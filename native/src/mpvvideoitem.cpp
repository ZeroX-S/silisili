#include "mpvvideoitem.h"
#include "droidvideodecoder.h"

#include <QByteArray>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMutex>
#include <QMutexLocker>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFramebufferObjectFormat>
#include <QOpenGLFunctions>
#include <QOpenGLShaderProgram>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QSurfaceFormat>
#include <QVariant>
#include <QVector>

#include <clocale>
#include <cstring>

#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

// EGL/GLES must be included before droidmedia because the latter exposes the
// same EGL handle typedefs for its C ABI.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

extern "C" {
#include <droidmedia.h>
#include <droidmediacodec.h>
}

namespace {
const double kMinimumPlaybackFrameRate = 45.0;
const int kFrameFloorQualificationWindows = 60;

PFNEGLCREATEIMAGEKHRPROC hardwareEglCreateImage = 0;
PFNEGLDESTROYIMAGEKHRPROC hardwareEglDestroyImage = 0;
PFNGLEGLIMAGETARGETTEXTURE2DOESPROC hardwareGlImageTargetTexture = 0;
PFNEGLCREATESYNCKHRPROC hardwareEglCreateSync = 0;
PFNEGLCLIENTWAITSYNCKHRPROC hardwareEglClientWaitSync = 0;
PFNEGLDESTROYSYNCKHRPROC hardwareEglDestroySync = 0;

bool resolveHardwareTextureFunctions() {
    if (!hardwareEglCreateImage) {
        hardwareEglCreateImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
                    eglGetProcAddress("eglCreateImageKHR"));
        hardwareEglDestroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
                    eglGetProcAddress("eglDestroyImageKHR"));
        hardwareGlImageTargetTexture =
                reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
                    eglGetProcAddress("glEGLImageTargetTexture2DOES"));
        hardwareEglCreateSync = reinterpret_cast<PFNEGLCREATESYNCKHRPROC>(
                    eglGetProcAddress("eglCreateSyncKHR"));
        hardwareEglClientWaitSync = reinterpret_cast<PFNEGLCLIENTWAITSYNCKHRPROC>(
                    eglGetProcAddress("eglClientWaitSyncKHR"));
        hardwareEglDestroySync = reinterpret_cast<PFNEGLDESTROYSYNCKHRPROC>(
                    eglGetProcAddress("eglDestroySyncKHR"));
    }
    return hardwareEglCreateImage && hardwareEglDestroyImage
            && hardwareGlImageTargetTexture;
}

int testHardwareStallTargetCount() {
    bool countReady = false;
    const int requestedCount = QString::fromLocal8Bit(
                qgetenv("SILISILI_NATIVE_TEST_HARDWARE_STALL_COUNT"))
            .trimmed().toInt(&countReady);
    if (countReady && requestedCount > 0)
        return qBound(1, requestedCount, 12);
    return qgetenv("SILISILI_NATIVE_TEST_HARDWARE_STALL_ONCE")
            == QByteArrayLiteral("1") ? 1 : 0;
}

QSize fittedVideoViewport(const QSize &textureSize,
                          int sourceWidth, int sourceHeight) {
    if (textureSize.width() < 1 || textureSize.height() < 1
            || sourceWidth < 1 || sourceHeight < 1)
        return QSize();
    const double sourceAspect = static_cast<double>(sourceWidth) / sourceHeight;
    const double textureAspect = static_cast<double>(textureSize.width())
            / textureSize.height();
    if (sourceAspect > textureAspect) {
        return QSize(textureSize.width(),
                     qMax(1, qRound(textureSize.width() / sourceAspect)));
    }
    return QSize(qMax(1, qRound(textureSize.height() * sourceAspect)),
                 textureSize.height());
}
}

// libmpv renders into application-owned textures through this offscreen context.
// The context and textures live for the whole process and are shared with the
// Qt Quick scene graph, so Lipstick can replace its Cover surface without
// disabling video or forcing a CPU copy of every frame.
class MpvVideoBackend {
public:
    struct RetiredFramebufferSet {
        QOpenGLFramebufferObject *first;
        QOpenGLFramebufferObject *second;
        int framesUntilRelease;
    };

    struct DeferredHardwareBuffer {
        DroidMediaBuffer *buffer;
        EGLDisplay display;
        EGLSyncKHR fence;
    };

    MpvVideoBackend()
        : mpv(0), renderContext(0), renderGlContext(0), renderSurface(0),
          hardwareProgram(0), hardwareExternalTexture(0),
          activeFramebuffer(-1), pendingFramebuffer(-1), framebufferGeneration(0),
          presentationEnabled(false),
          loadPending(false), pendingStart(0.0),
          pendingPause(false) {
        framebuffers[0] = 0;
        framebuffers[1] = 0;
    }

    ~MpvVideoBackend() {
        QMutexLocker locker(&mutex);
        const bool contextCurrent = renderGlContext && renderSurface
                && renderGlContext->makeCurrent(renderSurface);
        if (renderContext) {
            mpv_render_context_set_update_callback(renderContext, 0, 0);
            mpv_render_context_free(renderContext);
            renderContext = 0;
            qInfo() << "native player: persistent shared-texture render context destroyed";
        }
        if (contextCurrent) {
            // Every deferred buffer is protected by a fence inserted after the
            // external-OES sample was submitted. Shutdown is the only place
            // where waiting for all outstanding GPU reads is appropriate.
            for (int index = 0; index < deferredHardwareBuffers.size(); ++index) {
                DeferredHardwareBuffer &pending = deferredHardwareBuffers[index];
                if (pending.fence != EGL_NO_SYNC_KHR && hardwareEglClientWaitSync)
                    hardwareEglClientWaitSync(pending.display, pending.fence,
                                              EGL_SYNC_FLUSH_COMMANDS_BIT_KHR,
                                              EGL_FOREVER_KHR);
                if (pending.fence != EGL_NO_SYNC_KHR && hardwareEglDestroySync)
                    hardwareEglDestroySync(pending.display, pending.fence);
                if (pending.buffer)
                    droid_media_buffer_release(pending.buffer, pending.display, 0);
            }
            deferredHardwareBuffers.clear();
            delete hardwareProgram;
            hardwareProgram = 0;
            if (hardwareExternalTexture) {
                renderGlContext->functions()->glDeleteTextures(
                            1, &hardwareExternalTexture);
                hardwareExternalTexture = 0;
            }
            delete framebuffers[0];
            delete framebuffers[1];
            framebuffers[0] = 0;
            framebuffers[1] = 0;
            for (int index = 0; index < retiredFramebuffers.size(); ++index) {
                delete retiredFramebuffers[index].first;
                delete retiredFramebuffers[index].second;
            }
            retiredFramebuffers.clear();
            renderGlContext->doneCurrent();
        } else if (framebuffers[0] || framebuffers[1] || !retiredFramebuffers.isEmpty()) {
            // At process shutdown the EGL display may already be unavailable.
            // Avoid issuing GL deletes without the context that owns them.
            qWarning() << "native player: offscreen context unavailable during texture cleanup";
        }
        if (mpv) {
            mpv_set_wakeup_callback(mpv, 0, 0);
            mpv_terminate_destroy(mpv);
            mpv = 0;
            qInfo() << "native player: persistent mpv instance destroyed";
        }
        delete renderSurface;
        renderSurface = 0;
        delete renderGlContext;
        renderGlContext = 0;
    }

    QMutex mutex;
    mpv_handle *mpv;
    mpv_render_context *renderContext;
    QOpenGLContext *renderGlContext;
    QOffscreenSurface *renderSurface;
    QOpenGLShaderProgram *hardwareProgram;
    GLuint hardwareExternalTexture;
    QOpenGLFramebufferObject *framebuffers[2];
    int activeFramebuffer;
    int pendingFramebuffer;
    int framebufferGeneration;
    QVector<RetiredFramebufferSet> retiredFramebuffers;
    QVector<DeferredHardwareBuffer> deferredHardwareBuffers;
    bool presentationEnabled;
    bool loadPending;
    double pendingStart;
    bool pendingPause;
};

class SharedTextureNode : public QSGSimpleTextureNode {
public:
    SharedTextureNode() { setOwnsTexture(true); }

    void replaceTexture(QSGTexture *nextTexture) {
        QSGTexture *previousTexture = texture();
        setOwnsTexture(false);
        setTexture(nextTexture);
        setOwnsTexture(true);
        delete previousTexture;
    }
};

static void *sharedTextureGetProcAddress(void *context, const char *name) {
    QOpenGLContext *glContext = static_cast<QOpenGLContext *>(context);
    if (!glContext || !name) return 0;
    return reinterpret_cast<void *>(glContext->getProcAddress(QByteArray(name)));
}

static void onMpvWakeup(void *context) {
    MpvVideoItem *item = static_cast<MpvVideoItem *>(context);
    if (item)
        QMetaObject::invokeMethod(item, "drainMpvEvents", Qt::QueuedConnection);
}

static QString mpvStringProperty(mpv_handle *mpv, const char *name) {
    char *value = mpv ? mpv_get_property_string(mpv, name) : 0;
    const QString result = value ? QString::fromUtf8(value) : QStringLiteral("unavailable");
    if (value) mpv_free(value);
    return result;
}

static QString activeV4l2Device() {
    const QDir fdDirectory(QStringLiteral("/proc/self/fd"));
    const QStringList entries = fdDirectory.entryList(
                QDir::AllEntries | QDir::System | QDir::NoDotAndDotDot);
    for (int index = 0; index < entries.size(); ++index) {
        const QFileInfo descriptor(fdDirectory.absoluteFilePath(entries.at(index)));
        const QString target = descriptor.symLinkTarget();
        if (target.startsWith(QStringLiteral("/dev/video")))
            return target;
    }
    return QString();
}

MpvVideoItem::MpvVideoItem(QQuickItem *parent)
    : QQuickItem(parent), m_backend(new MpvVideoBackend),
      m_hardwareDecoder(new DroidVideoDecoder(this)),
      m_liveStreamSource(false),
      m_sharedTextureRenderQueued(0), m_sharedTextureFrameSerial(0),
      m_presentedTextureWidth(0), m_presentedTextureHeight(0),
      m_presentedVideoWidth(0), m_presentedVideoHeight(0),
      m_lastCoverSwapFrameSerial(0), m_coverSwapCadenceFrames(0),
      m_frameFloorWindowFrames(0), m_frameFloorWindowCount(0),
      m_frameFloorBelowThresholdCount(0), m_frameFloorMinimumFps(0.0),
      m_sourceFrameRate(0.0),
      m_textureSharingLogged(false),
      m_fullResolutionPresentation(false),
      m_hardwareDecodeActive(false), m_hardwareFallbackForCurrentLoad(false),
      m_hardwareFirstFramePending(false), m_hardwarePresentationCadenceLogged(false),
      m_hardwareStallObservedSerial(0), m_hardwareStallObservedPosition(0.0),
      m_hardwareStallRecoveryCount(0),
      m_testHardwareStallEnabled(
          testHardwareStallTargetCount() > 0),
      m_testHardwareStallInjected(false), m_testHardwareStallGeneration(0),
      m_testHardwareStallTargetCount(testHardwareStallTargetCount()),
      m_testHardwareStallInjectedCount(0),
      m_testHardwareStallNextFrameSerial(
          testHardwareStallTargetCount() > 1 ? 180 : 60),
      m_foregroundRestoreStage(0), m_progressClockTicks(0), m_loadSerial(0),
      m_loadCommandPending(false), m_pendingLoadStart(0.0), m_pendingLoadPause(false),
      m_initialPositionGatePending(false), m_initialPositionConfirmed(false),
      m_initialVideoFrameReady(false),
      m_requestedPaused(false), m_requestedPosition(0.0), m_requestedVolume(100.0),
      m_requestedBrightness(0.0), m_requestedSpeed(1.0), m_paused(false), m_loading(false), m_playing(false),
      m_ended(false), m_playbackStarted(false), m_sourceFileStartedForPresentation(false),
      m_pendingGeometryLogEmitted(false),
      m_dropVideoGeometryEventForTest(
          qgetenv("SILISILI_NATIVE_TEST_DROP_VIDEO_GEOMETRY_EVENT") == QByteArrayLiteral("1")),
      m_videoEnabled(true),
      m_seekPending(false), m_buffering(false), m_position(0.0), m_duration(0.0),
      m_volume(100.0), m_brightness(0.0), m_speed(1.0), m_videoWidth(0), m_videoHeight(0) {
    setFlag(QQuickItem::ItemHasContents, true);
    m_progressClockTimer.setInterval(100);
    m_progressClockTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_progressClockTimer, &QTimer::timeout,
            this, &MpvVideoItem::advanceProgressClock);
    // Hardware decoders publish at the source cadence (commonly 30 FPS), while
    // the phone display refreshes at 60 Hz. Re-present the current shared FBO
    // at the display cadence so Qt/Lipstick never falls back to sporadic scene
    // graph swaps between decoder frames. This repeats presentation only: it
    // does not decode, copy, mutate or count a second source frame.
    m_hardwarePresentationTimer.setInterval(16);
    m_hardwarePresentationTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_hardwarePresentationTimer, &QTimer::timeout, this, [this]() {
        if (!m_hardwareDecodeActive || !m_playing || m_paused || m_loading
                || m_ended || m_buffering || m_seekPending
                || m_sharedTextureFrameSerial <= 0)
            return;
        if (qApp && qApp->applicationState() == Qt::ApplicationActive)
            update();
    });
    m_hardwareStallTimer.setInterval(500);
    m_hardwareStallTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_hardwareStallTimer, &QTimer::timeout,
            this, &MpvVideoItem::monitorHardwareProgress);
    m_hardwareFirstFrameTimer.setSingleShot(true);
    // UHD opt-in retains the short allocation-safety deadline. Ordinary
    // 1080P hardware startup gets a wider deadline so a busy adaptation does
    // not unnecessarily restart the same source in software.
    m_hardwareFirstFrameTimer.setInterval(3500);
    m_hardwareFirstFrameTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_hardwareFirstFrameTimer, &QTimer::timeout, this, [this]() {
        if (!m_hardwareDecodeActive || !m_hardwareFirstFramePending) return;
        m_hardwareFirstFramePending = false;
        const int stalledLoadSerial = m_loadSerial;
        const int stalledWidth = m_videoWidth;
        const int stalledHeight = m_videoHeight;
        const double stalledFps = m_sourceFrameRate;
        qWarning() << "native hardware video: first-frame watchdog expired"
                   << "loadSerial" << stalledLoadSerial
                   << "geometry" << stalledWidth << "x" << stalledHeight
                   << "sourceFps" << stalledFps
                   << "deadlineMs" << m_hardwareFirstFrameTimer.interval();
        if (static_cast<long long>(stalledWidth) * stalledHeight
                <= 1920LL * 1080LL) {
            fallbackToSoftwareDecode(QStringLiteral("first-frame-timeout"));
            return;
        }
        stopHardwareDecode();
        emit hardwareFirstFrameTimedOut(stalledLoadSerial, stalledWidth,
                                        stalledHeight, stalledFps);
    });
    m_foregroundRestoreTimer.setSingleShot(true);
    connect(&m_foregroundRestoreTimer, &QTimer::timeout, this, [this]() {
        if (!qApp || qApp->applicationState() != Qt::ApplicationActive
                || m_sourceUrl.isEmpty() || !m_backend || !m_backend->mpv)
            return;
        if (m_foregroundRestoreStage == 0)
            prepareForegroundSurface();
        else
            refreshVideoOutput();
        ++m_foregroundRestoreStage;
        // The first active repaint can happen before Lipstick has rebuilt the
        // visible FBO. Follow it with cheap repaint requests, but never seek
        // or reload the stream (which previously caused black/stalled video).
        if (m_foregroundRestoreStage < 4) {
            const int delays[] = {120, 260, 560};
            m_foregroundRestoreTimer.start(delays[m_foregroundRestoreStage - 1]);
        }
    });
    connect(qApp, &QGuiApplication::applicationStateChanged, this,
            [this](Qt::ApplicationState state) {
        if (state != Qt::ApplicationActive) {
            m_foregroundRestoreTimer.stop();
            m_lastCoverSwapFrameSerial = 0;
            m_coverSwapCadenceFrames = 0;
            m_coverSwapCadenceTimer.invalidate();
            return;
        }
        m_lastCoverSwapFrameSerial = 0;
        m_coverSwapCadenceFrames = 0;
        m_coverSwapCadenceTimer.invalidate();
        scheduleForegroundRestore();
    });
}

