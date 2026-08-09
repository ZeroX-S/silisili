/*
 * SiliSili native Sailfish hardware video path.
 * Copyright (C) 2026 SiliSili contributors
 * Copyright (C) 2026 RootGPT
 *
 * Derived from the FFmpeg -> droidmedia -> gralloc design used by
 * RooTheater-SailfishOS. This modified implementation keeps SiliSili's
 * separate libmpv audio clock and application-owned shared Cover texture.
 * GPL-3.0-or-later.
 */
#include "droidvideodecoder.h"
#include "mpvvideoitem.h"

#include <QByteArray>
#include <QDebug>
#include <QMetaObject>
#include <QThread>

#include <chrono>
#include <cstdlib>
#include <cstring>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>

#include <droidmedia.h>
#include <droidmediacodec.h>
}

namespace {

const size_t kMaximumDecodedFrames = 4;

long long steadyNowUs() {
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

struct CodecMap {
    AVCodecID codec;
    const char *mime;
    const char *bitstreamFilter;
    const char *label;
};

const CodecMap kCodecMap[] = {
    {AV_CODEC_ID_H264, "video/avc", "h264_mp4toannexb", "h264"},
    {AV_CODEC_ID_HEVC, "video/hevc", "hevc_mp4toannexb", "hevc"},
    {AV_CODEC_ID_VP9, "video/x-vnd.on2.vp9", 0, "vp9"},
    {AV_CODEC_ID_VP8, "video/x-vnd.on2.vp8", 0, "vp8"},
    {AV_CODEC_ID_MPEG4, "video/mp4v-es", 0, "mpeg4"}
};

const CodecMap *codecMapFor(AVCodecID codec) {
    for (size_t index = 0; index < sizeof(kCodecMap) / sizeof(kCodecMap[0]); ++index) {
        if (kCodecMap[index].codec == codec) return &kCodecMap[index];
    }
    return 0;
}

bool frameAvailableCallback(void *data, DroidMediaBuffer *buffer) {
    static_cast<DroidVideoDecoder *>(data)->onFrameAvailable(buffer);
    return true;
}

bool bufferCreatedCallback(void *, DroidMediaBuffer *) { return true; }
void buffersReleasedCallback(void *) {}
void inputBufferRef(void *) {}
void inputBufferUnref(void *data) { std::free(data); }

} // namespace

DroidVideoDecoder::DroidVideoDecoder(MpvVideoItem *owner)
    : m_owner(owner), m_generation(0), m_active(false), m_stop(true),
      m_paused(false), m_failed(false), m_seekSerial(0), m_seekTargetUs(0),
      m_dropBeforeUs(0), m_format(0), m_bsf(0), m_videoStream(-1),
      m_codec(0), m_bufferQueue(0), m_guiPendingFrame(0),
      m_guiUpdateQueued(false), m_masterValid(false), m_masterRunning(false),
      m_masterPositionUs(0), m_masterAnchorUs(0), m_masterSpeed(1.0),
      m_startWallUs(0), m_firstVideoPtsUs(-1) {
}

DroidVideoDecoder::~DroidVideoDecoder() {
    stop();
}

bool DroidVideoDecoder::start(const QString &url, double startPosition) {
    stop();
    if (url.isEmpty() || !droid_media_init()) return false;
    m_url = url;
    const int nextGeneration = m_generation.fetch_add(1) + 1;
    m_stop.store(false);
    m_active.store(true);
    m_paused.store(false);
    m_failed.store(false);
    m_seekSerial.store(0);
    m_seekTargetUs.store(static_cast<long long>(qMax(0.0, startPosition) * 1000000.0));
    m_dropBeforeUs.store(qMax<long long>(0, m_seekTargetUs.load() - 100000));
    m_startWallUs = steadyNowUs();
    m_firstVideoPtsUs = -1;
    {
        std::lock_guard<std::mutex> lock(m_clockMutex);
        m_masterValid = false;
        m_masterRunning = false;
        m_masterPositionUs = m_seekTargetUs.load();
        m_masterAnchorUs = steadyNowUs();
        m_masterSpeed = 1.0;
    }
    m_presentThread = std::thread([this, nextGeneration]() {
        presentLoop(nextGeneration);
    });
    m_demuxThread = std::thread([this, nextGeneration]() {
        demuxLoop(nextGeneration);
    });
    qInfo() << "native hardware video: direct pipeline requested"
            << "generation" << nextGeneration
            << "start" << startPosition
            << "audioMaster" << "libmpv"
            << "decoder" << "droidmedia-omx";
    return true;
}

void DroidVideoDecoder::stop() {
    m_stop.store(true);
    m_active.store(false);
    m_frameReady.notify_all();
    m_frameSpace.notify_all();
    if (m_demuxThread.joinable()) m_demuxThread.join();
    if (m_presentThread.joinable()) m_presentThread.join();
    discardPendingFrame();
    clearDecodedFrames();
    teardownCodec();
}

void DroidVideoDecoder::seek(double position) {
    if (!m_active.load()) return;
    const long long targetUs = static_cast<long long>(qMax(0.0, position) * 1000000.0);
    m_seekTargetUs.store(targetUs);
    m_dropBeforeUs.store(qMax<long long>(0, targetUs - 100000));
    m_seekSerial.fetch_add(1);
    m_firstVideoPtsUs = -1;
    qInfo() << "native hardware video: in-place seek requested"
            << "position" << position
            << "generation" << m_generation.load();
}

void DroidVideoDecoder::setPaused(bool paused) {
    m_paused.store(paused);
    m_frameReady.notify_all();
}

void DroidVideoDecoder::updateMasterClock(double position, double speed, bool running) {
    std::lock_guard<std::mutex> lock(m_clockMutex);
    m_masterPositionUs = static_cast<long long>(qMax(0.0, position) * 1000000.0);
    m_masterAnchorUs = steadyNowUs();
    m_masterSpeed = qBound(0.25, speed, 4.0);
    m_masterRunning = running;
    m_masterValid = true;
}

long long DroidVideoDecoder::masterClockUs(bool *valid) const {
    std::lock_guard<std::mutex> lock(m_clockMutex);
    *valid = m_masterValid;
    if (!m_masterValid) return 0;
    if (!m_masterRunning) return m_masterPositionUs;
    const long long elapsedUs = steadyNowUs() - m_masterAnchorUs;
    return m_masterPositionUs + static_cast<long long>(elapsedUs * m_masterSpeed);
}

int DroidVideoDecoder::interruptCallback(void *data) {
    return static_cast<DroidVideoDecoder *>(data)->m_stop.load() ? 1 : 0;
}

bool DroidVideoDecoder::openInput(int generation) {
    avformat_network_init();
    m_format = avformat_alloc_context();
    if (!m_format) return false;
    m_format->interrupt_callback.callback = &DroidVideoDecoder::interruptCallback;
    m_format->interrupt_callback.opaque = this;

    AVDictionary *options = 0;
    av_dict_set(&options, "user_agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS", 0);
    av_dict_set(&options, "referer", "https://www.bilibili.com/", 0);
    av_dict_set(&options, "rw_timeout", "5000000", 0);
    const QByteArray source = m_url.toUtf8();
    const int openResult = avformat_open_input(&m_format, source.constData(), 0, &options);
    av_dict_free(&options);
    if (openResult < 0 || m_stop.load()) return false;
    if (avformat_find_stream_info(m_format, 0) < 0 || m_stop.load()) return false;

    m_videoStream = av_find_best_stream(m_format, AVMEDIA_TYPE_VIDEO, -1, -1, 0, 0);
    if (m_videoStream < 0) return false;
    AVStream *stream = m_format->streams[m_videoStream];
    const CodecMap *codecMap = codecMapFor(stream->codecpar->codec_id);
    if (!codecMap) {
        postFailure(generation, QStringLiteral("unsupported-video-codec"));
        return false;
    }

    if (codecMap->bitstreamFilter) {
        const AVBitStreamFilter *filter = av_bsf_get_by_name(codecMap->bitstreamFilter);
        if (!filter || av_bsf_alloc(filter, &m_bsf) < 0
                || avcodec_parameters_copy(m_bsf->par_in, stream->codecpar) < 0) {
            postFailure(generation, QStringLiteral("bitstream-filter-init"));
            return false;
        }
        m_bsf->time_base_in = stream->time_base;
        if (av_bsf_init(m_bsf) < 0) {
            postFailure(generation, QStringLiteral("bitstream-filter-start"));
            return false;
        }
    }

    DroidMediaCodecDecoderMetaData metadata;
    std::memset(&metadata, 0, sizeof(metadata));
    metadata.parent.type = codecMap->mime;
    metadata.parent.width = stream->codecpar->width;
    metadata.parent.height = stream->codecpar->height;
    const AVRational frameRate = stream->avg_frame_rate.num > 0
            ? stream->avg_frame_rate : stream->r_frame_rate;
    const double fps = frameRate.den > 0 ? av_q2d(frameRate) : 30.0;
    metadata.parent.fps = qMax(1, qRound(fps));
    metadata.parent.flags = DROID_MEDIA_CODEC_HW_ONLY;
    if (stream->codecpar->extradata && stream->codecpar->extradata_size > 0) {
        metadata.codec_data.data = stream->codecpar->extradata;
        metadata.codec_data.size = stream->codecpar->extradata_size;
    }
    if (!droid_media_codec_is_supported(&metadata.parent, false)) {
        postFailure(generation, QStringLiteral("hardware-codec-unsupported"));
        return false;
    }
    m_codec = droid_media_codec_create_decoder(&metadata);
    if (!m_codec) {
        postFailure(generation, QStringLiteral("hardware-codec-create"));
        return false;
    }

    DroidMediaCodecCallbacks codecCallbacks;
    std::memset(&codecCallbacks, 0, sizeof(codecCallbacks));
    codecCallbacks.signal_eos = &DroidVideoDecoder::eosCallback;
    codecCallbacks.error = &DroidVideoDecoder::errorCallback;
    codecCallbacks.size_changed = &DroidVideoDecoder::sizeChangedCallback;
    droid_media_codec_set_callbacks(m_codec, &codecCallbacks, this);

    m_bufferQueue = droid_media_codec_get_buffer_queue(m_codec);
    if (!m_bufferQueue) {
        postFailure(generation, QStringLiteral("hardware-buffer-queue"));
        return false;
    }
    DroidMediaBufferQueueCallbacks queueCallbacks;
    std::memset(&queueCallbacks, 0, sizeof(queueCallbacks));
    queueCallbacks.buffer_created = &bufferCreatedCallback;
    queueCallbacks.frame_available = &frameAvailableCallback;
    queueCallbacks.buffers_released = &buffersReleasedCallback;
    droid_media_buffer_queue_set_callbacks(m_bufferQueue, &queueCallbacks, this);
    if (!droid_media_codec_start(m_codec)) {
        postFailure(generation, QStringLiteral("hardware-codec-start"));
        return false;
    }

    const long long startUs = m_seekTargetUs.load();
    if (startUs > 0) {
        av_seek_frame(m_format, -1,
                      av_rescale_q(startUs, AVRational{1, 1000000}, AV_TIME_BASE_Q),
                      AVSEEK_FLAG_BACKWARD);
        if (m_bsf) av_bsf_flush(m_bsf);
    }
    QMetaObject::invokeMethod(m_owner, "hardwareStreamReady", Qt::QueuedConnection,
                              Q_ARG(int, generation),
                              Q_ARG(int, stream->codecpar->width),
                              Q_ARG(int, stream->codecpar->height),
                              Q_ARG(double, fps),
                              Q_ARG(QString, QString::fromLatin1(codecMap->label)));
    qInfo() << "native hardware video: OMX decoder started"
            << "generation" << generation
            << "codec" << codecMap->label
            << "mime" << codecMap->mime
            << "size" << stream->codecpar->width << "x" << stream->codecpar->height
            << "fps" << fps
            << "flags" << "HW_ONLY"
            << "cpuPixelCopies" << 0;
    return true;
}

void DroidVideoDecoder::queuePacket(const unsigned char *data, int size,
                                    long long ptsUs, bool keyFrame) {
    if (!m_codec || !data || size <= 0 || m_stop.load()) return;
    void *copy = std::malloc(static_cast<size_t>(size));
    if (!copy) return;
    std::memcpy(copy, data, static_cast<size_t>(size));
    DroidMediaCodecData codecData;
    std::memset(&codecData, 0, sizeof(codecData));
    codecData.data.data = copy;
    codecData.data.size = size;
    codecData.ts = ptsUs;
    codecData.decoding_ts = ptsUs;
    codecData.sync = keyFrame;
    DroidMediaBufferCallbacks callbacks;
    std::memset(&callbacks, 0, sizeof(callbacks));
    callbacks.ref = &inputBufferRef;
    callbacks.unref = &inputBufferUnref;
    callbacks.data = copy;
    droid_media_codec_queue(m_codec, &codecData, &callbacks);
}

void DroidVideoDecoder::demuxLoop(int generation) {
    if (!openInput(generation)) {
        if (!m_stop.load() && !m_failed.load())
            postFailure(generation, QStringLiteral("video-input-open"));
        return;
    }
    AVStream *stream = m_format->streams[m_videoStream];
    AVPacket *packet = av_packet_alloc();
    AVPacket *filtered = av_packet_alloc();
    int appliedSeekSerial = m_seekSerial.load();
    while (!m_stop.load() && !m_failed.load()) {
        if (m_paused.load()) {
            QThread::msleep(10);
            continue;
        }
        const int requestedSeekSerial = m_seekSerial.load();
        if (requestedSeekSerial != appliedSeekSerial) {
            appliedSeekSerial = requestedSeekSerial;
            clearDecodedFrames();
            discardPendingFrame();
            droid_media_codec_flush(m_codec);
            if (m_bsf) av_bsf_flush(m_bsf);
            const long long targetUs = m_seekTargetUs.load();
            av_seek_frame(m_format, -1,
                          av_rescale_q(targetUs, AVRational{1, 1000000}, AV_TIME_BASE_Q),
                          AVSEEK_FLAG_BACKWARD);
            qInfo() << "native hardware video: in-place seek applied"
                    << "generation" << generation
                    << "targetUs" << targetUs
                    << "decoderRecreated" << false;
        }
        if (av_read_frame(m_format, packet) < 0) break;
        if (packet->stream_index == m_videoStream) {
            if (m_bsf) {
                if (av_bsf_send_packet(m_bsf, packet) == 0) {
                    while (av_bsf_receive_packet(m_bsf, filtered) == 0) {
                        const long long ptsUs = filtered->pts == AV_NOPTS_VALUE ? 0
                                : av_rescale_q(filtered->pts, stream->time_base,
                                               AVRational{1, 1000000});
                        queuePacket(filtered->data, filtered->size, ptsUs,
                                    (filtered->flags & AV_PKT_FLAG_KEY) != 0);
                        av_packet_unref(filtered);
                    }
                }
            } else {
                const long long ptsUs = packet->pts == AV_NOPTS_VALUE ? 0
                        : av_rescale_q(packet->pts, stream->time_base,
                                       AVRational{1, 1000000});
                queuePacket(packet->data, packet->size, ptsUs,
                            (packet->flags & AV_PKT_FLAG_KEY) != 0);
            }
        }
        av_packet_unref(packet);
    }
    if (!m_stop.load() && !m_failed.load() && m_codec)
        droid_media_codec_drain(m_codec);
    av_packet_free(&filtered);
    av_packet_free(&packet);
}

void DroidVideoDecoder::onFrameAvailable(_DroidMediaBuffer *buffer) {
    if (!buffer) return;
    if (m_stop.load() || m_failed.load()) {
        droid_media_buffer_release(buffer, 0, 0);
        return;
    }
    DroidMediaBufferInfo info;
    std::memset(&info, 0, sizeof(info));
    droid_media_buffer_get_info(buffer, &info);
    const long long ptsUs = info.timestamp / 1000;
    std::unique_lock<std::mutex> lock(m_frameMutex);
    m_frameSpace.wait(lock, [this]() {
        return m_stop.load() || m_frames.size() < kMaximumDecodedFrames;
    });
    if (m_stop.load()) {
        lock.unlock();
        droid_media_buffer_release(buffer, 0, 0);
        return;
    }
    m_frames.push_back(PendingFrame{buffer, ptsUs});
    lock.unlock();
    m_frameReady.notify_one();
}

void DroidVideoDecoder::presentLoop(int generation) {
    while (!m_stop.load()) {
        if (m_paused.load()) {
            QThread::msleep(10);
            continue;
        }
        PendingFrame frame = {0, 0};
        {
            std::unique_lock<std::mutex> lock(m_frameMutex);
            m_frameReady.wait(lock, [this]() {
                return m_stop.load() || !m_frames.empty();
            });
            if (m_stop.load()) break;
            frame = m_frames.front();
            m_frames.pop_front();
        }
        m_frameSpace.notify_one();
        if (frame.ptsUs < m_dropBeforeUs.load()) {
            droid_media_buffer_release(frame.buffer, 0, 0);
            continue;
        }

        bool clockValid = false;
        long long masterUs = masterClockUs(&clockValid);
        if (!clockValid && steadyNowUs() - m_startWallUs < 1500000) {
            do {
                QThread::msleep(4);
                masterUs = masterClockUs(&clockValid);
            } while (!m_stop.load() && !clockValid
                     && steadyNowUs() - m_startWallUs < 1500000);
        }
        if (clockValid) {
            while (!m_stop.load() && !m_paused.load()) {
                masterUs = masterClockUs(&clockValid);
                const long long aheadUs = frame.ptsUs - masterUs;
                if (!clockValid || aheadUs <= 2000) break;
                QThread::usleep(static_cast<unsigned long>(qMin<long long>(aheadUs, 20000)));
            }
            masterUs = masterClockUs(&clockValid);
            if (clockValid && masterUs - frame.ptsUs > 180000) {
                droid_media_buffer_release(frame.buffer, 0, 0);
                continue;
            }
        } else {
            if (m_firstVideoPtsUs < 0) {
                m_firstVideoPtsUs = frame.ptsUs;
                m_startWallUs = steadyNowUs();
            }
            const long long targetUs = frame.ptsUs - m_firstVideoPtsUs;
            const long long elapsedUs = steadyNowUs() - m_startWallUs;
            if (targetUs > elapsedUs)
                QThread::usleep(static_cast<unsigned long>(qMin<long long>(
                    targetUs - elapsedUs, 20000)));
        }
        if (m_stop.load()) {
            droid_media_buffer_release(frame.buffer, 0, 0);
            break;
        }
        offerFrameToGui(frame.buffer, generation);
    }
}

void DroidVideoDecoder::offerFrameToGui(_DroidMediaBuffer *buffer, int generation) {
    _DroidMediaBuffer *dropped = 0;
    {
        std::lock_guard<std::mutex> lock(m_guiMutex);
        dropped = m_guiPendingFrame;
        m_guiPendingFrame = buffer;
    }
    if (dropped) droid_media_buffer_release(dropped, 0, 0);
    bool expected = false;
    if (m_guiUpdateQueued.compare_exchange_strong(expected, true)) {
        QMetaObject::invokeMethod(m_owner, "renderPendingHardwareFrame",
                                  Qt::QueuedConnection, Q_ARG(int, generation));
    }
}

_DroidMediaBuffer *DroidVideoDecoder::takePendingFrame(int generation) {
    if (generation != m_generation.load()) return 0;
    std::lock_guard<std::mutex> lock(m_guiMutex);
    _DroidMediaBuffer *buffer = m_guiPendingFrame;
    m_guiPendingFrame = 0;
    return buffer;
}

void DroidVideoDecoder::frameRenderCompleted(int generation) {
    m_guiUpdateQueued.store(false);
    if (generation != m_generation.load() || m_stop.load()) return;
    bool hasPending = false;
    {
        std::lock_guard<std::mutex> lock(m_guiMutex);
        hasPending = m_guiPendingFrame != 0;
    }
    bool expected = false;
    if (hasPending && m_guiUpdateQueued.compare_exchange_strong(expected, true)) {
        QMetaObject::invokeMethod(m_owner, "renderPendingHardwareFrame",
                                  Qt::QueuedConnection, Q_ARG(int, generation));
    }
}

void DroidVideoDecoder::discardPendingFrame() {
    _DroidMediaBuffer *buffer = 0;
    {
        std::lock_guard<std::mutex> lock(m_guiMutex);
        buffer = m_guiPendingFrame;
        m_guiPendingFrame = 0;
    }
    if (buffer) droid_media_buffer_release(buffer, 0, 0);
    m_guiUpdateQueued.store(false);
}

void DroidVideoDecoder::clearDecodedFrames() {
    std::deque<PendingFrame> frames;
    {
        std::lock_guard<std::mutex> lock(m_frameMutex);
        frames.swap(m_frames);
    }
    for (std::deque<PendingFrame>::const_iterator frame = frames.begin();
         frame != frames.end(); ++frame) {
        if (frame->buffer) droid_media_buffer_release(frame->buffer, 0, 0);
    }
    m_frameSpace.notify_all();
}

void DroidVideoDecoder::postFailure(int generation, const QString &reason) {
    bool expected = false;
    if (!m_failed.compare_exchange_strong(expected, true)) return;
    qWarning() << "native hardware video: direct pipeline failed"
               << "generation" << generation
               << "reason" << reason
               << "fallback" << "software-same-position";
    QMetaObject::invokeMethod(m_owner, "hardwareDecodeFailed", Qt::QueuedConnection,
                              Q_ARG(int, generation), Q_ARG(QString, reason));
}

void DroidVideoDecoder::eosCallback(void *data) {
    DroidVideoDecoder *decoder = static_cast<DroidVideoDecoder *>(data);
    qInfo() << "native hardware video: decoder EOS"
            << "generation" << decoder->generation();
}

void DroidVideoDecoder::errorCallback(void *data, int error) {
    DroidVideoDecoder *decoder = static_cast<DroidVideoDecoder *>(data);
    decoder->postFailure(decoder->generation(),
                         QStringLiteral("omx-runtime-%1").arg(error));
}

int DroidVideoDecoder::sizeChangedCallback(void *, int, int) {
    return 0;
}

void DroidVideoDecoder::teardownCodec() {
    if (m_codec) {
        droid_media_codec_stop(m_codec);
        droid_media_codec_destroy(m_codec);
        m_codec = 0;
        m_bufferQueue = 0;
    }
    if (m_bsf) av_bsf_free(&m_bsf);
    if (m_format) avformat_close_input(&m_format);
    m_videoStream = -1;
}
