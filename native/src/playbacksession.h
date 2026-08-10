#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QMetaObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

class MpvVideoItem;
class PlaybackResolver;
class LiveResolver;
class AccountService;
class QQuickItem;

class PlaybackSession : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(bool live READ live NOTIFY changed)
    Q_PROPERTY(QString mediaKind READ mediaKind NOTIFY changed)
    Q_PROPERTY(bool paused READ paused NOTIFY changed)
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(bool ended READ ended NOTIFY changed)
    Q_PROPERTY(bool compact READ compact NOTIFY surfaceChanged)
    Q_PROPERTY(bool surfaceTransition READ surfaceTransition NOTIFY surfaceChanged)
    Q_PROPERTY(bool backgroundPlayback READ backgroundPlayback WRITE setBackgroundPlayback NOTIFY changed)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY changed)
    Q_PROPERTY(double volume READ volume NOTIFY changed)
    Q_PROPERTY(double brightness READ brightness NOTIFY changed)
    Q_PROPERTY(double speed READ speed NOTIFY changed)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY changed)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY changed)
    Q_PROPERTY(double videoAspectRatio READ videoAspectRatio NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString cover READ cover NOTIFY changed)
    Q_PROPERTY(QString bvid READ bvid NOTIFY changed)
    Q_PROPERTY(QString cid READ cid NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
    Q_PROPERTY(QVariantList qualities READ qualities NOTIFY changed)
    Q_PROPERTY(int selectedQuality READ selectedQuality NOTIFY changed)
    Q_PROPERTY(QString selectedQualityLabel READ selectedQualityLabel NOTIFY changed)

public:
    enum MediaKind {
        NoMedia,
        VideoOnDemand,
        PgcOnDemand,
        LiveStream
    };
    Q_ENUMS(MediaKind)

    explicit PlaybackSession(PlaybackResolver *vodResolver,
                             LiveResolver *liveResolver,
                             AccountService *accountService,
                             QObject *parent = 0);

    bool active() const { return m_active; }
    bool live() const { return m_mediaKind == LiveStream; }
    QString mediaKind() const;
    bool paused() const;
    bool loading() const;
    bool playing() const;
    bool ended() const;
    bool compact() const;
    bool surfaceTransition() const { return m_surfaceTransition; }
    bool backgroundPlayback() const { return m_backgroundPlayback; }
    double position() const;
    double duration() const;
    double volume() const;
    double brightness() const;
    double speed() const;
    int videoWidth() const;
    int videoHeight() const;
    double videoAspectRatio() const;
    QString title() const { return m_title; }
    QString cover() const { return m_cover; }
    QString bvid() const { return m_bvid; }
    QString cid() const { return m_cid; }
    QString errorMessage() const;
    QVariantList qualities() const;
    int selectedQuality() const;
    QString selectedQualityLabel() const;

public slots:
    void attachPlayer(QObject *playerObject);
    void setFallbackHost(QObject *hostObject);
    void claimSurface(QObject *hostObject);
    void releaseSurface(QObject *hostObject);
    void beginSurfaceTransition(QObject *hostObject);
    void setSurfaceHighResolution(QObject *hostObject, bool enabled);
    void prepareVideo(const QString &bvid, const QString &cid, int quality = 80);
    void playVideo(const QString &bvid, const QString &cid, const QString &title,
                   const QString &cover = QString(), int quality = 80);
    void playVideoAt(const QString &bvid, const QString &cid, const QString &title,
                     const QString &cover, double startPosition, int quality = 80);
    void playPgc(const QString &aid, const QString &bvid, const QString &cid,
                 const QString &epId, const QString &title,
                 const QString &cover = QString(), int quality = 80);
    void playPgcAt(const QString &aid, const QString &bvid, const QString &cid,
                   const QString &epId, const QString &title,
                   const QString &cover, double startPosition, int quality = 80);
    void playLive(const QString &roomId, const QString &title,
                  const QString &cover, int quality = 250);
    void setVideoParts(const QString &bvid, const QVariantList &parts);
    void setVideoAid(const QString &bvid, const QString &aid);
    void requestQuality(int quality);
    void setPaused(bool paused);
    void togglePaused();
    void seek(double position);
    void setVolume(double volume);
    void setBrightness(double brightness);
    void setSpeed(double speed);
    void stop();
    void setBackgroundPlayback(bool enabled);

signals:
    void changed();
    void positionChanged();
    void surfaceChanged();
    void videoPrepared(const QString &bvid, const QString &cid, int quality,
                       bool ready);

private slots:
    void resolverChanged();
    void liveResolverChanged();
    void playerChanged();
    void firstFramePresented(int loadSerial, double position);
    void hardwareFirstFrameTimedOut(int loadSerial, int width, int height,
                                    double framesPerSecond);
    void sharedTextureFrameChanged(int frameSerial);
    void applicationStateChanged(Qt::ApplicationState state);

private:
    void useHost(QQuickItem *host);
    void resizePlayer();
    void refreshForegroundSurface();
    void dismissFinishedSmallWindowPlayback();
    bool hasCurrentPresentedFrame() const;
    bool reconcileFirstFrameReady(const char *reason);
    void confirmInitialResume(double actualPosition, const char *evidence);
    void playVideoInternal(const QString &bvid, const QString &cid,
                           const QString &title, const QString &cover,
                           double startPosition, bool resumeRequested, int quality);
    void playPgcInternal(const QString &aid, const QString &bvid,
                         const QString &cid, const QString &epId,
                         const QString &title, const QString &cover,
                         double startPosition, bool resumeRequested, int quality);
    void leaveLiveSourceForOnDemand(const char *nextKind);
    bool scheduleNextVideoPart();
    bool reportPlaybackProgress(const char *reason, bool force = false);

    PlaybackResolver *m_vodResolver;
    LiveResolver *m_liveResolver;
    AccountService *m_accountService;
    QPointer<MpvVideoItem> m_player;
    QPointer<QQuickItem> m_fallbackHost;
    QPointer<QQuickItem> m_surfaceHost;
    QPointer<QQuickItem> m_currentHost;
    QTimer m_foregroundRefreshTimer;
    QTimer m_surfaceTransitionTimer;
    QTimer m_historyReportTimer;
    QMetaObject::Connection m_widthConnection;
    QMetaObject::Connection m_heightConnection;
    QMetaObject::Connection m_destroyedConnection;
    bool m_active;
    MediaKind m_mediaKind;
    bool m_pgc;
    bool m_backgroundPlayback;
    bool m_resumeAfterForeground;
    bool m_firstFrameReady;
    bool m_preparingVideo;
    bool m_preparedVideoReady;
    bool m_finishedSmallWindowStopScheduled;
    bool m_nextVideoPartScheduled;
    bool m_dropFirstFrameEdgeForTest;
    bool m_surfaceTransition;
    bool m_initialResumePending;
    QElapsedTimer m_startupElapsed;
    int m_loadedRevision;
    int m_awaitedLoadSerial;
    int m_preparedLoadSerial;
    double m_pendingPosition;
    double m_requestedResumePosition;
    bool m_pendingPaused;
    int m_preparedQuality;
    QVariantList m_videoParts;
    QString m_videoPartsBvid;
    QString m_videoAidBvid;
    QString m_videoAid;
    QString m_liveRoomId;
    int m_loadedLiveRevision;
    QString m_lastHistoryBvid;
    QString m_lastHistoryCid;
    int m_lastHistoryProgress;
    QString m_preparedBvid, m_preparedCid;
    QString m_title, m_cover, m_aid, m_bvid, m_cid, m_epId;
};