double MpvVideoItem::position() const {
    if (m_seekPending) return m_requestedPosition;
    double displayedPosition = m_position;
    if (m_playing && !m_paused && !m_loading && !m_ended && !m_buffering
            && m_positionAnchorTimer.isValid()) {
        displayedPosition += (static_cast<double>(m_positionAnchorTimer.elapsed()) / 1000.0)
                             * m_speed;
    }
    if (displayedPosition < 0.0) displayedPosition = 0.0;
    if (m_duration > 0.0 && displayedPosition > m_duration)
        displayedPosition = m_duration;
    return displayedPosition;
}

bool MpvVideoItem::rendererReady() const {
    if (!m_backend) return false;
    QMutexLocker locker(&m_backend->mutex);
    return m_backend->mpv && m_backend->renderContext
            && m_backend->renderGlContext && m_backend->renderSurface;
}

void MpvVideoItem::prewarm() {
    QElapsedTimer elapsed;
    elapsed.start();
    const bool ready = ensureMpv();
    qInfo() << "native player: persistent software pipeline prewarm"
            << "ready" << ready
            << "elapsedMs" << elapsed.elapsed()
            << "globalShare" << (QOpenGLContext::globalShareContext() != 0);
}

void MpvVideoItem::resetProgressAnchor() {
    m_positionAnchorTimer.restart();
}

void MpvVideoItem::syncProgressClock() {
    syncHardwareClock();
    const bool shouldRun = m_playing && !m_paused && !m_loading && !m_ended
                           && !m_buffering && !m_sourceUrl.isEmpty();
    if (shouldRun == m_progressClockTimer.isActive()) return;
    if (!shouldRun) {
        m_progressClockTimer.stop();
        return;
    }
    if (!m_positionAnchorTimer.isValid()) resetProgressAnchor();
    m_progressClockTicks = 0;
    m_progressCadenceTimer.restart();
    m_progressClockTimer.start();
    qInfo() << "native player: progress clock started"
            << "intervalMs" << m_progressClockTimer.interval()
            << "position" << position();
}

void MpvVideoItem::advanceProgressClock() {
    if (!m_playing || m_paused || m_loading || m_ended || m_buffering
            || m_sourceUrl.isEmpty()) {
        syncProgressClock();
        return;
    }
    ++m_progressClockTicks;
    syncHardwareClock();
    emit positionChanged();
    if (m_progressClockTicks == 10) {
        qInfo() << "native player: progress clock cadence"
                << "ticks" << m_progressClockTicks
                << "elapsedMs" << m_progressCadenceTimer.elapsed()
                << "intervalMs" << m_progressClockTimer.interval()
                << "position" << position();
    }
}

void MpvVideoItem::resetFrameFloorWindow() {
    m_frameFloorWindowTimer.invalidate();
    m_frameFloorWindowFrames = 0;
}

void MpvVideoItem::resetFrameFloorQualification() {
    resetFrameFloorWindow();
    m_frameFloorWindowCount = 0;
    m_frameFloorBelowThresholdCount = 0;
    m_frameFloorMinimumFps = 0.0;
    m_sourceFrameRate = 0.0;
}

void MpvVideoItem::recordPresentedFrameForFloor() {
    // A source below 45 FPS cannot provide 45 unique frames. Apply the hard
    // floor to high-frame-rate media while it is actively playing; paused and
    // real cache-buffering intervals restart a clean measurement window.
    const bool eligible = m_sourceFrameRate + 0.5 >= kMinimumPlaybackFrameRate
                          && m_playing && !m_paused && !m_loading && !m_ended
                          && !m_buffering;
    if (!eligible) {
        resetFrameFloorWindow();
        return;
    }
    if (!m_frameFloorWindowTimer.isValid()) {
        m_frameFloorWindowFrames = 1;
        m_frameFloorWindowTimer.start();
        return;
    }

    ++m_frameFloorWindowFrames;
    const qint64 elapsedMs = m_frameFloorWindowTimer.elapsed();
    if (elapsedMs < 1000) return;

    const double framesPerSecond = m_frameFloorWindowFrames * 1000.0 / elapsedMs;
    ++m_frameFloorWindowCount;
    if (m_frameFloorWindowCount == 1 || framesPerSecond < m_frameFloorMinimumFps)
        m_frameFloorMinimumFps = framesPerSecond;
    const bool belowThreshold = framesPerSecond + 0.001 < kMinimumPlaybackFrameRate;
    if (belowThreshold) ++m_frameFloorBelowThresholdCount;

    qInfo() << "native player: frame floor window"
            << "index" << m_frameFloorWindowCount
            << "frames" << m_frameFloorWindowFrames
            << "elapsedMs" << elapsedMs
            << "fps" << framesPerSecond
            << "minimumFps" << m_frameFloorMinimumFps
            << "thresholdFps" << kMinimumPlaybackFrameRate
            << "sourceFps" << m_sourceFrameRate
            << "belowThreshold" << belowThreshold;
    if (belowThreshold) {
        qWarning() << "native player: frame floor violation"
                   << "index" << m_frameFloorWindowCount
                   << "fps" << framesPerSecond
                   << "thresholdFps" << kMinimumPlaybackFrameRate;
    }
    if (m_frameFloorWindowCount == kFrameFloorQualificationWindows)
        reportFrameFloorSummary("continuous-60s");

    m_frameFloorWindowFrames = 0;
    m_frameFloorWindowTimer.restart();
}

void MpvVideoItem::reportFrameFloorSummary(const char *reason) {
    if (m_frameFloorWindowCount <= 0) return;
    qInfo() << "native player: frame floor summary"
            << "reason" << reason
            << "windows" << m_frameFloorWindowCount
            << "minimumFps" << m_frameFloorMinimumFps
            << "thresholdFps" << kMinimumPlaybackFrameRate
            << "sourceFps" << m_sourceFrameRate
            << "belowThreshold" << m_frameFloorBelowThresholdCount
            << "qualified" << (m_frameFloorWindowCount >= kFrameFloorQualificationWindows
                                && m_frameFloorBelowThresholdCount == 0);
}

bool MpvVideoItem::ensureMpv() {
    if (!m_backend) return false;
    {
        QMutexLocker locker(&m_backend->mutex);
        if (m_backend->mpv) return true;
    }

    // Create the client handle lazily on the GUI thread. This keeps a transient
    // libmpv startup failure from poisoning the whole application session before
    // the user actually opens a video, and gives later playback attempts a clean
    // retry path.
    std::setlocale(LC_NUMERIC, "C");
    mpv_handle *handle = mpv_create();
    if (!handle) {
        m_errorMessage = QStringLiteral("无法创建 mpv 实例");
        qWarning() << "native player: mpv_create failed; client api"
                   << mpv_client_api_version();
        emit stateChanged();
        return false;
    }
    qInfo() << "native player: persistent mpv instance created"
            << "client api" << mpv_client_api_version();

    mpv_set_option_string(handle, "vo", "libmpv");
    // libmpv remains the deterministic software fallback and, on the direct
    // droidmedia route, owns only audio plus the master playback clock.
    mpv_set_option_string(handle, "hwdec", "no");
    mpv_set_option_string(handle, "keepaspect", "yes");
    mpv_set_option_string(handle, "video-unscaled", "no");
    mpv_set_option_string(handle, "panscan", "0");
    mpv_set_option_string(handle, "video-zoom", "0");
    mpv_set_option_string(handle, "video-pan-x", "0");
    mpv_set_option_string(handle, "video-pan-y", "0");
    mpv_set_option_string(handle, "video-scale-x", "1");
    mpv_set_option_string(handle, "video-scale-y", "1");
    mpv_set_option_string(handle, "vd-lavc-dr", "no");
    // Keep decode headroom for the 45 FPS floor without touching the retained
    // renderer, texture pool, playback clock or Cover lifecycle.
    // The phone hotplugs CPU cores aggressively and libavcodec's automatic
    // count has varied between three and four workers across identical cold
    // starts. Pin four workers for predictable 1080p60 startup and transport.
    mpv_set_option_string(handle, "vd-lavc-threads", "4");
    mpv_set_option_string(handle, "vd-lavc-fast", "yes");
    mpv_set_option_string(handle, "vd-lavc-skiploopfilter", "nonref");
    // The service commonly offers either 1080P60 or 720P30, with no 720P60
    // representation. Decode the stable 720p stream, then let mpv synthesize
    // intermediate presentation frames at the device refresh rate. This keeps
    // decoder load low without merely counting duplicated 30 FPS textures.
    mpv_set_option_string(handle, "video-sync", "display-resample");
    mpv_set_option_string(handle, "interpolation", "yes");
    mpv_set_option_string(handle, "tscale", "oversample");
    mpv_set_option_string(handle, "display-fps-override", "60");
    mpv_set_option_string(handle, "correct-downscaling", "no");
    mpv_set_option_string(handle, "sigmoid-upscaling", "no");
    mpv_set_option_string(handle, "deband", "no");
    mpv_set_option_string(handle, "scale", "bilinear");
    mpv_set_option_string(handle, "cscale", "bilinear");
    mpv_set_option_string(handle, "dscale", "bilinear");
    // Bilibili DASH tracks carry complete MP4 metadata. Avoid a long generic
    // probe window and keep PulseAudio's startup queue short; normal network
    // cache protection remains active once playback has begun.
    mpv_set_option_string(handle, "demuxer-lavf-analyzeduration", "0.1");
    mpv_set_option_string(handle, "demuxer-lavf-probesize", "32768");
    mpv_set_option_string(handle, "audio-buffer", "0.05");
    mpv_set_option_string(handle, "user-agent",
                          "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    mpv_set_option_string(handle, "referrer", "https://www.bilibili.com/");
    mpv_set_option_string(handle, "cache", "yes");
    // Do not hold the very first decoded frame merely to fill mpv's initial
    // network cache. Normal cache-pausing stays enabled for genuine later
    // underruns, so this reduces click-to-picture latency without trading away
    // playback stability after startup.
    mpv_set_option_string(handle, "cache-pause-initial", "no");
    mpv_set_option_string(handle, "terminal", "no");
    // Decoder debug spam competes with the GUI thread and journald during the
    // first-frame critical path. Application-owned state/timing markers remain
    // enabled; libmpv itself only needs to surface actionable warnings.
    mpv_request_log_messages(handle, "warn");
    if (mpv_initialize(handle) < 0) {
        m_errorMessage = QStringLiteral("mpv 初始化失败");
        qWarning() << "native player: mpv_initialize failed";
        mpv_terminate_destroy(handle);
        emit stateChanged();
        return false;
    }
    qInfo() << "native player: frame floor performance profile"
            << "hwdec" << mpvStringProperty(handle, "options/hwdec")
            << "decoderPriority" << mpvStringProperty(handle, "options/vd")
            << "threads" << mpvStringProperty(handle, "options/vd-lavc-threads")
            << "fast" << mpvStringProperty(handle, "options/vd-lavc-fast")
            << "skipLoopFilter" << mpvStringProperty(handle, "options/vd-lavc-skiploopfilter")
            << "interpolation" << mpvStringProperty(handle, "options/interpolation");
    QOpenGLContext *renderGlContext = new QOpenGLContext;
    QOpenGLContext *globalShareContext = QOpenGLContext::globalShareContext();
    // On Sailfish a direct initial live page can receive sceneGraphInitialized
    // before Qt publishes globalShareContext(). The QQuickWindow context is
    // already valid at that point, so use it as the explicit share parent.
    // The established 1.25 VOD path still selects globalShareContext whenever
    // it exists and is therefore unchanged.
    QOpenGLContext *windowShareContext = window() ? window()->openglContext() : 0;
    QOpenGLContext *shareContext = globalShareContext
            ? globalShareContext : windowShareContext;
    const QSurfaceFormat renderFormat = shareContext
            ? shareContext->format() : QSurfaceFormat::defaultFormat();
    renderGlContext->setFormat(renderFormat);
    if (shareContext)
        renderGlContext->setShareContext(shareContext);
    if (!renderGlContext->create()) {
        m_errorMessage = QStringLiteral("视频 OpenGL 上下文初始化失败");
        qWarning() << "native player: persistent offscreen OpenGL context creation failed";
        delete renderGlContext;
        mpv_terminate_destroy(handle);
        emit stateChanged();
        return false;
    }
    QOffscreenSurface *renderSurface = new QOffscreenSurface;
    renderSurface->setFormat(renderGlContext->format());
    renderSurface->create();
    if (!renderSurface->isValid() || !renderGlContext->makeCurrent(renderSurface)) {
        m_errorMessage = QStringLiteral("视频离屏渲染器初始化失败");
        qWarning() << "native player: persistent offscreen surface initialization failed";
        delete renderSurface;
        delete renderGlContext;
        mpv_terminate_destroy(handle);
        emit stateChanged();
        return false;
    }

    mpv_render_context *renderContext = 0;
    mpv_opengl_init_params glInitParams = {
        &sharedTextureGetProcAddress,
        renderGlContext
    };
    mpv_render_param renderParams[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInitParams},
        {MPV_RENDER_PARAM_INVALID, 0}
    };
    if (mpv_render_context_create(&renderContext, handle, renderParams) < 0) {
        m_errorMessage = QStringLiteral("mpv OpenGL 渲染器初始化失败");
        qWarning() << "native player: shared-texture render context initialization failed";
        renderGlContext->doneCurrent();
        delete renderSurface;
        delete renderGlContext;
        mpv_terminate_destroy(handle);
        emit stateChanged();
        return false;
    }
    renderGlContext->doneCurrent();
    qInfo() << "native player: persistent shared-texture render context initialized"
            << "globalShare" << (globalShareContext != 0)
            << "windowShareFallback"
            << (!globalShareContext && windowShareContext != 0)
            << "shareParent" << (shareContext != 0);

    mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 2, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(handle, 3, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(handle, 4, "video-out-params", MPV_FORMAT_NODE);
    mpv_observe_property(handle, 5, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(handle, 6, "estimated-vf-fps", MPV_FORMAT_DOUBLE);
    mpv_set_wakeup_callback(handle, &onMpvWakeup, this);
    mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &m_requestedVolume);
    mpv_set_property(handle, "brightness", MPV_FORMAT_DOUBLE, &m_requestedBrightness);
    mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &m_requestedSpeed);
    int paused = m_requestedPaused ? 1 : 0;
    mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused);

    {
        QMutexLocker locker(&m_backend->mutex);
        m_backend->mpv = handle;
        m_backend->renderContext = renderContext;
        m_backend->renderGlContext = renderGlContext;
        m_backend->renderSurface = renderSurface;
    }
    emit rendererReadyChanged();
    mpv_render_context_set_update_callback(renderContext,
                                           &MpvVideoItem::sharedTextureRenderUpdate,
                                           this);
    const bool hadError = !m_errorMessage.isEmpty();
    m_errorMessage.clear();
    if (hadError) emit stateChanged();
    update();
    return true;
}

MpvVideoItem::~MpvVideoItem() {
    shutdown();
}

void MpvVideoItem::shutdown() {
    if (!m_backend && !m_hardwareDecoder) return;
    clearSurfaceConnections();
    m_sharedTextureRenderQueued.storeRelease(1);
    stopHardwareDecode();
    delete m_hardwareDecoder;
    m_hardwareDecoder = 0;
    delete m_backend;
    m_backend = 0;
    qInfo() << "native application shutdown: playback resources released"
            << "hardwareDecoder" << false
            << "mpvBackend" << false
            << "sharedTexture" << false;
}

void MpvVideoItem::sharedTextureRenderUpdate(void *context) {
    MpvVideoItem *item = static_cast<MpvVideoItem *>(context);
    if (!item || !item->m_sharedTextureRenderQueued.testAndSetOrdered(0, 1)) return;
    QMetaObject::invokeMethod(item, "renderSharedTextureFrame", Qt::QueuedConnection);
}

