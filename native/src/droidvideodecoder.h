/*
 * SiliSili native Sailfish hardware video path.
 * Copyright (C) 2026 SiliSili contributors
 * Copyright (C) 2026 RootGPT
 *
 * This implementation is based on the direct droidmedia architecture from
 * RooTheater-SailfishOS and is distributed under GPL-3.0-or-later.
 */
#pragma once

#include <QString>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

class MpvVideoItem;
struct _DroidMediaBuffer;
struct _DroidMediaBufferQueue;
struct _DroidMediaCodec;
struct AVBSFContext;
struct AVFormatContext;

class DroidVideoDecoder {
public:
    explicit DroidVideoDecoder(MpvVideoItem *owner);
    ~DroidVideoDecoder();

    bool start(const QString &url, double startPosition,
               bool normalizeStreamingTimeline = false);
    void stop();
    void seek(double position);
    void setPaused(bool paused);
    void updateMasterClock(double position, double speed, bool running);

    bool active() const { return m_active.load(); }
    int generation() const { return m_generation.load(); }

    _DroidMediaBuffer *takePendingFrame(int generation);
    void frameRenderCompleted(int generation);
    void discardPendingFrame();

    bool onBufferCreated(_DroidMediaBuffer *buffer);
    void onBuffersReleased();
    void onFrameAvailable(_DroidMediaBuffer *buffer);

private:
    struct PendingFrame {
        _DroidMediaBuffer *buffer;
        long long ptsUs;
    };

    static void eosCallback(void *data);
    static void errorCallback(void *data, int error);
    static int sizeChangedCallback(void *data, int width, int height);
    static int interruptCallback(void *data);

    bool openInput(int generation);
    void demuxLoop(int generation);
    void presentLoop(int generation);
    bool queuePacket(const unsigned char *data, int size, long long ptsUs,
                     bool keyFrame, int seekSerial);
    void offerFrameToGui(_DroidMediaBuffer *buffer, int generation);
    void clearDecodedFrames();
    void postFailure(int generation, const QString &reason);
    long long masterClockUs(bool *valid) const;
    void releaseCreatedBufferReferences(const char *reason);
    void teardownCodec();

    MpvVideoItem *m_owner;
    QString m_url;
    std::atomic<int> m_generation;
    std::atomic<bool> m_active;
    std::atomic<bool> m_stop;
    std::atomic<bool> m_paused;
    std::atomic<bool> m_failed;
    std::atomic<bool> m_ultraHdSource;
    std::atomic<int> m_seekSerial;
    std::atomic<long long> m_seekTargetUs;
    std::atomic<long long> m_dropBeforeUs;
    std::atomic<bool> m_normalizeStreamingTimeline;
    std::atomic<bool> m_inputTimestampOriginSet;
    std::atomic<long long> m_inputTimestampOriginUs;

    AVFormatContext *m_format;
    AVBSFContext *m_bsf;
    int m_videoStream;
    _DroidMediaCodec *m_codec;
    _DroidMediaBufferQueue *m_bufferQueue;
    std::vector<_DroidMediaBuffer *> m_createdBuffers;
    mutable std::mutex m_createdBufferMutex;
    std::atomic<int> m_createdBufferReferenceCount;
    std::atomic<int> m_destroyedBufferReferenceCount;
    std::atomic<bool> m_bufferQueueReleased;

    std::thread m_demuxThread;
    std::thread m_presentThread;
    std::deque<PendingFrame> m_frames;
    mutable std::mutex m_frameMutex;
    std::condition_variable m_frameReady;
    std::condition_variable m_frameSpace;
    int m_inFlightPackets;
    std::atomic<bool> m_targetFrameReached;
    std::atomic<int> m_maxDecodedFrames;
    std::atomic<int> m_maxCodecPackets;
    std::atomic<int> m_callbackFrameDrops;
    std::atomic<bool> m_feedThrottleLogged;

    _DroidMediaBuffer *m_guiPendingFrame;
    mutable std::mutex m_guiMutex;
    std::atomic<bool> m_guiUpdateQueued;

    mutable std::mutex m_clockMutex;
    bool m_masterValid;
    bool m_masterRunning;
    long long m_masterPositionUs;
    long long m_masterAnchorUs;
    double m_masterSpeed;
    long long m_startWallUs;
    long long m_firstVideoPtsUs;
};
