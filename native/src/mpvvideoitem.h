#pragma once

#include <QQuickItem>
#include <QAtomicInt>
#include <QElapsedTimer>
#include <QMetaObject>
#include <QPointer>
#include <QSize>
#include <QString>
#include <QTimer>

class MpvVideoBackend;
class DroidVideoDecoder;
class QOpenGLContext;
class QSGNode;

class MpvVideoItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(bool paused READ paused NOTIFY stateChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(bool ended READ ended NOTIFY stateChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY stateChanged)
    Q_PROPERTY(double volume READ volume NOTIFY stateChanged)
    Q_PROPERTY(double brightness READ brightness NOTIFY stateChanged)
    Q_PROPERTY(double speed READ speed NOTIFY stateChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY stateChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY stateChanged)
    Q_PROPERTY(double sourceFrameRate READ sourceFrameRate NOTIFY stateChanged)
    Q_PROPERTY(double videoAspectRatio READ videoAspectRatio NOTIFY stateChanged)
    Q_PROPERTY(int loadSerial READ loadSerial)
    Q_PROPERTY(int presentedLoadSerial READ presentedLoadSerial)
    Q_PROPERTY(int presentedFrameSerial READ presentedFrameSerial)
    Q_PROPERTY(int presentedTextureWidth READ presentedTextureWidth
               NOTIFY presentationGeometryChanged)
    Q_PROPERTY(int presentedTextureHeight READ presentedTextureHeight
               NOTIFY presentationGeometryChanged)
    Q_PROPERTY(int presentedVideoWidth READ presentedVideoWidth
               NOTIFY presentationGeometryChanged)
    Q_PROPERTY(int presentedVideoHeight READ presentedVideoHeight
               NOTIFY presentationGeometryChanged)
    Q_PROPERTY(bool fullResolutionPresentation READ fullResolutionPresentation
               WRITE setFullResolutionPresentation NOTIFY stateChanged)
    Q_PROPERTY(bool hardwareDecoding READ hardwareDecoding NOTIFY stateChanged)
    Q_PROPERTY(bool rendererReady READ rendererReady NOTIFY rendererReadyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)

public:
    explicit MpvVideoItem(QQuickItem *parent = 0);
    ~MpvVideoItem() override;

    bool paused() const { return m_paused; }
    bool loading() const { return m_loading; }
    bool playing() const { return m_playing; }
    bool ended() const { return m_ended; }
    double position() const;
    double duration() const { return m_duration; }
    double volume() const { return m_volume; }
    double brightness() const { return m_brightness; }
    double speed() const { return m_speed; }
    int videoWidth() const { return m_videoWidth; }
    int videoHeight() const { return m_videoHeight; }
    double sourceFrameRate() const { return m_sourceFrameRate; }
    double videoAspectRatio() const {
        return m_videoHeight > 0 ? static_cast<double>(m_videoWidth) / m_videoHeight : 0.0;
    }
    int loadSerial() const { return m_loadSerial; }
    int presentedLoadSerial() const {
        return m_sharedTextureFrameSerial > 0 ? m_loadSerial : 0;
    }
    int presentedFrameSerial() const { return m_sharedTextureFrameSerial; }
    int presentedTextureWidth() const { return m_presentedTextureWidth; }
    int presentedTextureHeight() const { return m_presentedTextureHeight; }
    int presentedVideoWidth() const { return m_presentedVideoWidth; }
    int presentedVideoHeight() const { return m_presentedVideoHeight; }
    bool fullResolutionPresentation() const { return m_fullResolutionPresentation; }
    bool hardwareDecoding() const { return m_hardwareDecodeActive; }
    bool rendererReady() const;
    bool sharedTextureSnapshot(unsigned int &textureId, QSize &textureSize,
                               QOpenGLContext *&renderContext) const;
    QString errorMessage() const { return m_errorMessage; }

public slots:
    // Build the persistent libmpv/OpenGL state after Qt Quick has created its
    // global share context, before the user asks a video to start.
    void prewarm();
    void loadSource(const QString &sourceUrl, double startPosition = 0.0, bool pausedAfterLoad = false);
    void loadSourceWithAudio(const QString &sourceUrl, const QString &audioUrl,
                             double startPosition = 0.0, bool pausedAfterLoad = false,
                             bool videoEnabled = true);
    // Withdraw the currently presented texture as soon as navigation selects
    // another video. The persistent renderer remains alive for the next load.
    void beginSourceTransition();
    void setPaused(bool paused);
    void togglePaused();
    void seek(double position);
    void setVolume(double volume);
    void setBrightness(double brightness);
    void setSpeed(double speed);
    // Ask Qt Quick to present the current libmpv frame after a Sailfish Cover
    // return. This never changes the decoder, audio, source or playback clock.
    void prepareForegroundSurface();
    void refreshVideoOutput();
    // Feed libmpv the real Qt Quick swap time.  Reporting an offscreen FBO
    // render as a display swap makes display-resample overproduce frames and
    // steals bandwidth from the actual 1080p scene-graph presentation.
    void reportDisplaySwap();
    // The Sailfish Cover is rendered by Lipstick after the application's main
    // QQuickView stops swapping.  Feed back each distinct texture that the
    // Cover scene graph really consumed so display-resample keeps advancing
    // without inventing a decoder, reload or timer-driven fake swap.
    void reportCoverSwap(int frameSerial);
    void setFullResolutionPresentation(bool enabled);
    void stop();
    // Final process-exit barrier. Unlike stop(), this also destroys the
    // persistent mpv/GL backend after the overlay has been hidden.
    void shutdown();
    void claimSurface(QObject *hostObject);
    void releaseSurface(QObject *hostObject);

signals:
    void stateChanged();
    void rendererReadyChanged();
    void positionChanged();
    // Emitted only after the new source has produced a real application-owned
    // texture. Device tests use this as the end of the startup latency gate.
    void firstFramePresented(int loadSerial, double position);
    void hardwareFirstFrameTimedOut(int loadSerial, int width, int height,
                                    double framesPerSecond);
    // Live has no seekable position to retain. If an original/UHD source is
    // rejected before its first frame, let PlaybackSession request a lower
    // advertised qn instead of attempting a phone-hostile software decode.
    void unsafeLiveQualityRejected(int loadSerial, const QString &reason);
    // A lightweight second QQuickItem can sample the same application-owned
    // texture in Lipstick's system overlay. This signal never owns or decodes
    // media; it only schedules another scene-graph presentation of the frame.
    void sharedTextureFrameChanged(int frameSerial);
    // Unlike videoWidth/videoHeight (decoder input), these dimensions describe
    // the application-owned texture that Qt Quick actually scales to screen.
    // Keeping both observable prevents a 1080p input from being reported as
    // 1080p presentation when the shared framebuffer is still compact-sized.
    void presentationGeometryChanged();

private slots:
    void advanceProgressClock();
    void monitorHardwareProgress();
    void renderSharedTextureFrame();
    void submitPendingLoad();
    void drainMpvEvents();
    void updatePositionFromMpv(double position);
    void updateDurationFromMpv(double duration);
    void updatePausedFromMpv(bool paused);
    void updateBufferingFromMpv(bool buffering);
    void updateSourceFrameRateFromMpv(double framesPerSecond);
    void updateLoadingFromMpv(bool loading);
    void updateStartFileFromMpv();
    void updatePlaybackRestartFromMpv();
    void updateEndFileFromMpv(bool ended);
    void updateErrorFromMpv(const QString &message);
    void updateVideoGeometryFromMpv(int width, int height);
    void renderPendingHardwareFrame(int generation);
    void hardwareStreamReady(int generation, int width, int height,
                             double framesPerSecond, const QString &codec);
    void hardwareDecodeFailed(int generation, const QString &reason);
    bool enableSourceFramePresentation(const char *reason);
    void resetVideoGeometry(const char *reason);

private:
    QSGNode *updatePaintNode(QSGNode *oldNode,
                             UpdatePaintNodeData *updatePaintNodeData) override;
    bool ensureMpv();
    void resizeSurface();
    void clearSurfaceConnections();
    void scheduleForegroundRestore();
    void withdrawPresentedFrame(const char *reason);
    void resetProgressAnchor();
    void syncProgressClock();
    void recordPresentedFrameForFloor();
    void resetFrameFloorWindow();
    void resetFrameFloorQualification();
    void updatePresentedTextureGeometry(const QSize &textureSize,
                                        const QSize &videoViewportSize);
    void reportFrameFloorSummary(const char *reason);
    void syncHardwareClock();
    void resetHardwareStallWatchdog();
    void restartHardwareDecodeAfterStall();
    void releaseInitialPositionGate(double confirmedPosition);
    void loadSourceInternal(const QString &sourceUrl, const QString &audioUrl,
                            double startPosition, bool pausedAfterLoad,
                            bool videoEnabled, bool liveStreamSource);
    bool startHardwareDecode(const QString &videoUrl, double startPosition);
    void drainDeferredHardwareBuffers(const char *reason);
    void stopHardwareDecode();
    void fallbackToSoftwareDecode(const QString &reason);
    static void sharedTextureRenderUpdate(void *context);

    MpvVideoBackend *m_backend;
    DroidVideoDecoder *m_hardwareDecoder;
    QPointer<QQuickItem> m_surfaceHost;
    QMetaObject::Connection m_widthConnection;
    QMetaObject::Connection m_heightConnection;
    QMetaObject::Connection m_destroyedConnection;
    QString m_sourceUrl;
    QString m_audioUrl;
    QString m_originalVideoUrl;
    QString m_originalAudioUrl;
    bool m_liveStreamSource;
    QAtomicInt m_sharedTextureRenderQueued;
    int m_sharedTextureFrameSerial;
    int m_presentedTextureWidth;
    int m_presentedTextureHeight;
    int m_presentedVideoWidth;
    int m_presentedVideoHeight;
    QElapsedTimer m_sharedTextureFrameTimer;
    QElapsedTimer m_coverSwapCadenceTimer;
    int m_lastCoverSwapFrameSerial;
    int m_coverSwapCadenceFrames;
    QElapsedTimer m_frameFloorWindowTimer;
    int m_frameFloorWindowFrames;
    int m_frameFloorWindowCount;
    int m_frameFloorBelowThresholdCount;
    double m_frameFloorMinimumFps;
    double m_sourceFrameRate;
    bool m_textureSharingLogged;
    bool m_fullResolutionPresentation;
    bool m_hardwareDecodeActive;
    bool m_hardwareFallbackForCurrentLoad;
    QTimer m_hardwarePresentationTimer;
    QTimer m_hardwareFirstFrameTimer;
    bool m_hardwareFirstFramePending;
    bool m_hardwarePresentationCadenceLogged;
    QTimer m_hardwareStallTimer;
    QElapsedTimer m_hardwareStallElapsed;
    QElapsedTimer m_hardwareSeekElapsed;
    int m_hardwareStallObservedSerial;
    double m_hardwareStallObservedPosition;
    int m_hardwareStallRecoveryCount;
    bool m_testHardwareStallEnabled;
    bool m_testHardwareStallInjected;
    int m_testHardwareStallGeneration;
    int m_testHardwareStallTargetCount;
    int m_testHardwareStallInjectedCount;
    int m_testHardwareStallNextFrameSerial;
    QTimer m_foregroundRestoreTimer;
    int m_foregroundRestoreStage;
    QTimer m_progressClockTimer;
    QElapsedTimer m_positionAnchorTimer;
    QElapsedTimer m_progressCadenceTimer;
    int m_progressClockTicks;
    int m_loadSerial;
    bool m_loadCommandPending;
    double m_pendingLoadStart;
    bool m_pendingLoadPause;
    bool m_initialPositionGatePending;
    bool m_initialPositionConfirmed;
    bool m_initialVideoFrameReady;
    bool m_requestedPaused;
    double m_requestedPosition;
    double m_requestedVolume;
    double m_requestedBrightness;
    double m_requestedSpeed;

    bool m_paused;
    bool m_loading;
    bool m_playing;
    bool m_ended;
    bool m_playbackStarted;
    bool m_sourceFileStartedForPresentation;
    bool m_pendingGeometryLogEmitted;
    bool m_dropVideoGeometryEventForTest;
    bool m_videoEnabled;
    bool m_seekPending;
    bool m_buffering;
    double m_position;
    double m_duration;
    double m_volume;
    double m_brightness;
    double m_speed;
    int m_videoWidth;
    int m_videoHeight;
    QString m_errorMessage;

    friend class MpvVideoMirrorItem;
};

class MpvVideoMirrorItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QObject *source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QString usage READ usage WRITE setUsage NOTIFY usageChanged)
    Q_PROPERTY(bool preserveAspectRatio READ preserveAspectRatio
               WRITE setPreserveAspectRatio NOTIFY preserveAspectRatioChanged)

public:
    explicit MpvVideoMirrorItem(QQuickItem *parent = 0);

    QObject *source() const { return m_source.data(); }
    void setSource(QObject *sourceObject);
    QString usage() const { return m_usage; }
    void setUsage(const QString &usage);
    bool preserveAspectRatio() const { return m_preserveAspectRatio; }
    void setPreserveAspectRatio(bool preserve);

signals:
    void sourceChanged();
    void usageChanged();
    void preserveAspectRatioChanged();

private:
    QSGNode *updatePaintNode(QSGNode *oldNode,
                             UpdatePaintNodeData *updatePaintNodeData) override;

    QPointer<MpvVideoItem> m_source;
    QMetaObject::Connection m_frameConnection;
    QMetaObject::Connection m_sourceDestroyedConnection;
    QString m_usage;
    bool m_textureSharingLogged;
    bool m_preserveAspectRatio;
    int m_lastLoggedFrameSerial;
    int m_lastPresentedFrameSerial;
    int m_lastPresentationLogSerial;
};