void MpvVideoItem::renderSharedTextureFrame() {
    m_sharedTextureRenderQueued.storeRelease(0);
    if (m_hardwareDecodeActive) return;
    if (!m_backend) return;
    QMutexLocker backendLocker(&m_backend->mutex);
    mpv_render_context *renderContext = m_backend->renderContext;
    QOpenGLContext *renderGlContext = m_backend->renderGlContext;
    QOffscreenSurface *renderSurface = m_backend->renderSurface;
    if (!renderContext || !renderGlContext || !renderSurface
            || !renderGlContext->makeCurrent(renderSurface)) {
        qWarning() << "native player: persistent offscreen context could not be made current";
        return;
    }
    const int frameWidth = qRound(width());
    const int frameHeight = qRound(height());
    if (frameWidth < 2 || frameHeight < 2) {
        renderGlContext->doneCurrent();
        return;
    }
    const QSize currentFramebufferSize = m_backend->framebuffers[0]
            ? m_backend->framebuffers[0]->size() : QSize();
    const double requestedAspect = static_cast<double>(frameWidth) / frameHeight;
    const double currentAspect = !currentFramebufferSize.isEmpty()
            ? static_cast<double>(currentFramebufferSize.width())
              / currentFramebufferSize.height() : 0.0;
    // Inline and compact surfaces deliberately share a bounded framebuffer so
    // PageStack animation and the Cover do not compete with software decoding.
    // Full-screen playback is promoted explicitly after orientation settles;
    // it then receives a host-sized framebuffer so a 1920x1080 source is not
    // first reduced to 800 pixels and enlarged again by Qt Quick.
    const bool framebufferAspectChanged = !currentFramebufferSize.isEmpty()
            && qAbs(currentAspect - requestedAspect)
               > qMax(0.01, requestedAspect * 0.015);
    QSize desiredFramebufferSize;
    if (m_fullResolutionPresentation) {
        desiredFramebufferSize = QSize(frameWidth, frameHeight);
    } else {
        const int stableLongEdge = 800;
        desiredFramebufferSize = requestedAspect >= 1.0
                ? QSize(stableLongEdge,
                        qMax(2, qRound(stableLongEdge / requestedAspect)))
                : QSize(qMax(2, qRound(stableLongEdge * requestedAspect)),
                        stableLongEdge);
    }
    const bool framebufferResolutionChanged = !currentFramebufferSize.isEmpty()
            && currentFramebufferSize != desiredFramebufferSize
            && (m_fullResolutionPresentation
                || qMax(currentFramebufferSize.width(), currentFramebufferSize.height()) > 800);
    const bool framebufferGeometryChanged = framebufferAspectChanged
            || framebufferResolutionChanged;
    const QSize nextFramebufferSize = currentFramebufferSize.isEmpty()
            || framebufferGeometryChanged
            ? desiredFramebufferSize : currentFramebufferSize;
    const uint64_t updateFlags = mpv_render_context_update(renderContext);
    const bool forcePresentedFrame = m_backend->presentationEnabled
            && (m_backend->activeFramebuffer < 0 || framebufferGeometryChanged);
    if (!(updateFlags & MPV_RENDER_UPDATE_FRAME) && !forcePresentedFrame) {
        renderGlContext->doneCurrent();
        return;
    }

    if (!m_backend->framebuffers[0] || !m_backend->framebuffers[1]
            || framebufferGeometryChanged) {
        QOpenGLFramebufferObjectFormat framebufferFormat;
        framebufferFormat.setAttachment(QOpenGLFramebufferObject::NoAttachment);
        framebufferFormat.setTextureTarget(GL_TEXTURE_2D);
        QOpenGLFramebufferObject *nextFirst = new QOpenGLFramebufferObject(
                    nextFramebufferSize.width(), nextFramebufferSize.height(),
                    framebufferFormat);
        QOpenGLFramebufferObject *nextSecond = new QOpenGLFramebufferObject(
                    nextFramebufferSize.width(), nextFramebufferSize.height(),
                    framebufferFormat);
        if (!nextFirst->isValid() || !nextSecond->isValid()) {
            qWarning() << "native player: persistent video framebuffer creation failed"
                       << nextFramebufferSize.width() << "x"
                       << nextFramebufferSize.height();
            delete nextFirst;
            delete nextSecond;
            renderGlContext->doneCurrent();
            return;
        }
        if (m_backend->framebuffers[0] || m_backend->framebuffers[1]) {
            MpvVideoBackend::RetiredFramebufferSet retired = {
                m_backend->framebuffers[0], m_backend->framebuffers[1], 8
            };
            m_backend->retiredFramebuffers.append(retired);
        }
        m_backend->framebuffers[0] = nextFirst;
        m_backend->framebuffers[1] = nextSecond;
        m_backend->activeFramebuffer = -1;
        m_backend->pendingFramebuffer = -1;
        ++m_backend->framebufferGeneration;
        qInfo() << "native player: video framebuffer geometry reset"
                << "generation" << m_backend->framebufferGeneration
                << "old" << currentFramebufferSize.width() << "x"
                << currentFramebufferSize.height()
                << "new" << nextFramebufferSize.width() << "x"
                << nextFramebufferSize.height()
                << "profile" << (m_fullResolutionPresentation
                                  ? "fullscreen-native" : "bounded-shared")
                << "itemAspect" << requestedAspect
                << "videoAspect" << videoAspectRatio()
                << "stableAcrossSizeOnlyHostChanges" << true;
    }

    const int occupiedFramebuffer = m_backend->activeFramebuffer >= 0
            ? m_backend->activeFramebuffer : m_backend->pendingFramebuffer;
    const int nextFramebuffer = occupiedFramebuffer < 0
            ? 0 : 1 - occupiedFramebuffer;
    QOpenGLFramebufferObject *framebuffer = m_backend->framebuffers[nextFramebuffer];
    const QSize framebufferSize = framebuffer->size();
    mpv_opengl_fbo targetFramebuffer = {
        static_cast<int>(framebuffer->handle()),
        framebufferSize.width(),
        framebufferSize.height(),
        0
    };
    int flipY = 1;
    int blockForTargetTime = 0;
    mpv_render_param renderParams[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &targetFramebuffer},
        {MPV_RENDER_PARAM_FLIP_Y, &flipY},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &blockForTargetTime},
        {MPV_RENDER_PARAM_INVALID, 0}
    };
    mpv_render_context_render(renderContext, renderParams);
    // Submit the completed write to the shared GL object without stalling the
    // GUI thread until every pixel has drained through the GPU.  The renderer
    // writes into the non-active half of the double buffer; publishing that
    // texture after glFlush lets the scene-graph context establish the actual
    // read dependency, while glFinish here previously serialized a full
    // 1920x1080 render before every Qt frame and pushed swaps below 45 FPS.
    typedef void (*GlFlushFunction)();
    GlFlushFunction glFlushFunction = reinterpret_cast<GlFlushFunction>(
                renderGlContext->getProcAddress(QByteArrayLiteral("glFlush")));
    if (glFlushFunction)
        glFlushFunction();
    if (!m_backend->presentationEnabled) {
        qint64 decodedWidth = 0;
        qint64 decodedHeight = 0;
        qint64 displayWidth = 0;
        qint64 displayHeight = 0;
        qint64 rotation = 0;
        const bool hasDecodedVideo = m_backend->mpv
                && mpv_get_property(m_backend->mpv, "video-params/w",
                                    MPV_FORMAT_INT64, &decodedWidth) >= 0
                && mpv_get_property(m_backend->mpv, "video-params/h",
                                    MPV_FORMAT_INT64, &decodedHeight) >= 0
                && decodedWidth > 0 && decodedHeight > 0;
        if (m_sourceFileStartedForPresentation && hasDecodedVideo) {
            // MPV_RENDER_UPDATE_FRAME can beat the queued video-geometry
            // property event. Retain this verified frame for the current new
            // source; it remains hidden until geometry confirms the aspect.
            m_backend->pendingFramebuffer = nextFramebuffer;
            if (!m_pendingGeometryLogEmitted) {
                m_pendingGeometryLogEmitted = true;
                qInfo() << "native player: decoded new-source frame retained pending geometry"
                        << decodedWidth << "x" << decodedHeight
                        << "loadSerial" << m_loadSerial;
            }

            // The observed video-out-params event is normally the first source
            // of display geometry, but on Sailfish it can be lost while the
            // first DASH video frame and audio restart arrive in adjacent event
            // turns. The decoded frame is already verified here, so query the
            // same current mpv properties synchronously and use them as a
            // level-triggered fallback. This only releases the retained frame;
            // it never reloads, seeks, pauses, or replaces the decoder.
            if (videoAspectRatio() <= 0.0) {
                if (mpv_get_property(m_backend->mpv, "video-out-params/dw",
                                     MPV_FORMAT_INT64, &displayWidth) < 0
                        || mpv_get_property(m_backend->mpv, "video-out-params/dh",
                                            MPV_FORMAT_INT64, &displayHeight) < 0
                        || displayWidth <= 0 || displayHeight <= 0) {
                    displayWidth = decodedWidth;
                    displayHeight = decodedHeight;
                }
                if (mpv_get_property(m_backend->mpv, "video-out-params/rotate",
                                     MPV_FORMAT_INT64, &rotation) < 0)
                    rotation = 0;
                const int normalizedRotation = static_cast<int>((rotation % 360 + 360) % 360);
                if (normalizedRotation == 90 || normalizedRotation == 270)
                    qSwap(displayWidth, displayHeight);
            }
        }
        renderGlContext->doneCurrent();
        backendLocker.unlock();
        if (displayWidth > 0 && displayHeight > 0) {
            qInfo() << "native player: video geometry recovered from decoded frame"
                    << displayWidth << "x" << displayHeight
                    << "loadSerial" << m_loadSerial
                    << "withoutReload" << true;
            updateVideoGeometryFromMpv(static_cast<int>(displayWidth),
                                       static_cast<int>(displayHeight));
        }
        return;
    }
    m_backend->activeFramebuffer = nextFramebuffer;
    m_backend->pendingFramebuffer = -1;
    ++m_sharedTextureFrameSerial;
    recordPresentedFrameForFloor();
    const QSize presentedViewportSize = fittedVideoViewport(
                framebufferSize, m_videoWidth, m_videoHeight);
    if (framebufferGeometryChanged) {
        qInfo() << "native player: framebuffer profile frame committed"
                << "profile" << (m_fullResolutionPresentation
                                  ? "fullscreen-native" : "bounded-shared")
                << "texture" << framebufferSize.width() << "x" << framebufferSize.height()
                << "videoViewport" << presentedViewportSize.width() << "x"
                << presentedViewportSize.height()
                << "source" << m_videoWidth << "x" << m_videoHeight
                << "frameSerial" << m_sharedTextureFrameSerial;
    }
    if (m_sharedTextureFrameSerial == 1) {
        m_initialVideoFrameReady = true;
        m_sharedTextureFrameTimer.start();
        qInfo() << "native player: first persistent shared-texture frame rendered"
                << framebufferSize.width() << "x" << framebufferSize.height()
                << "texture" << framebuffer->texture()
                << "loadSerial" << m_loadSerial
                << "item" << frameWidth << "x" << frameHeight
                << "videoAspect" << videoAspectRatio();
        emit firstFramePresented(m_loadSerial, position());
        releaseInitialPositionGate(m_position);
    } else if ((m_sharedTextureFrameSerial - 1) % 60 == 0) {
        const qint64 elapsedMs = m_sharedTextureFrameTimer.elapsed();
        const double averageFps = elapsedMs > 0
                ? (m_sharedTextureFrameSerial - 1) * 1000.0 / elapsedMs : 0.0;
        qInfo() << "native player: shared-texture frame checkpoint"
                << "serial" << m_sharedTextureFrameSerial
                << "elapsedMs" << elapsedMs
                << "averageFps" << averageFps;
    }
    // Qt's scene graph can retain the wrapper for the previous shared texture
    // for a few render passes. Keep old FBO storage alive for eight decoded
    // frames so an orientation change never samples a deleted GL texture.
    for (int index = m_backend->retiredFramebuffers.size() - 1; index >= 0; --index) {
        MpvVideoBackend::RetiredFramebufferSet &retired =
                m_backend->retiredFramebuffers[index];
        --retired.framesUntilRelease;
        if (retired.framesUntilRelease > 0) continue;
        delete retired.first;
        delete retired.second;
        m_backend->retiredFramebuffers.remove(index);
    }
    renderGlContext->doneCurrent();
    backendLocker.unlock();
    updatePresentedTextureGeometry(framebufferSize, presentedViewportSize);
    update();
    emit sharedTextureFrameChanged(m_sharedTextureFrameSerial);
}

bool MpvVideoItem::startHardwareDecode(const QString &videoUrl,
                                       double startPosition) {
    if (!m_hardwareDecoder || videoUrl.isEmpty()) return false;
    if (!qgetenv("SILISILI_NATIVE_TEST_PAGE").isEmpty()
            && qgetenv("SILISILI_NATIVE_TEST_SOFTWARE_VIDEO") == QByteArrayLiteral("1")) {
        qInfo() << "native player: software video route requested for regression";
        return false;
    }
    DroidMediaCodecMetaData capability;
    std::memset(&capability, 0, sizeof(capability));
    capability.type = "video/avc";
    capability.width = 1920;
    capability.height = 1080;
    capability.fps = 30;
    capability.flags = DROID_MEDIA_CODEC_HW_ONLY;
    if (!droid_media_init()
            || !droid_media_codec_is_supported(&capability, false)) {
        qWarning() << "native hardware video: device route unavailable"
                   << "fallback" << "software";
        return false;
    }
    return m_hardwareDecoder->start(videoUrl, startPosition,
                                    m_liveStreamSource);
}

void MpvVideoItem::stopHardwareDecode() {
    const bool wasActive = m_hardwareDecodeActive;
    m_hardwareDecodeActive = false;
    m_hardwarePresentationTimer.stop();
    m_hardwareStallTimer.stop();
    m_hardwareStallElapsed.invalidate();
    m_hardwareFirstFrameTimer.stop();
    m_hardwareFirstFramePending = false;
    m_hardwarePresentationCadenceLogged = false;
    drainDeferredHardwareBuffers("decoder-stop");
    if (m_hardwareDecoder) m_hardwareDecoder->stop();
    if (wasActive)
        qInfo() << "native hardware video: direct pipeline stopped";
}

void MpvVideoItem::drainDeferredHardwareBuffers(const char *reason) {
    if (!m_backend) return;
    QMutexLocker locker(&m_backend->mutex);
    if (m_backend->deferredHardwareBuffers.isEmpty()) return;

    QOpenGLContext *renderContext = m_backend->renderGlContext;
    QOffscreenSurface *renderSurface = m_backend->renderSurface;
    if (!renderContext || !renderSurface
            || !renderContext->makeCurrent(renderSurface)) {
        qWarning() << "native hardware video: deferred buffer drain postponed"
                   << "reason" << reason
                   << "buffers" << m_backend->deferredHardwareBuffers.size();
        return;
    }

    // Decoder stop/restart is the one bounded point where waiting for all GPU
    // reads is desirable. It guarantees no buffer from the outgoing
    // BufferQueue remains attached to the persistent renderer and avoids
    // carrying an old codec generation into the next playback session.
    renderContext->functions()->glFinish();
    const int released = m_backend->deferredHardwareBuffers.size();
    for (int index = 0; index < released; ++index) {
        MpvVideoBackend::DeferredHardwareBuffer &pending =
                m_backend->deferredHardwareBuffers[index];
        if (pending.fence != EGL_NO_SYNC_KHR && hardwareEglDestroySync)
            hardwareEglDestroySync(pending.display, pending.fence);
        if (pending.buffer)
            droid_media_buffer_release(pending.buffer, pending.display, 0);
    }
    m_backend->deferredHardwareBuffers.clear();
    renderContext->doneCurrent();
    qInfo() << "native hardware video: deferred GPU buffers drained"
            << "reason" << reason
            << "released" << released
            << "boundedAtDecoderBoundary" << true;
}

void MpvVideoItem::syncHardwareClock() {
    if (!m_hardwareDecodeActive || !m_hardwareDecoder) {
        m_hardwarePresentationTimer.stop();
        m_hardwareStallTimer.stop();
        m_hardwareStallElapsed.invalidate();
        return;
    }
    const bool running = m_playing && !m_paused && !m_loading && !m_ended
            && !m_buffering && !m_seekPending;
    m_hardwareDecoder->updateMasterClock(position(), m_speed, running);
    if (running) {
        if (!m_hardwarePresentationTimer.isActive())
            m_hardwarePresentationTimer.start();
        if (!m_hardwarePresentationCadenceLogged) {
            m_hardwarePresentationCadenceLogged = true;
            qInfo() << "native hardware video: display cadence driver"
                    << "intervalMs" << m_hardwarePresentationTimer.interval()
                    << "sourceFps" << m_sourceFrameRate
                    << "decodeCopies" << 0
                    << "presentationOnly" << true;
        }
        if (!m_hardwareStallTimer.isActive())
            m_hardwareStallTimer.start();
        if (!m_hardwareStallElapsed.isValid())
            resetHardwareStallWatchdog();
    } else {
        m_hardwarePresentationTimer.stop();
        m_hardwareStallTimer.stop();
        m_hardwareStallElapsed.invalidate();
    }
}

void MpvVideoItem::resetHardwareStallWatchdog() {
    m_hardwareStallObservedSerial = m_sharedTextureFrameSerial;
    m_hardwareStallObservedPosition = position();
    m_hardwareStallElapsed.restart();
}

void MpvVideoItem::monitorHardwareProgress() {
    const bool eligible = m_hardwareDecodeActive && m_hardwareDecoder
            && !m_hardwareFirstFramePending && m_sharedTextureFrameSerial > 0
            && m_playing && !m_paused && !m_loading && !m_ended
            && !m_buffering && !m_seekPending;
    if (!eligible) {
        m_hardwareStallElapsed.invalidate();
        return;
    }

    const int frameSerial = m_sharedTextureFrameSerial;
    const double playbackPosition = position();
    if (!m_hardwareStallElapsed.isValid()
            || frameSerial != m_hardwareStallObservedSerial
            || playbackPosition + 0.25 < m_hardwareStallObservedPosition) {
        resetHardwareStallWatchdog();
        return;
    }
    const double audioAdvance = playbackPosition - m_hardwareStallObservedPosition;
    if (audioAdvance < 1.0 || m_hardwareStallElapsed.elapsed() < 3000)
        return;

    qWarning() << "native hardware video: playback frame stall detected"
               << "generation" << m_hardwareDecoder->generation()
               << "frameSerial" << frameSerial
               << "stalledMs" << m_hardwareStallElapsed.elapsed()
               << "audioAdvance" << audioAdvance
               << "position" << playbackPosition
               << "loading" << m_loading
               << "buffering" << m_buffering;
    restartHardwareDecodeAfterStall();
}

void MpvVideoItem::restartHardwareDecodeAfterStall() {
    if (!m_hardwareDecodeActive || !m_hardwareDecoder
            || m_originalVideoUrl.isEmpty())
        return;
    const double retainedPosition = position();
    const int retainedFrameSerial = m_sharedTextureFrameSerial;
    const int previousGeneration = m_hardwareDecoder->generation();
    ++m_hardwareStallRecoveryCount;

    m_hardwareStallTimer.stop();
    m_hardwareStallElapsed.invalidate();
    m_hardwarePresentationTimer.stop();
    m_hardwareFirstFrameTimer.stop();
    m_hardwareFirstFramePending = false;
    drainDeferredHardwareBuffers("stall-restart");
    m_hardwareDecoder->stop();

    const bool restarted = m_hardwareDecoder->start(m_originalVideoUrl,
                                                    retainedPosition,
                                                    m_liveStreamSource);
    m_hardwareDecodeActive = restarted;
    if (!restarted) {
        // Keep the existing complete compatibility path as the last resort.
        // This branch is not used by the normal same-quality recovery.
        m_hardwareDecodeActive = true;
        fallbackToSoftwareDecode(QStringLiteral("runtime-stall-restart-failed"));
        return;
    }

    m_hardwareFirstFramePending = true;
    m_hardwarePresentationCadenceLogged = false;
    if (m_testHardwareStallInjected
            && m_testHardwareStallGeneration == previousGeneration
            && m_testHardwareStallInjectedCount
               < m_testHardwareStallTargetCount) {
        m_testHardwareStallInjected = false;
        m_testHardwareStallNextFrameSerial = m_sharedTextureFrameSerial + 30;
    }
    m_hardwareDecoder->setPaused(false);
    m_hardwareDecoder->updateMasterClock(retainedPosition, m_speed, true);
    resetHardwareStallWatchdog();
    syncHardwareClock();
    qWarning() << "native hardware video: same-quality decoder restart completed"
               << "previousGeneration" << previousGeneration
               << "generation" << m_hardwareDecoder->generation()
               << "recoveryCount" << m_hardwareStallRecoveryCount
               << "position" << retainedPosition
               << "frameSerialRetained" << retainedFrameSerial
               << "audioReload" << false
               << "mediaLoadSerial" << m_loadSerial
               << "textureRetained" << true;
}

void MpvVideoItem::hardwareStreamReady(int generation, int width, int height,
                                       double framesPerSecond,
                                       const QString &codec) {
    if (!m_hardwareDecodeActive || !m_hardwareDecoder
            || generation != m_hardwareDecoder->generation())
        return;
    qInfo() << "native hardware video: stream ready"
            << "generation" << generation
            << "codec" << codec
            << "geometry" << width << "x" << height
            << "sourceFps" << framesPerSecond
            << "audioMaster" << "libmpv"
            << "cpuPixelCopies" << 0;
    updateSourceFrameRateFromMpv(framesPerSecond);
    updateVideoGeometryFromMpv(width, height);
    if (m_hardwareFirstFramePending) {
        const bool ultraHd = static_cast<long long>(width) * height
                > 1920LL * 1080LL;
        m_hardwareFirstFrameTimer.setInterval(ultraHd ? 1200 : 3500);
        m_hardwareFirstFrameTimer.start();
        qInfo() << "native hardware video: first-frame watchdog armed"
                << "loadSerial" << m_loadSerial
                << "deadlineMs" << m_hardwareFirstFrameTimer.interval()
                << "geometry" << width << "x" << height
                << "sourceFps" << framesPerSecond;
    }
    emit stateChanged();
}

void MpvVideoItem::hardwareDecodeFailed(int generation,
                                        const QString &reason) {
    if (!m_hardwareDecodeActive || !m_hardwareDecoder
            || generation != m_hardwareDecoder->generation())
        return;
    if (reason == QStringLiteral("source-exceeds-device-buffer-budget")
            || reason.startsWith(QStringLiteral("ultrahd-"))) {
        if (m_liveStreamSource) {
            qWarning() << "native live quality: unsafe original rejected"
                       << "loadSerial" << m_loadSerial
                       << "reason" << reason
                       << "action" << "request-lower-server-quality";
            emit unsafeLiveQualityRejected(m_loadSerial, reason);
            return;
        }
        qWarning() << "native hardware video: unsafe software fallback suppressed"
                   << "reason" << reason
                   << "action" << "stop-and-select-lower-quality";
        stop();
        updateErrorFromMpv(QStringLiteral("该超高清档位无法安全硬解，请切换到更低清晰度"));
        return;
    }
    fallbackToSoftwareDecode(reason);
}

void MpvVideoItem::fallbackToSoftwareDecode(const QString &reason) {
    if (!m_hardwareDecodeActive || m_originalVideoUrl.isEmpty()) return;
    const QString videoUrl = m_originalVideoUrl;
    const QString audioUrl = m_originalAudioUrl;
    // A live container is not seekable. Reopening it at libmpv's elapsed
    // position adds a non-zero initial-position gate which can never be
    // confirmed, permanently hiding an otherwise valid software frame.
    const double fallbackPosition = m_liveStreamSource ? 0.0 : position();
    const bool fallbackPaused = m_requestedPaused || m_paused;
    qWarning() << "native hardware video: switching to software fallback"
               << "reason" << reason
               << "position" << fallbackPosition
               << "liveStream" << m_liveStreamSource
               << "seekSuppressed" << m_liveStreamSource
               << "paused" << fallbackPaused
               << "sameSource" << true;
    m_hardwareFallbackForCurrentLoad = true;
    loadSourceInternal(videoUrl, audioUrl, fallbackPosition, fallbackPaused,
                       true, m_liveStreamSource);
}

void MpvVideoItem::renderPendingHardwareFrame(int generation) {
    if (!m_hardwareDecoder) return;
    DroidMediaBuffer *buffer = m_hardwareDecoder->takePendingFrame(generation);
    if (!buffer) {
        m_hardwareDecoder->frameRenderCompleted(generation);
        return;
    }
    if (!m_hardwareDecodeActive || generation != m_hardwareDecoder->generation()
            || !m_backend) {
        droid_media_buffer_release(buffer, 0, 0);
        m_hardwareDecoder->frameRenderCompleted(generation);
        return;
    }

    if (m_testHardwareStallEnabled && !m_testHardwareStallInjected
            && m_testHardwareStallInjectedCount
               < m_testHardwareStallTargetCount
            && m_sharedTextureFrameSerial
               >= m_testHardwareStallNextFrameSerial) {
        m_testHardwareStallInjected = true;
        m_testHardwareStallGeneration = generation;
        ++m_testHardwareStallInjectedCount;
        qWarning() << "native hardware video: deterministic frame stall injected"
                   << "generation" << generation
                   << "frameSerial" << m_sharedTextureFrameSerial
                   << "injection" << m_testHardwareStallInjectedCount
                   << "target" << m_testHardwareStallTargetCount
                   << "oneShot" << (m_testHardwareStallTargetCount == 1);
    }
    if (m_testHardwareStallInjected
            && generation == m_testHardwareStallGeneration) {
        droid_media_buffer_release(buffer, 0, 0);
        m_hardwareDecoder->frameRenderCompleted(generation);
        return;
    }

    DroidMediaBufferInfo bufferInfo;
    std::memset(&bufferInfo, 0, sizeof(bufferInfo));
    droid_media_buffer_get_info(buffer, &bufferInfo);
    int sourceWidth = bufferInfo.width > 0
            ? static_cast<int>(bufferInfo.width) : m_videoWidth;
    int sourceHeight = bufferInfo.height > 0
            ? static_cast<int>(bufferInfo.height) : m_videoHeight;
    const int cropLeft = qBound(0, bufferInfo.crop_rect.left, sourceWidth);
    const int cropTop = qBound(0, bufferInfo.crop_rect.top, sourceHeight);
    const int cropRight = bufferInfo.crop_rect.right > cropLeft
            ? qBound(cropLeft + 1, bufferInfo.crop_rect.right, sourceWidth)
            : sourceWidth;
    const int cropBottom = bufferInfo.crop_rect.bottom > cropTop
            ? qBound(cropTop + 1, bufferInfo.crop_rect.bottom, sourceHeight)
            : sourceHeight;
    int visibleWidth = qMax(1, cropRight - cropLeft);
    int visibleHeight = qMax(1, cropBottom - cropTop);
    const bool rotated = (bufferInfo.transform & 0x04u) != 0;
    if (rotated) qSwap(visibleWidth, visibleHeight);

    QString renderError;
    QSize framebufferSize;
    QSize presentedViewportSize;
    GLuint publishedTexture = 0;
    bool published = false;
    bool firstPublishedFrame = false;
    {
        QMutexLocker backendLocker(&m_backend->mutex);
        QOpenGLContext *renderContext = m_backend->renderGlContext;
        QOffscreenSurface *renderSurface = m_backend->renderSurface;
        if (!renderContext || !renderSurface
                || !renderContext->makeCurrent(renderSurface)) {
            renderError = QStringLiteral("hardware-offscreen-context");
        } else if (!resolveHardwareTextureFunctions()) {
            renderError = QStringLiteral("eglimage-external-oes-unavailable");
        } else {
            const int itemWidth = qRound(width());
            const int itemHeight = qRound(height());
            if (itemWidth < 2 || itemHeight < 2) {
                renderContext->doneCurrent();
                droid_media_buffer_release(buffer, 0, 0);
                m_hardwareDecoder->frameRenderCompleted(generation);
                return;
            }
            const double itemAspect = static_cast<double>(itemWidth) / itemHeight;
            const QSize desiredSize = m_fullResolutionPresentation
                    ? QSize(itemWidth, itemHeight)
                    : (itemAspect >= 1.0
                       ? QSize(800, qMax(2, qRound(800.0 / itemAspect)))
                       : QSize(qMax(2, qRound(800.0 * itemAspect)), 800));
            const QSize currentSize = m_backend->framebuffers[0]
                    ? m_backend->framebuffers[0]->size() : QSize();
            const bool geometryChanged = currentSize.isEmpty()
                    || currentSize != desiredSize;
            if (!m_backend->framebuffers[0] || !m_backend->framebuffers[1]
                    || geometryChanged) {
                QOpenGLFramebufferObjectFormat format;
                format.setAttachment(QOpenGLFramebufferObject::NoAttachment);
                format.setTextureTarget(GL_TEXTURE_2D);
                QOpenGLFramebufferObject *first = new QOpenGLFramebufferObject(
                            desiredSize.width(), desiredSize.height(), format);
                QOpenGLFramebufferObject *second = new QOpenGLFramebufferObject(
                            desiredSize.width(), desiredSize.height(), format);
                if (!first->isValid() || !second->isValid()) {
                    delete first;
                    delete second;
                    renderError = QStringLiteral("hardware-framebuffer-create");
                } else {
                    if (m_backend->framebuffers[0] || m_backend->framebuffers[1]) {
                        MpvVideoBackend::RetiredFramebufferSet retired = {
                            m_backend->framebuffers[0], m_backend->framebuffers[1], 8
                        };
                        m_backend->retiredFramebuffers.append(retired);
                    }
                    m_backend->framebuffers[0] = first;
                    m_backend->framebuffers[1] = second;
                    m_backend->activeFramebuffer = -1;
                    m_backend->pendingFramebuffer = -1;
                    ++m_backend->framebufferGeneration;
                    qInfo() << "native hardware video: shared framebuffer geometry"
                            << "generation" << m_backend->framebufferGeneration
                            << "old" << currentSize.width() << "x" << currentSize.height()
                            << "new" << desiredSize.width() << "x" << desiredSize.height()
                            << "profile" << (m_fullResolutionPresentation
                                              ? "fullscreen-native" : "bounded-shared");
                }
            }

            if (renderError.isEmpty() && !m_backend->hardwareProgram) {
                QOpenGLShaderProgram *program = new QOpenGLShaderProgram;
                const char *vertexShader =
                    "attribute highp vec2 aPosition;\n"
                    "attribute highp vec2 aTexCoord;\n"
                    "varying highp vec2 vTexCoord;\n"
                    "void main() { gl_Position = vec4(aPosition, 0.0, 1.0);"
                    " vTexCoord = aTexCoord; }\n";
                const char *fragmentShader =
                    "#extension GL_OES_EGL_image_external : require\n"
                    "precision mediump float;\n"
                    "uniform samplerExternalOES uTexture;\n"
                    "uniform lowp float uBrightness;\n"
                    "varying highp vec2 vTexCoord;\n"
                    "void main() { vec4 c = texture2D(uTexture, vTexCoord);"
                    " c.rgb = clamp(c.rgb + vec3(uBrightness), 0.0, 1.0);"
                    " gl_FragColor = c; }\n";
                if (!program->addShaderFromSourceCode(QOpenGLShader::Vertex,
                                                       vertexShader)
                        || !program->addShaderFromSourceCode(QOpenGLShader::Fragment,
                                                             fragmentShader)
                        || !program->link()) {
                    qWarning() << "native hardware video: external texture shader failed"
                               << program->log();
                    delete program;
                    renderError = QStringLiteral("external-oes-shader");
                } else {
                    m_backend->hardwareProgram = program;
                }
            }

            QOpenGLFunctions *gl = renderContext->functions();
            if (renderError.isEmpty() && !m_backend->hardwareExternalTexture) {
                gl->glGenTextures(1, &m_backend->hardwareExternalTexture);
                gl->glBindTexture(GL_TEXTURE_EXTERNAL_OES,
                                  m_backend->hardwareExternalTexture);
                gl->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER,
                                    GL_LINEAR);
                gl->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER,
                                    GL_LINEAR);
                gl->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S,
                                    GL_CLAMP_TO_EDGE);
                gl->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T,
                                    GL_CLAMP_TO_EDGE);
            }

            EGLDisplay eglDisplay = eglGetCurrentDisplay();
            EGLImageKHR image = EGL_NO_IMAGE_KHR;
            if (renderError.isEmpty()) {
                const EGLint imageAttributes[] = {
                    EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE
                };
                image = hardwareEglCreateImage(
                            eglDisplay, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                            reinterpret_cast<EGLClientBuffer>(buffer), imageAttributes);
                if (image == EGL_NO_IMAGE_KHR) {
                    qWarning() << "native hardware video: EGLImage creation failed"
                               << QString::number(eglGetError(), 16);
                    renderError = QStringLiteral("eglimage-create");
                }
            }

            if (renderError.isEmpty()) {
                const int occupied = m_backend->activeFramebuffer >= 0
                        ? m_backend->activeFramebuffer : m_backend->pendingFramebuffer;
                const int nextFramebuffer = occupied < 0 ? 0 : 1 - occupied;
                QOpenGLFramebufferObject *framebuffer =
                        m_backend->framebuffers[nextFramebuffer];
                framebufferSize = framebuffer->size();
                framebuffer->bind();
                gl->glViewport(0, 0, framebufferSize.width(), framebufferSize.height());
                gl->glClearColor(0.f, 0.f, 0.f, 1.f);
                gl->glClear(GL_COLOR_BUFFER_BIT);

                const double sourceAspect = static_cast<double>(visibleWidth)
                        / visibleHeight;
                int viewportWidth = framebufferSize.width();
                int viewportHeight = qRound(viewportWidth / sourceAspect);
                if (viewportHeight > framebufferSize.height()) {
                    viewportHeight = framebufferSize.height();
                    viewportWidth = qRound(viewportHeight * sourceAspect);
                }
                gl->glViewport((framebufferSize.width() - viewportWidth) / 2,
                               (framebufferSize.height() - viewportHeight) / 2,
                               viewportWidth, viewportHeight);
                presentedViewportSize = QSize(viewportWidth, viewportHeight);
                gl->glActiveTexture(GL_TEXTURE0);
                gl->glBindTexture(GL_TEXTURE_EXTERNAL_OES,
                                  m_backend->hardwareExternalTexture);
                hardwareGlImageTargetTexture(GL_TEXTURE_EXTERNAL_OES,
                                             reinterpret_cast<GLeglImageOES>(image));

                const GLfloat positions[] = {
                    -1.f, -1.f, -1.f, 1.f, 1.f, -1.f, 1.f, 1.f
                };
                const GLfloat left = static_cast<GLfloat>(cropLeft)
                        / qMax(1, sourceWidth);
                const GLfloat right = static_cast<GLfloat>(cropRight)
                        / qMax(1, sourceWidth);
                const GLfloat top = static_cast<GLfloat>(cropTop)
                        / qMax(1, sourceHeight);
                const GLfloat bottom = static_cast<GLfloat>(cropBottom)
                        / qMax(1, sourceHeight);
                GLfloat textureCoordinates[] = {
                    left, bottom, left, top, right, bottom, right, top
                };
                // Android's transform bit 0x04 denotes a 90-degree rotation.
                // Rotate sampling without stretching; the viewport aspect was
                // swapped above. Flip flags are uncommon for decoded video but
                // are still honored when supplied by the buffer queue.
                if (rotated) {
                    const GLfloat rotatedCoordinates[] = {
                        right, bottom, left, bottom, right, top, left, top
                    };
                    std::memcpy(textureCoordinates, rotatedCoordinates,
                                sizeof(textureCoordinates));
                }
                if ((bufferInfo.transform & 0x01u) != 0) {
                    for (int index = 0; index < 4; ++index)
                        textureCoordinates[index * 2] = left + right
                                - textureCoordinates[index * 2];
                }
                if ((bufferInfo.transform & 0x02u) != 0) {
                    for (int index = 0; index < 4; ++index)
                        textureCoordinates[index * 2 + 1] = top + bottom
                                - textureCoordinates[index * 2 + 1];
                }

                QOpenGLShaderProgram *program = m_backend->hardwareProgram;
                program->bind();
                program->setUniformValue("uTexture", 0);
                program->setUniformValue("uBrightness",
                                         static_cast<GLfloat>(m_brightness / 100.0));
                const int positionLocation = program->attributeLocation("aPosition");
                const int textureLocation = program->attributeLocation("aTexCoord");
                program->enableAttributeArray(positionLocation);
                program->enableAttributeArray(textureLocation);
                program->setAttributeArray(positionLocation, GL_FLOAT, positions, 2);
                program->setAttributeArray(textureLocation, GL_FLOAT,
                                           textureCoordinates, 2);
                gl->glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                program->disableAttributeArray(positionLocation);
                program->disableAttributeArray(textureLocation);
                program->release();
                framebuffer->release();

                // Android 9's droidmedia BufferQueue ignores a native fence
                // passed to buffer_release(). Keep the gralloc buffer alive in
                // this process instead: a render-context EGL fence proves that
                // the external-OES sample into the shared FBO has completed.
                // This avoids the per-frame glFinish() that stalled the GUI and
                // produced sub-45 FPS display windows despite stable decoding.
                gl->glFlush();
                EGLSyncKHR releaseFence = EGL_NO_SYNC_KHR;
                if (hardwareEglCreateSync && hardwareEglClientWaitSync
                        && hardwareEglDestroySync) {
                    const EGLint fenceAttributes[] = {EGL_NONE};
                    releaseFence = hardwareEglCreateSync(
                                eglDisplay, EGL_SYNC_FENCE_KHR, fenceAttributes);
                    gl->glFlush();
                }
                hardwareEglDestroyImage(eglDisplay, image);
                image = EGL_NO_IMAGE_KHR;
                if (releaseFence != EGL_NO_SYNC_KHR) {
                    MpvVideoBackend::DeferredHardwareBuffer pending = {
                        buffer, eglDisplay, releaseFence
                    };
                    m_backend->deferredHardwareBuffers.append(pending);
                    buffer = 0;

                    for (int index = 0;
                         index < m_backend->deferredHardwareBuffers.size();) {
                        MpvVideoBackend::DeferredHardwareBuffer &candidate =
                                m_backend->deferredHardwareBuffers[index];
                        const EGLint waitResult = hardwareEglClientWaitSync(
                                    candidate.display, candidate.fence, 0, 0);
                        if (waitResult != EGL_CONDITION_SATISFIED_KHR) {
                            ++index;
                            continue;
                        }
                        hardwareEglDestroySync(candidate.display, candidate.fence);
                        droid_media_buffer_release(candidate.buffer,
                                                   candidate.display, 0);
                        m_backend->deferredHardwareBuffers.remove(index);
                    }

                    // Normal operation retains one or two buffers. A broken
                    // fence implementation must not exhaust the decoder queue;
                    // use one bounded emergency drain instead of blocking every
                    // video frame for the lifetime of playback.
                    if (m_backend->deferredHardwareBuffers.size() > 4) {
                        qWarning() << "native hardware video: GPU fence backlog"
                                   << m_backend->deferredHardwareBuffers.size()
                                   << "emergencyFinish" << true;
                        gl->glFinish();
                        for (int index = 0;
                             index < m_backend->deferredHardwareBuffers.size();
                             ++index) {
                            MpvVideoBackend::DeferredHardwareBuffer &candidate =
                                    m_backend->deferredHardwareBuffers[index];
                            hardwareEglDestroySync(candidate.display,
                                                   candidate.fence);
                            droid_media_buffer_release(candidate.buffer,
                                                       candidate.display, 0);
                        }
                        m_backend->deferredHardwareBuffers.clear();
                    }
                } else {
                    // Compatibility fallback for EGL stacks without
                    // EGL_KHR_fence_sync. It is safe but intentionally rare.
                    gl->glFinish();
                    droid_media_buffer_release(buffer, eglDisplay, 0);
                    buffer = 0;
                }

                if (m_backend->presentationEnabled) {
                    m_backend->activeFramebuffer = nextFramebuffer;
                    m_backend->pendingFramebuffer = -1;
                    ++m_sharedTextureFrameSerial;
                    publishedTexture = framebuffer->texture();
                    published = true;
                    firstPublishedFrame = m_sharedTextureFrameSerial == 1;
                    recordPresentedFrameForFloor();
                } else {
                    m_backend->pendingFramebuffer = nextFramebuffer;
                }
                for (int index = m_backend->retiredFramebuffers.size() - 1;
                     index >= 0; --index) {
                    MpvVideoBackend::RetiredFramebufferSet &retired =
                            m_backend->retiredFramebuffers[index];
                    --retired.framesUntilRelease;
                    if (retired.framesUntilRelease <= 0) {
                        delete retired.first;
                        delete retired.second;
                        m_backend->retiredFramebuffers.remove(index);
                    }
                }
            }
            if (image != EGL_NO_IMAGE_KHR)
                hardwareEglDestroyImage(eglDisplay, image);
            renderContext->doneCurrent();
        }
    }

    if (buffer) droid_media_buffer_release(buffer, 0, 0);
    m_hardwareDecoder->frameRenderCompleted(generation);
    if (!renderError.isEmpty()) {
        fallbackToSoftwareDecode(renderError);
        return;
    }

    if (m_videoWidth != visibleWidth || m_videoHeight != visibleHeight)
        updateVideoGeometryFromMpv(visibleWidth, visibleHeight);
    const bool firstDecodedHardwareFrame = m_hardwareFirstFramePending;
    if (firstDecodedHardwareFrame) {
        // A non-zero history position keeps presentation gated until the
        // audio clock confirms the same target. The hardware frame has still
        // been decoded and copied into the application-owned shared FBO, so it
        // is not a decoder startup failure. Stop the codec watchdog here and
        // let the initial-position gate publish the retained framebuffer.
        m_hardwareFirstFramePending = false;
        m_hardwareFirstFrameTimer.stop();
        qInfo() << "native hardware video: first decoded texture ready"
                << framebufferSize.width() << "x" << framebufferSize.height()
                << "loadSerial" << m_loadSerial
                << "generation" << generation
                << "published" << published
                << "initialPositionGate" << m_initialPositionGatePending
                << "cpuPixelCopies" << 0;
    }
    if (!published) return;
    updatePresentedTextureGeometry(framebufferSize, presentedViewportSize);
    resetHardwareStallWatchdog();
    if (firstPublishedFrame) {
        m_initialVideoFrameReady = true;
        m_sharedTextureFrameTimer.start();
        qInfo() << "native hardware video: first shared-texture frame rendered"
                << framebufferSize.width() << "x" << framebufferSize.height()
                << "texture" << publishedTexture
                << "loadSerial" << m_loadSerial
                << "generation" << generation
                << "cpuPixelCopies" << 0;
        emit firstFramePresented(m_loadSerial, position());
        releaseInitialPositionGate(m_position);
    } else if ((m_sharedTextureFrameSerial - 1) % 60 == 0) {
        const qint64 elapsedMs = m_sharedTextureFrameTimer.elapsed();
        qInfo() << "native hardware video: shared-texture frame checkpoint"
                << "serial" << m_sharedTextureFrameSerial
                << "elapsedMs" << elapsedMs
                << "averageFps" << (elapsedMs > 0
                    ? (m_sharedTextureFrameSerial - 1) * 1000.0 / elapsedMs : 0.0)
                << "cpuPixelCopies" << 0;
    }
    update();
    emit sharedTextureFrameChanged(m_sharedTextureFrameSerial);
}

QSGNode *MpvVideoItem::updatePaintNode(QSGNode *oldNode,
                                       UpdatePaintNodeData *updatePaintNodeData) {
    Q_UNUSED(updatePaintNodeData)
    SharedTextureNode *node = static_cast<SharedTextureNode *>(oldNode);
    if (!m_backend || !window()) {
        delete node;
        return 0;
    }

    GLuint textureId = 0;
    QSize textureSize;
    QOpenGLContext *renderGlContext = 0;
    {
        QMutexLocker locker(&m_backend->mutex);
        const int activeFramebuffer = m_backend->activeFramebuffer;
        QOpenGLFramebufferObject *framebuffer = activeFramebuffer >= 0
                ? m_backend->framebuffers[activeFramebuffer] : 0;
        if (framebuffer) {
            textureId = framebuffer->texture();
            textureSize = framebuffer->size();
            renderGlContext = m_backend->renderGlContext;
        }
    }
    if (!textureId || textureSize.isEmpty()) {
        delete node;
        return 0;
    }

    QOpenGLContext *sceneGraphContext = QOpenGLContext::currentContext();
    const bool contextsShare = renderGlContext && sceneGraphContext
            && QOpenGLContext::areSharing(renderGlContext, sceneGraphContext);
    if (!m_textureSharingLogged) {
        m_textureSharingLogged = true;
        qInfo() << "native player: scene graph shares persistent video texture"
                << contextsShare;
    }
    if (!contextsShare) {
        delete node;
        return 0;
    }

    QSGTexture *texture = window()->createTextureFromId(textureId, textureSize);
    if (!texture) {
        delete node;
        return 0;
    }
    if (!node)
        node = new SharedTextureNode;
    node->replaceTexture(texture);
    node->setRect(boundingRect());
    node->setFiltering(QSGTexture::Linear);
    node->setTextureCoordinatesTransform(QSGSimpleTextureNode::MirrorVertically);
    return node;
}

MpvVideoMirrorItem::MpvVideoMirrorItem(QQuickItem *parent)
    : QQuickItem(parent), m_textureSharingLogged(false),
      m_preserveAspectRatio(false), m_lastLoggedFrameSerial(0),
      m_lastPresentedFrameSerial(0), m_lastPresentationLogSerial(0) {
    setFlag(QQuickItem::ItemHasContents, true);
}

void MpvVideoMirrorItem::setUsage(const QString &usage) {
    const QString normalized = usage.trimmed().toLower();
    if (m_usage == normalized) return;
    m_usage = normalized;
    m_textureSharingLogged = false;
    m_lastLoggedFrameSerial = 0;
    m_lastPresentedFrameSerial = 0;
    m_lastPresentationLogSerial = 0;
    update();
    emit usageChanged();
}

void MpvVideoMirrorItem::setPreserveAspectRatio(bool preserve) {
    if (m_preserveAspectRatio == preserve) return;
    m_preserveAspectRatio = preserve;
    update();
    emit preserveAspectRatioChanged();
}

bool MpvVideoItem::sharedTextureSnapshot(unsigned int &textureId,
                                         QSize &textureSize,
                                         QOpenGLContext *&renderContext) const {
    textureId = 0;
    textureSize = QSize();
    renderContext = 0;
    if (!m_backend) return false;
    QMutexLocker locker(&m_backend->mutex);
    const int activeFramebuffer = m_backend->activeFramebuffer;
    QOpenGLFramebufferObject *framebuffer = activeFramebuffer >= 0
            ? m_backend->framebuffers[activeFramebuffer] : 0;
    if (!framebuffer) return false;
    textureId = framebuffer->texture();
    textureSize = framebuffer->size();
    renderContext = m_backend->renderGlContext;
    return textureId != 0 && !textureSize.isEmpty() && renderContext;
}

void MpvVideoMirrorItem::setSource(QObject *sourceObject) {
    MpvVideoItem *nextSource = qobject_cast<MpvVideoItem *>(sourceObject);
    if (m_source == nextSource) return;
    QObject::disconnect(m_frameConnection);
    QObject::disconnect(m_sourceDestroyedConnection);
    m_source = nextSource;
    m_textureSharingLogged = false;
    m_lastLoggedFrameSerial = 0;
    m_lastPresentedFrameSerial = 0;
    m_lastPresentationLogSerial = 0;
    if (m_source) {
        m_frameConnection = connect(m_source.data(),
                                    &MpvVideoItem::sharedTextureFrameChanged,
                                    this, [this](int frameSerial) {
            if (frameSerial <= 0) {
                m_lastLoggedFrameSerial = 0;
            } else if (m_lastLoggedFrameSerial == 0
                       || frameSerial - m_lastLoggedFrameSerial >= 60) {
                m_lastLoggedFrameSerial = frameSerial;
                if (m_usage == QStringLiteral("cover")) {
                    qInfo() << "native cover video: decoded shared-texture frame available"
                            << "serial" << frameSerial
                            << "decoderCopies" << 0;
                } else {
                    qInfo() << "native system PiP: mirrored shared-texture frame"
                            << "serial" << frameSerial
                            << "decoderCopies" << 0;
                }
            }
            update();
        });
        m_sourceDestroyedConnection = connect(m_source.data(), &QObject::destroyed,
                                               this, [this]() {
            m_source.clear();
            m_lastLoggedFrameSerial = 0;
            m_lastPresentedFrameSerial = 0;
            m_lastPresentationLogSerial = 0;
            update();
            emit sourceChanged();
        });
    }
    update();
    emit sourceChanged();
}

QSGNode *MpvVideoMirrorItem::updatePaintNode(
        QSGNode *oldNode, UpdatePaintNodeData *updatePaintNodeData) {
    Q_UNUSED(updatePaintNodeData)
    SharedTextureNode *node = static_cast<SharedTextureNode *>(oldNode);
    MpvVideoItem *sourceItem = m_source.data();
    if (!sourceItem || !sourceItem->m_backend || !window()) {
        delete node;
        return 0;
    }

    GLuint textureId = 0;
    QSize textureSize;
    QOpenGLContext *renderGlContext = 0;
    int frameSerial = 0;
    {
        QMutexLocker locker(&sourceItem->m_backend->mutex);
        const int activeFramebuffer = sourceItem->m_backend->activeFramebuffer;
        QOpenGLFramebufferObject *framebuffer = activeFramebuffer >= 0
                ? sourceItem->m_backend->framebuffers[activeFramebuffer] : 0;
        if (framebuffer) {
            textureId = framebuffer->texture();
            textureSize = framebuffer->size();
            renderGlContext = sourceItem->m_backend->renderGlContext;
            frameSerial = sourceItem->m_sharedTextureFrameSerial;
        }
    }
    if (!textureId || textureSize.isEmpty()) {
        delete node;
        return 0;
    }

    QOpenGLContext *sceneGraphContext = QOpenGLContext::currentContext();
    const bool contextsShare = renderGlContext && sceneGraphContext
            && QOpenGLContext::areSharing(renderGlContext, sceneGraphContext);
    if (!m_textureSharingLogged) {
        m_textureSharingLogged = true;
        if (m_usage == QStringLiteral("cover")) {
            qInfo() << "native cover video: scene graph shares persistent video texture"
                    << contextsShare;
        } else {
            qInfo() << "native system PiP: scene graph shares persistent video texture"
                    << contextsShare;
        }
    }
    if (!contextsShare) {
        delete node;
        return 0;
    }

    QSGTexture *texture = window()->createTextureFromId(textureId, textureSize);
    if (!texture) {
        delete node;
        return 0;
    }
    if (!node)
        node = new SharedTextureNode;
    node->replaceTexture(texture);
    QRectF targetRect = boundingRect();
    if (m_preserveAspectRatio && textureSize.width() > 0 && textureSize.height() > 0
            && targetRect.width() > 0.0 && targetRect.height() > 0.0) {
        const qreal textureAspect = static_cast<qreal>(textureSize.width())
                / textureSize.height();
        const qreal targetAspect = targetRect.width() / targetRect.height();
        if (textureAspect > targetAspect) {
            const qreal fittedHeight = targetRect.width() / textureAspect;
            targetRect.setY((targetRect.height() - fittedHeight) / 2.0);
            targetRect.setHeight(fittedHeight);
        } else {
            const qreal fittedWidth = targetRect.height() * textureAspect;
            targetRect.setX((targetRect.width() - fittedWidth) / 2.0);
            targetRect.setWidth(fittedWidth);
        }
    }
    node->setRect(targetRect);
    node->setFiltering(QSGTexture::Linear);
    node->setTextureCoordinatesTransform(QSGSimpleTextureNode::MirrorVertically);
    const bool backgroundPresentation = m_usage == QStringLiteral("cover")
            || m_usage == QStringLiteral("pip");
    if (backgroundPresentation && qApp
            && qApp->applicationState() != Qt::ApplicationActive
            && frameSerial > 0 && frameSerial != m_lastPresentedFrameSerial) {
        m_lastPresentedFrameSerial = frameSerial;
        // updatePaintNode() is the closest reliable Cover presentation edge
        // available on Sailfish. Queue the feedback to the GUI thread, where
        // the libmpv-owned GL context can be made current safely.
        QMetaObject::invokeMethod(sourceItem, "reportCoverSwap",
                                  Qt::QueuedConnection, Q_ARG(int, frameSerial));
        if (m_lastPresentationLogSerial == 0
                || frameSerial - m_lastPresentationLogSerial >= 30) {
            m_lastPresentationLogSerial = frameSerial;
            qInfo() << (m_usage == QStringLiteral("cover")
                        ? "native cover video: live shared-texture frame presented"
                        : "native system PiP: live shared-texture frame presented")
                    << "serial" << frameSerial
                    << "texture" << textureSize.width() << "x" << textureSize.height()
                    << "presentationItem" << qRound(width()) << "x" << qRound(height())
                    << "preserveAspect" << m_preserveAspectRatio
                    << "applicationState" << qApp->applicationState()
                    << "decoderCopies" << 0;
        }
    }
    return node;
}

void MpvVideoItem::loadSource(const QString &sourceUrl, double startPosition, bool pausedAfterLoad) {
    loadSourceInternal(sourceUrl, QString(), startPosition, pausedAfterLoad,
                       true, true);
}

void MpvVideoItem::loadSourceWithAudio(const QString &sourceUrl, const QString &audioUrl,
                                       double startPosition, bool pausedAfterLoad,
                                       bool videoEnabled) {
    loadSourceInternal(sourceUrl, audioUrl, startPosition, pausedAfterLoad,
                       videoEnabled, false);
}

void MpvVideoItem::loadSourceInternal(const QString &sourceUrl,
                                      const QString &audioUrl,
                                      double startPosition,
                                      bool pausedAfterLoad,
                                      bool videoEnabled,
                                      bool liveStreamSource) {
    if (sourceUrl.isEmpty() || !m_backend) return;
    if (!ensureMpv()) return;
    const bool forceSoftwareForThisLoad = m_hardwareFallbackForCurrentLoad;
    m_hardwareFallbackForCurrentLoad = false;
    stopHardwareDecode();
    m_originalVideoUrl = sourceUrl;
    m_originalAudioUrl = audioUrl;
    m_liveStreamSource = liveStreamSource;
    // A direct load (including a quality change) must never leave the last
    // source's texture attached while mpv opens the replacement stream.
    withdrawPresentedFrame("load-request");
    resetVideoGeometry("load-request");
    if (startPosition < 0.0) startPosition = 0.0;
    // Every video start holds audio until the current file and its first
    // texture are ready, including the usual zero-position start. Restricting
    // this to history resume let the independent DASH audio run ahead.
    m_initialPositionGatePending = videoEnabled;
    m_initialPositionConfirmed = !videoEnabled;
    m_initialVideoFrameReady = false;
    const bool hardwareStarted = videoEnabled && !forceSoftwareForThisLoad
            && startHardwareDecode(sourceUrl, startPosition);
    m_hardwareDecodeActive = hardwareStarted;
    m_hardwareFirstFramePending = hardwareStarted;
    m_hardwarePresentationCadenceLogged = false;
    // The hardware path owns only the video elementary stream. libmpv remains
    // the audio/output clock, using the separate DASH audio URL when present or
    // the combined source with vid=no for live/container playback.
    m_videoEnabled = videoEnabled && !hardwareStarted;
    m_sourceUrl = hardwareStarted
            ? (!audioUrl.isEmpty() ? audioUrl : sourceUrl)
            : (!videoEnabled && !audioUrl.isEmpty() ? audioUrl : sourceUrl);
    m_audioUrl = m_videoEnabled ? audioUrl : QString();
    m_loadCommandPending = true;
    m_pendingLoadStart = startPosition;
    m_pendingLoadPause = pausedAfterLoad;
    m_requestedPaused = pausedAfterLoad;
    m_requestedPosition = startPosition;
    m_requestedSpeed = 1.0;
    m_paused = pausedAfterLoad;
    m_position = startPosition;
    m_duration = 0.0;
    m_loading = true;
    m_playing = false;
    m_ended = false;
    m_playbackStarted = false;
    // A non-zero initial position is applied as a paused per-file start option.
    // Do not present a frame or release audio until the new file confirms the
    // same clock position; a bounded exact seek remains only as compatibility
    // fallback for older libmpv builds.
    m_seekPending = startPosition > 0.0;
    m_buffering = false;
    m_speed = 1.0;
    m_errorMessage.clear();
    resetProgressAnchor();
    syncProgressClock();
    ++m_loadSerial;
    if (m_backend && m_backend->mpv) {
        double normalSpeed = 1.0;
        mpv_set_property_async(m_backend->mpv, 0, "speed", MPV_FORMAT_DOUBLE, &normalSpeed);
        mpv_set_property_string(m_backend->mpv, "vid", m_videoEnabled ? "auto" : "no");
    }
    qInfo() << "native player: decode route selected"
            << "hardware" << hardwareStarted
            << "video" << (hardwareStarted ? sourceUrl : m_sourceUrl)
            << "audioSeparate" << !audioUrl.isEmpty()
            << "liveStream" << m_liveStreamSource
            << "fallbackForced" << forceSoftwareForThisLoad;
    emit stateChanged();
    emit positionChanged();
    update();
    submitPendingLoad();
}

void MpvVideoItem::beginSourceTransition() {
    if (!m_backend) return;
    m_foregroundRestoreTimer.stop();
    stopHardwareDecode();
    withdrawPresentedFrame("new-selection");
    resetVideoGeometry("new-selection");
    m_sourceUrl.clear();
    m_audioUrl.clear();
    m_liveStreamSource = false;
    m_loadCommandPending = false;
    m_backend->loadPending = false;
    m_initialPositionGatePending = false;
    m_initialPositionConfirmed = false;
    m_initialVideoFrameReady = false;
    m_requestedPosition = 0.0;
    m_pendingLoadStart = 0.0;
    m_position = 0.0;
    m_duration = 0.0;
    m_loading = true;
    m_playing = false;
    m_ended = false;
    m_playbackStarted = false;
    m_seekPending = false;
    m_buffering = false;
    resetProgressAnchor();
    syncProgressClock();
    if (m_backend->mpv) {
        const char *command[] = {"stop", 0};
        mpv_command_async(m_backend->mpv, 0, command);
    }
    qInfo() << "native player: new source transition started; previous playback stopped";
    emit stateChanged();
    emit positionChanged();
}

void MpvVideoItem::setPaused(bool paused) {
    if (!paused && m_ended && !m_sourceUrl.isEmpty()) {
        qInfo() << "native player: replay requested after EOF";
        const QString replayVideo = m_originalVideoUrl.isEmpty()
                ? m_sourceUrl : m_originalVideoUrl;
        const QString replayAudio = m_originalVideoUrl.isEmpty()
                ? m_audioUrl : m_originalAudioUrl;
        loadSourceInternal(replayVideo, replayAudio, 0.0, false, true,
                           m_liveStreamSource);
        return;
    }
    const bool changed = m_paused != paused || (paused && m_playing);
    if (paused && m_playing && !m_seekPending) {
        m_position = position();
        resetProgressAnchor();
    }
    m_requestedPaused = paused;
    m_pendingLoadPause = paused;
    if (m_backend && m_backend->loadPending) m_backend->pendingPause = paused;
    m_paused = paused;
    if (paused) m_playing = false;
    if (paused) resetFrameFloorWindow();
    if (m_backend && (m_backend->mpv || ensureMpv())) {
        int value = paused ? 1 : 0;
        if (!m_initialPositionGatePending || paused) {
            mpv_set_property_async(m_backend->mpv, 0, "pause",
                                   MPV_FORMAT_FLAG, &value);
        } else {
            qInfo() << "native player: unpause deferred until initial position gate"
                    << "target" << m_requestedPosition
                    << "loadSerial" << m_loadSerial;
        }
    }
    if (m_hardwareDecoder) {
        // A pause request made while the initial target is loading is the
        // desired post-start state. Keep the private decoder moving until it
        // has produced the target texture; releaseInitialPositionGate() then
        // applies the requested pause without ever starting audio.
        const bool pauseDecoderNow = paused && !m_initialPositionGatePending;
        m_hardwareDecoder->setPaused(pauseDecoderNow);
    }
    syncProgressClock();
    syncHardwareClock();
    if (changed) emit stateChanged();
    if (changed) emit positionChanged();
}

void MpvVideoItem::togglePaused() {
    if (m_ended)
        setPaused(false);
    else
        setPaused(!m_paused);
}

void MpvVideoItem::seek(double position) {
    if (position < 0.0) position = 0.0;
    if (m_duration > 0.0 && position > m_duration) position = m_duration;
    m_requestedPosition = position;
    m_pendingLoadStart = position;
    if (m_backend && m_backend->loadPending) m_backend->pendingStart = position;
    m_seekPending = true;
    if (m_backend && (m_backend->mpv || ensureMpv()) && !m_loadCommandPending) {
        const QByteArray value = QByteArray::number(position, 'f', 3);
        const char *command[] = {"seek", value.constData(), "absolute+exact", 0};
        mpv_command_async(m_backend->mpv, 0, command);
    }
    if (m_hardwareDecodeActive && m_hardwareDecoder)
        // The decoder primes the target texture even while audio stays paused.
        m_hardwareDecoder->seek(position);
    syncHardwareClock();
    emit stateChanged();
    emit positionChanged();
}

void MpvVideoItem::setVolume(double volume) {
    volume = qBound(0.0, volume, 100.0);
    if (qAbs(m_volume - volume) < 0.1) return;
    m_volume = volume;
    m_requestedVolume = volume;
    if (m_backend && (m_backend->mpv || ensureMpv())) {
        double value = volume;
        mpv_set_property_async(m_backend->mpv, 0, "volume", MPV_FORMAT_DOUBLE, &value);
    }
    emit stateChanged();
}

void MpvVideoItem::setBrightness(double brightness) {
    brightness = qBound(-100.0, brightness, 100.0);
    if (qAbs(m_brightness - brightness) < 0.1) return;
    m_brightness = brightness;
    m_requestedBrightness = brightness;
    if (m_backend && (m_backend->mpv || ensureMpv())) {
        double value = brightness;
        mpv_set_property_async(m_backend->mpv, 0, "brightness", MPV_FORMAT_DOUBLE, &value);
    }
    emit stateChanged();
}

void MpvVideoItem::setSpeed(double speed) {
    speed = qBound(0.25, speed, 4.0);
    if (qAbs(m_speed - speed) < 0.01) return;
    if (m_playing && !m_seekPending) {
        m_position = position();
        resetProgressAnchor();
    }
    m_speed = speed;
    m_requestedSpeed = speed;
    if (m_backend && (m_backend->mpv || ensureMpv())) {
        double value = speed;
        mpv_set_property_async(m_backend->mpv, 0, "speed", MPV_FORMAT_DOUBLE, &value);
    }
    qInfo() << "native player: speed" << speed;
    syncHardwareClock();
    emit stateChanged();
    emit positionChanged();
}

void MpvVideoItem::refreshVideoOutput() {
    if (!m_backend || !m_backend->mpv) return;
    qInfo() << "native player: foreground shared-texture repaint requested"
            << "frame" << m_sharedTextureFrameSerial;
    if (!isVisible()) setVisible(true);
    update();
}

void MpvVideoItem::reportDisplaySwap() {
    if (m_hardwareDecodeActive) return;
    if (qApp && qApp->applicationState() != Qt::ApplicationActive) return;
    if (!m_backend) return;
    QMutexLocker locker(&m_backend->mutex);
    if (!m_backend->renderContext || !m_backend->renderGlContext
            || !m_backend->renderSurface
            || !m_backend->renderGlContext->makeCurrent(m_backend->renderSurface))
        return;
    // report_swap() is meaningful only at the real window flip.  Keeping it
    // here (rather than beside the offscreen FBO render) lets display-resample
    // observe Lipstick/Qt's actual refresh cadence.
    mpv_render_context_report_swap(m_backend->renderContext);
    m_backend->renderGlContext->doneCurrent();
}

void MpvVideoItem::reportCoverSwap(int frameSerial) {
    if (frameSerial <= 0 || frameSerial <= m_lastCoverSwapFrameSerial
            || !qApp || qApp->applicationState() == Qt::ApplicationActive
            || !m_backend || m_hardwareDecodeActive)
        return;
    QMutexLocker locker(&m_backend->mutex);
    if (!m_backend->renderContext || !m_backend->renderGlContext
            || !m_backend->renderSurface
            || !m_backend->renderGlContext->makeCurrent(m_backend->renderSurface))
        return;
    mpv_render_context_report_swap(m_backend->renderContext);
    m_backend->renderGlContext->doneCurrent();
    m_lastCoverSwapFrameSerial = frameSerial;

    if (!m_coverSwapCadenceTimer.isValid()) {
        m_coverSwapCadenceFrames = 0;
        m_coverSwapCadenceTimer.start();
    }
    ++m_coverSwapCadenceFrames;
    const qint64 elapsedMs = m_coverSwapCadenceTimer.elapsed();
    if (elapsedMs >= 1000) {
        const double framesPerSecond = m_coverSwapCadenceFrames * 1000.0 / elapsedMs;
        qInfo() << "native cover video: presentation swap cadence"
                << "frames" << m_coverSwapCadenceFrames
                << "elapsedMs" << elapsedMs
                << "fps" << framesPerSecond
                << "lastSerial" << frameSerial
                << "decoderCopies" << 0;
        m_coverSwapCadenceFrames = 0;
        m_coverSwapCadenceTimer.restart();
    }
}

void MpvVideoItem::setFullResolutionPresentation(bool enabled) {
    if (m_fullResolutionPresentation == enabled) return;
    m_fullResolutionPresentation = enabled;
    qInfo() << "native player: presentation resolution profile"
            << (enabled ? "fullscreen-native" : "bounded-shared")
            << "item" << qRound(width()) << "x" << qRound(height())
            << "source" << m_videoWidth << "x" << m_videoHeight;
    if (!m_hardwareDecodeActive && width() >= 2 && height() >= 2 && !m_sourceUrl.isEmpty())
        sharedTextureRenderUpdate(this);
    emit stateChanged();
}

void MpvVideoItem::prepareForegroundSurface() {
    if (!m_backend || !m_backend->mpv || m_sourceUrl.isEmpty()) return;
    qInfo() << "native player: foreground persistent-frame repaint requested"
            << "frame" << m_sharedTextureFrameSerial;
    refreshVideoOutput();
}

void MpvVideoItem::scheduleForegroundRestore() {
    if (m_sourceUrl.isEmpty() || !m_backend || !m_backend->mpv) return;
    m_foregroundRestoreStage = 0;
    // Wait for Lipstick to expose the application surface. The session layer
    // owns QML host selection; this item owns a context-independent frame.
    m_foregroundRestoreTimer.start(80);
}

void MpvVideoItem::stop() {
    const bool changed = m_loading || m_playing || m_ended || qAbs(m_speed - 1.0) >= 0.01
            || m_videoWidth != 0 || m_videoHeight != 0;
    m_sourceUrl.clear();
    m_audioUrl.clear();
    m_originalVideoUrl.clear();
    m_originalAudioUrl.clear();
    m_liveStreamSource = false;
    stopHardwareDecode();
    m_loadCommandPending = false;
    if (m_backend) m_backend->loadPending = false;
    m_loading = false;
    m_playing = false;
    m_ended = false;
    m_playbackStarted = false;
    m_initialPositionGatePending = false;
    m_initialPositionConfirmed = false;
    m_initialVideoFrameReady = false;
    m_seekPending = false;
    m_buffering = false;
    m_speed = 1.0;
    m_requestedSpeed = 1.0;
    if (m_backend && m_backend->mpv) {
        double normalSpeed = 1.0;
        mpv_set_property_async(m_backend->mpv, 0, "speed", MPV_FORMAT_DOUBLE, &normalSpeed);
        const char *command[] = {"stop", 0};
        mpv_command_async(m_backend->mpv, 0, command);
        qInfo() << "native player: stop command submitted from GUI event loop";
    }
    withdrawPresentedFrame("stop");
    resetVideoGeometry("stop");
    syncProgressClock();
    if (changed) emit stateChanged();
}

void MpvVideoItem::updatePresentedTextureGeometry(
        const QSize &textureSize, const QSize &videoViewportSize) {
    const int width = qMax(0, textureSize.width());
    const int height = qMax(0, textureSize.height());
    const int videoWidth = qMax(0, videoViewportSize.width());
    const int videoHeight = qMax(0, videoViewportSize.height());
    if (m_presentedTextureWidth == width
            && m_presentedTextureHeight == height
            && m_presentedVideoWidth == videoWidth
            && m_presentedVideoHeight == videoHeight)
        return;
    m_presentedTextureWidth = width;
    m_presentedTextureHeight = height;
    m_presentedVideoWidth = videoWidth;
    m_presentedVideoHeight = videoHeight;
    qInfo() << "native player: presentation texture geometry"
            << width << "x" << height
            << "videoViewport" << videoWidth << "x" << videoHeight
            << "source" << m_videoWidth << "x" << m_videoHeight
            << "profile" << (m_fullResolutionPresentation
                               ? "fullscreen-native" : "bounded-shared");
    emit presentationGeometryChanged();
}

void MpvVideoItem::claimSurface(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host) return;
    if (m_surfaceHost == host && parentItem() == host) {
        resizeSurface();
        setVisible(true);
        update();
        return;
    }
    clearSurfaceConnections();
    m_surfaceHost = host;
    setParentItem(host);
    setVisible(true);
    resizeSurface();
    m_widthConnection = connect(host, &QQuickItem::widthChanged,
                                this, &MpvVideoItem::resizeSurface);
    m_heightConnection = connect(host, &QQuickItem::heightChanged,
                                 this, &MpvVideoItem::resizeSurface);
    m_destroyedConnection = connect(host, &QObject::destroyed, this, [this, host]() {
        if (m_surfaceHost == host) {
            clearSurfaceConnections();
            m_surfaceHost.clear();
            setVisible(false);
        }
    });
    qInfo() << "native player: surface claimed by direct host"
            << host->width() << "x" << host->height();
    update();
}

void MpvVideoItem::releaseSurface(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host || m_surfaceHost != host) return;
    clearSurfaceConnections();
    m_surfaceHost.clear();
    setVisible(false);
    qInfo() << "native player: direct host released";
}

void MpvVideoItem::submitPendingLoad() {
    if (!m_loadCommandPending || m_sourceUrl.isEmpty() || !m_backend) return;
    if (!m_backend->mpv && !ensureMpv()) return;

    // libmpv requires its render context before playback creates a VO. The
    // persistent shared-texture context is made during ensureMpv() and survives
    // every Cover transition.
    {
        QMutexLocker locker(&m_backend->mutex);
        if (!m_backend->renderContext) {
            update();
            return;
        }
    }

    const QByteArray source = m_sourceUrl.toUtf8();
    QStringList fileOptions;
    fileOptions.append(QStringLiteral("referrer=\"https://www.bilibili.com\""));
    fileOptions.append(QStringLiteral("network-timeout=5"));
    if (m_liveStreamSource) {
        // The global low-latency probe budget is sized for Bilibili DASH MP4.
        // FLV live streams can place the first AAC metadata/packet after the
        // first 32 KiB; when the direct decoder owns video, libmpv would then
        // see no selected stream and terminate the audio clock. Give only live
        // container loads enough data to discover their audio track.
        fileOptions.append(QStringLiteral("demuxer-lavf-analyzeduration=1"));
        fileOptions.append(QStringLiteral("demuxer-lavf-probesize=1048576"));
    }
    if (m_pendingLoadStart > 0.0) {
        // Position the audio demuxer before it is allowed to run. Previously
        // audio started at zero and FILE_LOADED issued a second exact seek,
        // producing audible playback followed by a visible/time jump.
        fileOptions.append(QStringLiteral("start=%1").arg(
                               m_pendingLoadStart, 0, 'f', 3));
    }
    if (m_initialPositionGatePending || m_pendingLoadPause)
        fileOptions.append(QStringLiteral("pause=yes"));
    if (!m_audioUrl.isEmpty())
        fileOptions.append(QStringLiteral("audio-file=\"%1\"").arg(m_audioUrl));
    const QByteArray options = fileOptions.join(QStringLiteral(",")).toUtf8();
    m_backend->loadPending = true;
    m_backend->pendingStart = m_pendingLoadStart;
    m_backend->pendingPause = m_pendingLoadPause;
    m_loadCommandPending = false;
    if (options.isEmpty()) {
        const char *command[] = {"loadfile", source.constData(), "replace", 0};
        mpv_command_async(m_backend->mpv, 0, command);
    } else if (mpv_client_api_version() >= MPV_MAKE_VERSION(2, 3)) {
        const char *command[] = {"loadfile", source.constData(), "replace", "0",
                                 options.constData(), 0};
        mpv_command_async(m_backend->mpv, 0, command);
    } else {
        const char *command[] = {"loadfile", source.constData(), "replace",
                                 options.constData(), 0};
        mpv_command_async(m_backend->mpv, 0, command);
    }
    qInfo() << "native player: load command submitted serial" << m_loadSerial
            << "from GUI event loop at" << m_backend->pendingStart
            << "paused" << m_backend->pendingPause
            << "dashAudio" << !m_audioUrl.isEmpty()
            << "startOption" << (m_backend->pendingStart > 0.0)
            << "audioStartGated" << m_initialPositionGatePending
            << "videoEnabled" << m_videoEnabled;
}

void MpvVideoItem::drainMpvEvents() {
    if (!m_backend || !m_backend->mpv) return;
    mpv_handle *mpv = m_backend->mpv;
    while (true) {
        mpv_event *event = mpv_wait_event(mpv, 0.0);
        if (!event || event->event_id == MPV_EVENT_NONE) break;
        if (event->event_id == MPV_EVENT_START_FILE) {
            qInfo() << "native player: start file";
            updateStartFileFromMpv();
        } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
            qInfo() << "native player: file loaded";
            double sourceFramesPerSecond = 0.0;
            if (mpv_get_property(mpv, "estimated-vf-fps", MPV_FORMAT_DOUBLE,
                                 &sourceFramesPerSecond) >= 0)
                updateSourceFrameRateFromMpv(sourceFramesPerSecond);
            const QString decoderName = mpvStringProperty(
                        mpv, "current-tracks/video/decoder");
            const QString decoderDescription = mpvStringProperty(
                        mpv, "current-tracks/video/decoder-desc");
            const QString v4l2Device = activeV4l2Device();
            const bool v4l2M2mDecoder = decoderName.contains(
                        QStringLiteral("v4l2m2m"), Qt::CaseInsensitive)
                    || (decoderDescription.contains(
                        QStringLiteral("V4L2"), Qt::CaseInsensitive)
                    && decoderDescription.contains(QStringLiteral("mem2mem"),
                                                   Qt::CaseInsensitive))
                    || !v4l2Device.isEmpty();
            qInfo() << "native player: decoder state"
                    << "decoder" << decoderName
                    << "description" << decoderDescription
                    << "codec" << mpvStringProperty(mpv, "video-codec")
                    << "format" << mpvStringProperty(mpv, "video-format")
                    << "v4l2M2m" << v4l2M2mDecoder
                    << "v4l2Device" << (v4l2Device.isEmpty()
                                         ? QStringLiteral("unavailable") : v4l2Device)
                    << "hwdec" << mpvStringProperty(mpv, "hwdec-current")
                    << "interop" << mpvStringProperty(mpv, "hwdec-interop")
                    << "pixelFormat" << mpvStringProperty(mpv, "video-params/pixelformat")
                    << "hardwarePixelFormat"
                    << mpvStringProperty(mpv, "video-params/hw-pixelformat");
            const double startPosition = m_backend->loadPending
                                         ? m_backend->pendingStart : 0.0;
            const bool pausedAfterLoad = m_backend->loadPending
                                         ? m_backend->pendingPause : m_requestedPaused;
            m_backend->loadPending = false;
            if (m_initialPositionGatePending && startPosition > 0.0) {
                double loadedPosition = -1.0;
                const bool startApplied = mpv_get_property(
                            mpv, "time-pos", MPV_FORMAT_DOUBLE,
                            &loadedPosition) >= 0
                        && qAbs(startPosition - loadedPosition) < 0.75;
                if (startApplied) {
                    updatePositionFromMpv(loadedPosition);
                } else {
                    // Older libmpv builds may ignore the per-file start
                    // option. They remain paused, so this bounded exact seek
                    // cannot leak time-zero audio before target confirmation.
                    const QByteArray position = QByteArray::number(
                                startPosition, 'f', 3);
                    const char *seekCommand[] = {
                        "seek", position.constData(), "absolute+exact", 0
                    };
                    mpv_command_async(mpv, 0, seekCommand);
                    qInfo() << "native player: initial position fallback seek"
                            << "target" << startPosition
                            << "loadedPosition" << loadedPosition
                            << "audioHeld" << true
                            << "loadSerial" << m_loadSerial;
                }
            } else if (m_initialPositionGatePending) {
                // A zero start needs no seek or advancing audio clock. The
                // paused video decoder may already have retained its frame.
                m_initialPositionConfirmed = true;
                enableSourceFramePresentation("initial-zero-start-confirmed");
                releaseInitialPositionGate(m_position);
            } else {
                int paused = pausedAfterLoad ? 1 : 0;
                mpv_set_property_async(mpv, 0, "pause",
                                       MPV_FORMAT_FLAG, &paused);
                updateLoadingFromMpv(false);
            }
        } else if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *message = static_cast<mpv_event_log_message *>(event->data);
            if (!message || !message->text) continue;
            const QString text = QString::fromUtf8(message->text).trimmed();
            const QString prefix = QString::fromUtf8(message->prefix ? message->prefix : "");
            const QString level = QString::fromUtf8(message->level ? message->level : "");
            const bool decoderDiagnostic = prefix == QStringLiteral("vd")
                    || prefix.startsWith(QStringLiteral("ffmpeg/video"))
                    || text.contains(QStringLiteral("v4l2"), Qt::CaseInsensitive)
                    || text.contains(QStringLiteral("m2m"), Qt::CaseInsensitive)
                    || text.contains(QStringLiteral("decoder"), Qt::CaseInsensitive)
                    || text.contains(QStringLiteral("decoding"), Qt::CaseInsensitive)
                    || text.contains(QStringLiteral("failed"), Qt::CaseInsensitive)
                    || text.contains(QStringLiteral("device"), Qt::CaseInsensitive)
                    || level == QStringLiteral("error") || level == QStringLiteral("fatal")
                    || level == QStringLiteral("warn");
            if (decoderDiagnostic && !text.isEmpty())
                qInfo() << "native player: mpv log" << prefix << level << text;
        } else if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            mpv_event_property *property = static_cast<mpv_event_property *>(event->data);
            if (!property || !property->data) continue;
            const QByteArray name(property->name);
            if ((name == "time-pos" || name == "duration")
                    && property->format == MPV_FORMAT_DOUBLE) {
                const double value = *static_cast<double *>(property->data);
                if (name == "time-pos")
                    updatePositionFromMpv(value);
                else
                    updateDurationFromMpv(value);
            } else if (name == "pause" && property->format == MPV_FORMAT_FLAG) {
                updatePausedFromMpv(*static_cast<int *>(property->data) != 0);
            } else if (name == "paused-for-cache" && property->format == MPV_FORMAT_FLAG) {
                updateBufferingFromMpv(*static_cast<int *>(property->data) != 0);
            } else if (name == "estimated-vf-fps" && property->format == MPV_FORMAT_DOUBLE) {
                updateSourceFrameRateFromMpv(*static_cast<double *>(property->data));
            } else if (name == "video-out-params" && property->format == MPV_FORMAT_NODE) {
                const mpv_node *params = static_cast<const mpv_node *>(property->data);
                int64_t displayWidth = 0;
                int64_t displayHeight = 0;
                int64_t sourceWidth = 0;
                int64_t sourceHeight = 0;
                int64_t rotation = 0;
                if (params->format == MPV_FORMAT_NODE_MAP && params->u.list) {
                    for (int index = 0; index < params->u.list->num; ++index) {
                        const char *key = params->u.list->keys[index];
                        const mpv_node &value = params->u.list->values[index];
                        if (!key || value.format != MPV_FORMAT_INT64) continue;
                        if (std::strcmp(key, "dw") == 0)
                            displayWidth = value.u.int64;
                        else if (std::strcmp(key, "dh") == 0)
                            displayHeight = value.u.int64;
                        else if (std::strcmp(key, "w") == 0)
                            sourceWidth = value.u.int64;
                        else if (std::strcmp(key, "h") == 0)
                            sourceHeight = value.u.int64;
                        else if (std::strcmp(key, "rotate") == 0)
                            rotation = value.u.int64;
                    }
                }
                if (displayWidth <= 0) displayWidth = sourceWidth;
                if (displayHeight <= 0) displayHeight = sourceHeight;
                const int normalizedRotation = static_cast<int>((rotation % 360 + 360) % 360);
                qInfo() << "native player: raw video geometry"
                        << "source" << sourceWidth << "x" << sourceHeight
                        << "display" << displayWidth << "x" << displayHeight
                        << "rotation" << normalizedRotation;
                if (normalizedRotation == 90 || normalizedRotation == 270) {
                    const int64_t rotatedWidth = displayHeight;
                    displayHeight = displayWidth;
                    displayWidth = rotatedWidth;
                }
                if (displayWidth > 0 && displayHeight > 0) {
                    if (m_dropVideoGeometryEventForTest) {
                        qInfo() << "native player: video geometry event intentionally dropped for regression"
                                << displayWidth << "x" << displayHeight
                                << "loadSerial" << m_loadSerial;
                    } else {
                        updateVideoGeometryFromMpv(static_cast<int>(displayWidth),
                                                   static_cast<int>(displayHeight));
                    }
                }
            }
        } else if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) {
            updatePlaybackRestartFromMpv();
        } else if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *end = static_cast<mpv_event_end_file *>(event->data);
            const bool ended = end && end->reason == MPV_END_FILE_REASON_EOF;
            if (end)
                qInfo() << "native player: end file reason" << end->reason
                        << "error" << end->error;
            // loadfile replace emits END_FILE(STOP) for the superseded audio-
            // only source after the new load has already installed its target
            // seek gate. It belongs to the old file and must not clear the new
            // file's m_seekPending/presentation state.
            if (end && end->reason == MPV_END_FILE_REASON_STOP
                    && m_backend->loadPending) {
                qInfo() << "native player: superseded source end ignored"
                        << "pendingTarget" << m_backend->pendingStart
                        << "loadSerial" << m_loadSerial;
                continue;
            }
            // A Cover must never restart media just to recover its surface.
            // The renderer keeps a retained context when possible and lets Qt
            // recreate it only for a real scene-graph loss. If libmpv still
            // reports a terminal VO error, surface a normal error instead of
            // silently reloading/seeking and breaking audio continuity.
            if (end && end->reason == MPV_END_FILE_REASON_ERROR
                    && end->error == MPV_ERROR_VO_INIT_FAILED
                    && !m_sourceUrl.isEmpty()) {
                qWarning() << "native player: terminal video-output error; source reload suppressed";
                updateEndFileFromMpv(false);
                updateErrorFromMpv(QString::fromUtf8(mpv_error_string(end->error)));
            } else {
                updateEndFileFromMpv(ended);
                if (end && end->error < 0)
                    updateErrorFromMpv(QString::fromUtf8(mpv_error_string(end->error)));
            }
        }
    }
}

void MpvVideoItem::updatePositionFromMpv(double position) {
    // During loadfile replacement, time-pos can briefly report the superseded
    // source. An initial target is valid only after FILE_LOADED clears the
    // backend load latch; ordinary in-place seeks keep their existing path.
    const bool newFileReady = !m_initialPositionGatePending
            || (m_backend && !m_backend->loadPending);
    const bool confirmedSeek = m_seekPending && newFileReady
            && qAbs(m_requestedPosition - position) < 0.75;
    const bool changed = qAbs(m_position - position) >= 0.05 || confirmedSeek;
    m_position = position;
    resetProgressAnchor();
    syncHardwareClock();
    if (confirmedSeek) {
        m_seekPending = false;
        if (m_initialPositionGatePending)
            m_initialPositionConfirmed = true;
        qInfo() << "native player: requested position frame gate confirmed"
                << "target" << m_requestedPosition
                << "actual" << position
                << "loadSerial" << m_loadSerial;
        if (enableSourceFramePresentation("requested-position-confirmed"))
            sharedTextureRenderUpdate(this);
        releaseInitialPositionGate(position);
    }
    if (changed && (!m_progressClockTimer.isActive() || confirmedSeek))
        emit positionChanged();
}

void MpvVideoItem::releaseInitialPositionGate(double confirmedPosition) {
    if (!m_initialPositionGatePending || !m_initialPositionConfirmed
            || !m_initialVideoFrameReady || !m_backend || m_backend->loadPending)
        return;
    m_initialPositionGatePending = false;
    const bool remainPaused = m_requestedPaused;
    updateLoadingFromMpv(false);
    if (m_backend && m_backend->mpv) {
        int paused = remainPaused ? 1 : 0;
        mpv_set_property_async(m_backend->mpv, 0, "pause",
                               MPV_FORMAT_FLAG, &paused);
    }
    if (m_hardwareDecoder)
        m_hardwareDecoder->setPaused(remainPaused);
    qInfo() << "native player: initial position gate released"
            << "target" << m_requestedPosition
            << "actual" << confirmedPosition
            << "audioReleased" << !remainPaused
            << "audioFromConfirmedTarget" << true
            << "firstVideoFrameReady" << true
            << "loadSerial" << m_loadSerial;
}

void MpvVideoItem::updateDurationFromMpv(double duration) {
    if (qAbs(m_duration - duration) < 0.05) return;
    m_duration = duration;
    emit stateChanged();
}

void MpvVideoItem::updatePausedFromMpv(bool paused) {
    // The load gate's internal pause is not a user pause. Preserve the user's
    // intent in the controls until releaseInitialPositionGate applies it.
    if (m_initialPositionGatePending) paused = m_requestedPaused;
    if (paused && m_playing && !m_seekPending) {
        m_position = position();
        resetProgressAnchor();
    }
    const bool nextPlaying = m_playbackStarted && !paused && !m_requestedPaused
                             && !m_loading && !m_ended && m_errorMessage.isEmpty();
    const bool changed = m_paused != paused || m_playing != nextPlaying;
    m_paused = paused;
    m_playing = nextPlaying;
    if (paused) resetFrameFloorWindow();
    if (!paused) resetProgressAnchor();
    syncProgressClock();
    if (changed) emit stateChanged();
    if (changed) emit positionChanged();
}

void MpvVideoItem::updateBufferingFromMpv(bool buffering) {
    if (m_buffering == buffering) return;
    if (buffering && m_playing && !m_seekPending)
        m_position = position();
    m_buffering = buffering;
    resetFrameFloorWindow();
    resetProgressAnchor();
    syncProgressClock();
    qInfo() << "native player: progress clock buffering" << buffering;
    emit positionChanged();
}

void MpvVideoItem::updateSourceFrameRateFromMpv(double framesPerSecond) {
    if (framesPerSecond <= 0.0 || qAbs(m_sourceFrameRate - framesPerSecond) < 0.01) return;
    // estimated-vf-fps can continue refining on variable-rate files. Lock the
    // eligibility decision after presentation starts so tiny estimator changes
    // cannot keep discarding otherwise valid one-second windows.
    if (m_sourceFrameRate > 0.0 && m_sharedTextureFrameSerial > 1) return;
    m_sourceFrameRate = framesPerSecond;
    resetFrameFloorWindow();
    qInfo() << "native player: frame floor source rate"
            << "sourceFps" << m_sourceFrameRate
            << "thresholdFps" << kMinimumPlaybackFrameRate
            << "eligible" << (m_sourceFrameRate + 0.5 >= kMinimumPlaybackFrameRate);
    emit stateChanged();
}

void MpvVideoItem::updateLoadingFromMpv(bool loading) {
    if (m_initialPositionGatePending) loading = true;
    if (loading && m_playing && !m_seekPending) {
        m_position = position();
        resetProgressAnchor();
    }
    const bool changed = m_loading != loading || (loading && m_playing);
    m_loading = loading;
    if (loading) resetFrameFloorWindow();
    if (loading) m_playing = false;
    syncProgressClock();
    if (changed) emit stateChanged();
}

void MpvVideoItem::updateStartFileFromMpv() {
    const bool changed = !m_loading || m_playing || m_ended;
    m_loading = true;
    m_playing = false;
    m_ended = false;
    m_playbackStarted = false;
    m_sourceFileStartedForPresentation = true;
    syncProgressClock();
    if (changed) emit stateChanged();
}

void MpvVideoItem::updatePlaybackRestartFromMpv() {
    const bool nextPlaying = !m_initialPositionGatePending
            && !m_paused && !m_requestedPaused && m_errorMessage.isEmpty();
    const bool changed = m_loading || m_ended || m_playing != nextPlaying;
    m_loading = m_initialPositionGatePending;
    m_ended = false;
    m_playbackStarted = true;
    m_playing = nextPlaying;
    resetProgressAnchor();
    syncProgressClock();
    if (!enableSourceFramePresentation("playback-restart")
            && m_sourceFileStartedForPresentation)
        qInfo() << "native player: new source frame presentation deferred"
                << "reason" << "video-geometry-not-ready"
                << "loadSerial" << m_loadSerial;
    if (changed) emit stateChanged();
    if (changed) emit positionChanged();
}

void MpvVideoItem::updateEndFileFromMpv(bool ended) {
    if (ended) reportFrameFloorSummary("eof");
    if (m_playing && !m_seekPending) m_position = position();
    const bool changed = m_loading || m_playing || m_ended != ended;
    m_loading = false;
    m_playing = false;
    m_ended = ended;
    m_playbackStarted = false;
    m_initialPositionGatePending = false;
    m_initialPositionConfirmed = false;
    m_initialVideoFrameReady = false;
    m_seekPending = false;
    m_buffering = false;
    resetProgressAnchor();
    syncProgressClock();
    if (changed) emit stateChanged();
    if (changed) emit positionChanged();
}

void MpvVideoItem::updateErrorFromMpv(const QString &message) {
    if (m_playing && !m_seekPending) m_position = position();
    const bool changed = m_errorMessage != message || m_loading || m_playing || m_ended;
    m_errorMessage = message;
    m_loading = false;
    m_playing = false;
    m_ended = false;
    m_playbackStarted = false;
    m_initialPositionGatePending = false;
    m_initialPositionConfirmed = false;
    m_initialVideoFrameReady = false;
    m_seekPending = false;
    m_buffering = false;
    resetProgressAnchor();
    syncProgressClock();
    if (changed) emit stateChanged();
    if (changed) emit positionChanged();
}

void MpvVideoItem::updateVideoGeometryFromMpv(int width, int height) {
    if (width <= 0 || height <= 0 || (m_videoWidth == width && m_videoHeight == height)) return;
    m_videoWidth = width;
    m_videoHeight = height;
    qInfo() << "native player: video geometry" << width << "x" << height
            << "aspect" << videoAspectRatio();
    enableSourceFramePresentation("video-geometry-ready");
    emit stateChanged();
}

bool MpvVideoItem::enableSourceFramePresentation(const char *reason) {
    // A paused non-zero start intentionally withholds MPV playback restart
    // until the first picture is ready. Once the new file has confirmed its
    // target, allow that verified paused frame to become visible so releasing
    // audio does not depend on an event that itself requires audio to run.
    const bool confirmedInitialFrame = m_initialPositionGatePending
            && m_initialPositionConfirmed;
    if (!m_backend || (!m_playbackStarted && !confirmedInitialFrame)
            || !m_sourceFileStartedForPresentation
            || m_seekPending || videoAspectRatio() <= 0.0)
        return false;

    bool enabledNewSourceFrame = false;
    bool publishedPendingFrame = false;
    QSize pendingFramebufferSize;
    GLuint pendingTexture = 0;
    {
        QMutexLocker locker(&m_backend->mutex);
        if (!m_backend->presentationEnabled) {
            m_backend->presentationEnabled = true;
            if (m_backend->pendingFramebuffer >= 0
                    && m_backend->framebuffers[m_backend->pendingFramebuffer]) {
                m_backend->activeFramebuffer = m_backend->pendingFramebuffer;
                m_backend->pendingFramebuffer = -1;
                QOpenGLFramebufferObject *framebuffer =
                        m_backend->framebuffers[m_backend->activeFramebuffer];
                pendingFramebufferSize = framebuffer->size();
                pendingTexture = framebuffer->texture();
                publishedPendingFrame = true;
            } else {
                m_backend->activeFramebuffer = -1;
            }
            enabledNewSourceFrame = true;
        }
    }
    if (!enabledNewSourceFrame) return false;

    m_sourceFileStartedForPresentation = false;
    qInfo() << "native player: new source frame presentation enabled"
            << "reason" << reason
            << "loadSerial" << m_loadSerial
            << "videoAspect" << videoAspectRatio();
    if (publishedPendingFrame) {
        updatePresentedTextureGeometry(
                    pendingFramebufferSize,
                    fittedVideoViewport(pendingFramebufferSize,
                                        m_videoWidth, m_videoHeight));
        m_sharedTextureFrameSerial = 1;
        m_initialVideoFrameReady = true;
        m_sharedTextureFrameTimer.start();
        recordPresentedFrameForFloor();
        qInfo() << "native player: first persistent shared-texture frame rendered"
                << pendingFramebufferSize.width() << "x" << pendingFramebufferSize.height()
                << "texture" << pendingTexture
                << "loadSerial" << m_loadSerial
                << "item" << qRound(width()) << "x" << qRound(height())
                << "videoAspect" << videoAspectRatio()
                << "retainedBeforeGeometry" << true;
        emit firstFramePresented(m_loadSerial, position());
        releaseInitialPositionGate(m_position);
        update();
        emit sharedTextureFrameChanged(m_sharedTextureFrameSerial);
        return true;
    }
    // Render only after mpv reports non-zero source geometry. PLAYBACK_RESTART
    // can precede the first decoded video frame when separate DASH audio has
    // already started; presenting an empty FBO at that point causes a black
    // video interval and falsely counts it as the first frame.
    if (!m_hardwareDecodeActive)
        sharedTextureRenderUpdate(this);
    return true;
}

void MpvVideoItem::resizeSurface() {
    QQuickItem *host = m_surfaceHost.data();
    if (!host) return;
    setX(0);
    setY(0);
    setWidth(host->width());
    setHeight(host->height());
    // A paused frame has no natural mpv update callback. Force one render pass
    // so an orientation/host-size change gets a matching FBO instead of
    // stretching the previous portrait or landscape texture.
    if (!m_hardwareDecodeActive && width() >= 2 && height() >= 2 && !m_sourceUrl.isEmpty())
        sharedTextureRenderUpdate(this);
    update();
}

void MpvVideoItem::resetVideoGeometry(const char *reason) {
    m_pendingGeometryLogEmitted = false;
    if (m_videoWidth == 0 && m_videoHeight == 0) return;
    qInfo() << "native player: video geometry reset"
            << "reason" << reason
            << "previous" << m_videoWidth << "x" << m_videoHeight;
    m_videoWidth = 0;
    m_videoHeight = 0;
}

void MpvVideoItem::clearSurfaceConnections() {
    QObject::disconnect(m_widthConnection);
    QObject::disconnect(m_heightConnection);
    QObject::disconnect(m_destroyedConnection);
    m_widthConnection = QMetaObject::Connection();
    m_heightConnection = QMetaObject::Connection();
    m_destroyedConnection = QMetaObject::Connection();
}

void MpvVideoItem::withdrawPresentedFrame(const char *reason) {
    const int previousFrameSerial = m_sharedTextureFrameSerial;
    if (m_backend) {
        QMutexLocker locker(&m_backend->mutex);
        m_backend->presentationEnabled = false;
        m_backend->activeFramebuffer = -1;
        m_backend->pendingFramebuffer = -1;
    }
    m_sharedTextureFrameSerial = 0;
    updatePresentedTextureGeometry(QSize(), QSize());
    m_sharedTextureFrameTimer.invalidate();
    m_lastCoverSwapFrameSerial = 0;
    m_coverSwapCadenceFrames = 0;
    m_coverSwapCadenceTimer.invalidate();
    resetFrameFloorQualification();
    m_sourceFileStartedForPresentation = false;
    qInfo() << "native player: previous source texture withdrawn"
            << "reason" << reason
            << "previousFrameSerial" << previousFrameSerial;
    update();
    emit sharedTextureFrameChanged(0);
}
