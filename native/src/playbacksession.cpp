#include "playbacksession.h"

#include "accountservice.h"
#include "liveresolver.h"
#include "mpvvideoitem.h"
#include "playbackresolver.h"

#include <QByteArray>
#include <QDebug>
#include <QGuiApplication>
#include <QQuickItem>

namespace {
const int kDefaultSoftwareQuality = 80;
const int kMaximumApiQuality = 127;
const int kMaximumStablePhoneQuality = 116;
const int kMaximumStableLiveQuality = 400;

int normalizedSoftwareQuality(int requestedQuality) {
    return requestedQuality > 0
            ? qMin(requestedQuality, kMaximumApiQuality)
            : kDefaultSoftwareQuality;
}
}

PlaybackSession::PlaybackSession(PlaybackResolver *vodResolver,
                                 LiveResolver *liveResolver,
                                 AccountService *accountService, QObject *parent)
    : QObject(parent), m_vodResolver(vodResolver), m_liveResolver(liveResolver),
      m_accountService(accountService), m_active(false), m_mediaKind(NoMedia),
      m_pgc(false),
      m_backgroundPlayback(true), m_inAppMiniPlayerEnabled(true),
      m_resumeAfterForeground(false),
      m_firstFrameReady(true), m_preparingVideo(false),
      m_preparedVideoReady(false), m_finishedSmallWindowStopScheduled(false),
      m_nextVideoPartScheduled(false),
      m_dropFirstFrameEdgeForTest(
          qgetenv("SILISILI_NATIVE_TEST_DROP_FIRST_FRAME_EDGE") == QByteArrayLiteral("1")),
      m_surfaceTransition(false), m_initialResumePending(false),
      m_retainedVideoAspectRatio(0.0),
      m_loadedRevision(0), m_awaitedLoadSerial(0), m_preparedLoadSerial(0),
      m_pendingPosition(0.0), m_requestedResumePosition(0.0),
      m_pendingPaused(false), m_preparedQuality(0), m_loadedLiveRevision(0),
      m_lastHistoryProgress(-1) {
    connect(m_vodResolver, &PlaybackResolver::changed,
            this, &PlaybackSession::resolverChanged);
    connect(m_liveResolver, &LiveResolver::changed,
            this, &PlaybackSession::liveResolverChanged);
    connect(qApp, &QGuiApplication::applicationStateChanged,
            this, &PlaybackSession::applicationStateChanged);

    m_foregroundRefreshTimer.setSingleShot(true);
    m_foregroundRefreshTimer.setInterval(90);
    connect(&m_foregroundRefreshTimer, &QTimer::timeout,
            this, &PlaybackSession::refreshForegroundSurface);

    m_historyReportTimer.setInterval(15000);
    connect(&m_historyReportTimer, &QTimer::timeout, this, [this]() {
        reportPlaybackProgress("periodic-15s");
    });

    m_surfaceTransitionTimer.setSingleShot(true);
    m_surfaceTransitionTimer.setInterval(1400);
    connect(&m_surfaceTransitionTimer, &QTimer::timeout, this, [this]() {
        if (!m_surfaceTransition) return;
        m_surfaceTransition = false;
        if (!m_surfaceHost && !m_inAppMiniPlayerEnabled) {
            qWarning() << "native player: surface transition timed out"
                       << "fallbackCompact" << false
                       << "policy" << "disabled";
            stop();
            return;
        }
        if (!m_surfaceHost) useHost(m_fallbackHost.data());
        qWarning() << "native player: surface transition timed out"
                   << "fallbackCompact" << compact();
        emit surfaceChanged();
    });

    qInfo() << "native software video: single persistent mpv pipeline enabled"
            << "hardwareBackend" << false
            << "decoderSwitching" << false;
}

bool PlaybackSession::paused() const { return m_player ? m_player->paused() : true; }
QString PlaybackSession::mediaKind() const {
    switch (m_mediaKind) {
    case VideoOnDemand: return QStringLiteral("video");
    case PgcOnDemand: return QStringLiteral("pgc");
    case LiveStream: return QStringLiteral("live");
    case NoMedia: break;
    }
    return QStringLiteral("none");
}
bool PlaybackSession::loading() const {
    const bool awaitingFirstFrame = m_active && !m_firstFrameReady
            && !hasCurrentPresentedFrame()
            && errorMessage().isEmpty();
    return (live() ? (m_liveResolver && m_liveResolver->loading())
                   : (m_vodResolver && m_vodResolver->loading()))
            || (m_player && m_player->loading()) || awaitingFirstFrame;
}
bool PlaybackSession::playing() const {
    return m_active && m_player && m_player->playing()
            && !loading() && errorMessage().isEmpty();
}
bool PlaybackSession::ended() const { return m_player ? m_player->ended() : false; }
bool PlaybackSession::compact() const {
    return m_active && m_currentHost && m_currentHost == m_fallbackHost;
}
double PlaybackSession::position() const { return m_player ? m_player->position() : 0.0; }
double PlaybackSession::duration() const { return m_player ? m_player->duration() : 0.0; }
double PlaybackSession::volume() const { return m_player ? m_player->volume() : 100.0; }
double PlaybackSession::brightness() const { return m_player ? m_player->brightness() : 0.0; }
double PlaybackSession::speed() const { return m_player ? m_player->speed() : 1.0; }
int PlaybackSession::videoWidth() const { return m_player ? m_player->videoWidth() : 0; }
int PlaybackSession::videoHeight() const { return m_player ? m_player->videoHeight() : 0; }
double PlaybackSession::sourceFrameRate() const {
    return m_player ? m_player->sourceFrameRate() : 0.0;
}
int PlaybackSession::presentedTextureWidth() const {
    return m_player ? m_player->presentedTextureWidth() : 0;
}
int PlaybackSession::presentedTextureHeight() const {
    return m_player ? m_player->presentedTextureHeight() : 0;
}
int PlaybackSession::presentedVideoWidth() const {
    return m_player ? m_player->presentedVideoWidth() : 0;
}
int PlaybackSession::presentedVideoHeight() const {
    return m_player ? m_player->presentedVideoHeight() : 0;
}
double PlaybackSession::videoAspectRatio() const {
    const double currentAspect = videoHeight() > 0
            ? static_cast<double>(videoWidth()) / videoHeight() : 0.0;
    return currentAspect > 0.0 ? currentAspect : m_retainedVideoAspectRatio;
}
QString PlaybackSession::errorMessage() const {
    if (live()) {
        if (m_liveResolver && !m_liveResolver->errorMessage().isEmpty())
            return m_liveResolver->errorMessage();
        return m_player ? m_player->errorMessage() : QString();
    }
    if (m_vodResolver && !m_vodResolver->errorMessage().isEmpty())
        return m_vodResolver->errorMessage();
    return m_player ? m_player->errorMessage() : QString();
}
QVariantList PlaybackSession::qualities() const {
    if (live()) return m_liveResolver ? m_liveResolver->qualities() : QVariantList();
    return m_vodResolver ? m_vodResolver->qualities() : QVariantList();
}
int PlaybackSession::selectedQuality() const {
    if (live()) return m_liveResolver ? m_liveResolver->selectedQuality() : 0;
    return m_vodResolver ? m_vodResolver->selectedQuality() : 0;
}
QString PlaybackSession::selectedQualityLabel() const {
    if (live()) {
        QString label = m_liveResolver
                ? m_liveResolver->selectedQualityLabel() : QString();
        if (videoWidth() <= 0 || videoHeight() <= 0) return label;
        QString actual = QStringLiteral("%1×%2")
                .arg(videoWidth()).arg(videoHeight());
        if (sourceFrameRate() > 0.0) {
            const int roundedFps = qRound(sourceFrameRate());
            const QString fps = qAbs(sourceFrameRate() - roundedFps) < 0.05
                    ? QString::number(roundedFps)
                    : QString::number(sourceFrameRate(), 'f', 2);
            actual += QStringLiteral(" · %1fps").arg(fps);
        }
        const int sourceShortEdge = qMin(videoWidth(), videoHeight());
        const int sourceLongEdge = qMax(videoWidth(), videoHeight());
        const int presentedShortEdge = qMin(presentedVideoWidth(),
                                            presentedVideoHeight());
        const int presentedLongEdge = qMax(presentedVideoWidth(),
                                           presentedVideoHeight());
        if (presentedShortEdge > 0 && presentedLongEdge > 0
                && (presentedShortEdge < sourceShortEdge
                    || presentedLongEdge < sourceLongEdge)) {
            actual += QStringLiteral(" · 显示%1×%2")
                    .arg(presentedVideoWidth())
                    .arg(presentedVideoHeight());
        }
        return label.isEmpty() ? actual
                               : label + QStringLiteral(" · ") + actual;
    }
    return m_vodResolver ? m_vodResolver->selectedQualityLabel() : QString();
}

void PlaybackSession::attachPlayer(QObject *playerObject) {
    MpvVideoItem *player = qobject_cast<MpvVideoItem *>(playerObject);
    if (!player || m_player == player) return;
    if (m_player) {
        disconnect(m_player, &MpvVideoItem::stateChanged,
                   this, &PlaybackSession::playerChanged);
        disconnect(m_player, &MpvVideoItem::positionChanged,
                   this, &PlaybackSession::positionChanged);
        disconnect(m_player, &MpvVideoItem::firstFramePresented,
                   this, &PlaybackSession::firstFramePresented);
        disconnect(m_player, &MpvVideoItem::hardwareFirstFrameTimedOut,
                   this, &PlaybackSession::hardwareFirstFrameTimedOut);
        disconnect(m_player, &MpvVideoItem::unsafeLiveQualityRejected,
                   this, &PlaybackSession::unsafeLiveQualityRejected);
        disconnect(m_player, &MpvVideoItem::sharedTextureFrameChanged,
                   this, &PlaybackSession::sharedTextureFrameChanged);
        disconnect(m_player, &MpvVideoItem::presentationGeometryChanged,
                   this, &PlaybackSession::playerChanged);
    }
    m_player = player;
    connect(m_player, &MpvVideoItem::stateChanged, this, &PlaybackSession::playerChanged);
    connect(m_player, &MpvVideoItem::positionChanged,
            this, &PlaybackSession::positionChanged);
    connect(m_player, &MpvVideoItem::firstFramePresented,
            this, &PlaybackSession::firstFramePresented);
    connect(m_player, &MpvVideoItem::hardwareFirstFrameTimedOut,
            this, &PlaybackSession::hardwareFirstFrameTimedOut);
    connect(m_player, &MpvVideoItem::unsafeLiveQualityRejected,
            this, &PlaybackSession::unsafeLiveQualityRejected);
    connect(m_player, &MpvVideoItem::sharedTextureFrameChanged,
            this, &PlaybackSession::sharedTextureFrameChanged);
    connect(m_player, &MpvVideoItem::presentationGeometryChanged,
            this, &PlaybackSession::playerChanged);
    useHost(m_surfaceHost ? m_surfaceHost.data() : m_fallbackHost.data());
    emit surfaceChanged();
    emit changed();
    emit positionChanged();
}

void PlaybackSession::setFallbackHost(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host || m_fallbackHost == host) return;
    m_fallbackHost = host;
    if (!m_surfaceHost && !m_surfaceTransition) useHost(host);
    emit surfaceChanged();
}

void PlaybackSession::claimSurface(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host) return;
    if (m_surfaceHost == host && !m_surfaceTransition) return;
    const bool completedTransition = m_surfaceTransition;
    QQuickItem *previousHost = m_currentHost.data();
    m_surfaceTransition = false;
    m_surfaceTransitionTimer.stop();
    m_surfaceHost = host;
    useHost(host);
    if (completedTransition) {
        qInfo() << "native player: fullscreen surface handoff completed"
                << "from" << previousHost
                << "to" << host
                << "compactVisibleDuringHandoff" << false
                << "decoderReload" << false;
    }
    emit surfaceChanged();
}

void PlaybackSession::releaseSurface(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host || m_surfaceHost != host) return;
    if (qApp && qApp->applicationState() != Qt::ApplicationActive) return;
    if (m_surfaceTransition) {
        // The outgoing page may become inactive before PlayerPage finishes
        // construction. Keep the live texture on that still-valid host until
        // the full-screen host claims it; never expose the compact fallback in
        // the middle of an intentional full-screen transition.
        m_surfaceHost.clear();
        qInfo() << "native player: outgoing surface retained for fullscreen handoff"
                << "compactVisibleDuringHandoff" << false;
        emit surfaceChanged();
        return;
    }
    if (!m_inAppMiniPlayerEnabled) {
        qInfo() << "native compact player: page exit stopped playback"
                << "policy" << "disabled"
                << "mediaKind" << mediaKind();
        m_surfaceHost.clear();
        stop();
        return;
    }
    // PageStack status changes are synchronous. Reparent the same persistent
    // texture to the rotation-stable compact layer in this call so a busy QML
    // event loop cannot leave a 1-3 frame hole during a page transition.
    const int frameBefore = m_player ? m_player->presentedFrameSerial() : 0;
    m_surfaceHost.clear();
    useHost(m_fallbackHost.data());
    const int frameAfter = m_player ? m_player->presentedFrameSerial() : 0;
    qInfo() << "native compact player: seamless surface handoff completed"
            << "elapsedMs" << 0
            << "frameBefore" << frameBefore
            << "frameAfter" << frameAfter
            << "textureRetained" << (frameBefore > 0 && frameAfter >= frameBefore)
            << "decoderReload" << false
            << "hiddenDelayMs" << 0;
    emit surfaceChanged();
    dismissFinishedSmallWindowPlayback();
}

void PlaybackSession::beginSurfaceTransition(QObject *hostObject) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!m_active || !host || m_currentHost != host) return;
    m_surfaceTransition = true;
    m_surfaceTransitionTimer.start();
    qInfo() << "native player: fullscreen surface handoff started"
            << "host" << host
            << "compactVisibleDuringHandoff" << false;
    emit surfaceChanged();
}

void PlaybackSession::setSurfaceHighResolution(QObject *hostObject, bool enabled) {
    QQuickItem *host = qobject_cast<QQuickItem *>(hostObject);
    if (!host || !m_player || m_currentHost != host) return;
    m_player->setFullResolutionPresentation(enabled);
}

void PlaybackSession::prepareVideo(const QString &bvid, const QString &cid, int quality) {
    if (m_active || !m_player || !m_vodResolver || bvid.isEmpty() || cid.isEmpty()) return;
    // Visible-card preparation is a foreground latency optimization.  A Home
    // model refresh can recreate delegate zero while a detail page remains in
    // the Cover; decoding that new row into the persistent player leaks its
    // first frame into the stopped detail lifecycle when the app is restored.
    if (qApp && qApp->applicationState() != Qt::ApplicationActive) {
        qInfo() << "native software video: visible-card prepare skipped in background"
                << bvid << cid;
        return;
    }
    const int requestedQuality = normalizedSoftwareQuality(quality);
    if ((m_preparingVideo || m_preparedVideoReady)
            && m_preparedBvid == bvid && m_preparedCid == cid
            && m_preparedQuality == requestedQuality) {
        if (m_preparedVideoReady)
            emit videoPrepared(bvid, cid, requestedQuality, true);
        return;
    }

    m_preparingVideo = true;
    m_preparedVideoReady = false;
    m_preparedBvid = bvid;
    m_preparedCid = cid;
    m_preparedQuality = requestedQuality;
    m_preparedLoadSerial = 0;
    m_pendingPosition = 0.0;
    m_pendingPaused = true;
    // Start one bounded metadata request for the first visible card, then join
    // it from resolve(). The same persistent mpv instance opens the media
    // paused and hidden; no second decoder or background audio is created.
    m_vodResolver->prefetchVideo(bvid, cid, requestedQuality);
    m_vodResolver->resolve(bvid, cid, requestedQuality);
    qInfo() << "native software video: first visible card prepare requested"
            << bvid << cid << "quality" << requestedQuality;
}

void PlaybackSession::playVideo(const QString &bvid, const QString &cid,
                                const QString &title, const QString &cover, int quality) {
    playVideoInternal(bvid, cid, title, cover, 0.0, false, quality);
}

void PlaybackSession::playVideoAt(const QString &bvid, const QString &cid,
                                  const QString &title, const QString &cover,
                                  double startPosition, int quality) {
    playVideoInternal(bvid, cid, title, cover, startPosition, true, quality);
}

void PlaybackSession::playVideoInternal(const QString &bvid, const QString &cid,
                                        const QString &title, const QString &cover,
                                        double startPosition, bool resumeRequested,
                                        int quality) {
    if (bvid.isEmpty() || cid.isEmpty() || !m_vodResolver) return;
    leaveLiveSourceForOnDemand("video");
    const double requestedStartPosition = qMax(0.0, startPosition);
    const int requestedQuality = normalizedSoftwareQuality(quality);
    const bool wasActive = m_active;
    const bool sameVideo = m_active && !m_pgc && m_bvid == bvid && m_cid == cid;
    const bool sameVideoFamily = m_active && !m_pgc && m_bvid == bvid;
    if (m_active && !sameVideo) reportPlaybackProgress("video-switch", true);
    if (!sameVideoFamily) m_retainedVideoAspectRatio = 0.0;
    const bool preparedVideo = !resumeRequested && !m_active
            && (m_preparingVideo || m_preparedVideoReady)
            && m_preparedBvid == bvid && m_preparedCid == cid
            && m_preparedQuality == requestedQuality;
    const bool preparedFrameReady = preparedVideo && m_preparedVideoReady;
    m_title = title;
    m_cover = cover;
    m_aid = m_videoAidBvid == bvid ? m_videoAid : QString();
    m_bvid = bvid;
    m_cid = cid;
    m_epId.clear();
    m_pgc = false;
    m_mediaKind = VideoOnDemand;
    m_active = true;
    if (!m_historyReportTimer.isActive()) m_historyReportTimer.start();
    if (!wasActive) emit surfaceChanged();
    if (m_player) m_player->setVisible(m_currentHost);
    if (sameVideo) {
        if (resumeRequested) {
            qInfo() << "native history resume: active session retained"
                    << "kind" << "video" << "bvid" << bvid << "cid" << cid
                    << "requested" << requestedStartPosition
                    << "actual" << position();
        }
        m_initialResumePending = false;
        emit changed();
        return;
    }
    m_firstFrameReady = false;
    m_initialResumePending = resumeRequested;
    m_requestedResumePosition = requestedStartPosition;
    if (resumeRequested) {
        qInfo() << "native history resume: start accepted"
                << "kind" << "video" << "bvid" << bvid << "cid" << cid
                << "position" << requestedStartPosition
                << "directMediaLoad" << true << "postStartSeek" << false;
    }
    m_startupElapsed.restart();
    if (preparedVideo) {
        m_preparingVideo = false;
        m_preparedVideoReady = false;
        m_pendingPosition = 0.0;
        m_pendingPaused = false;
        m_awaitedLoadSerial = m_preparedLoadSerial > 0
                ? m_preparedLoadSerial : (m_player ? m_player->loadSerial() : 0);
        if (m_player) {
            m_player->setVisible(m_currentHost);
            m_player->setPaused(false);
            m_player->refreshVideoOutput();
        }
        if (preparedFrameReady) {
            m_firstFrameReady = true;
            qInfo() << "native software video: first frame ready"
                    << "loadSerial" << -1
                    << "position" << position()
                    << "requestElapsedMs" << m_startupElapsed.elapsed()
                    << "loadingCoverWithdrawn" << true
                    << "preparedBeforeTap" << true;
            reportPlaybackProgress("prepared-first-frame", true);
        } else {
            qInfo() << "native software video: tap joined in-flight first-card prepare"
                    << bvid << cid;
        }
        reconcileFirstFrameReady("prepared-activation-level-check");
        emit changed();
        emit surfaceChanged();
        return;
    }
    m_preparingVideo = false;
    m_preparedVideoReady = false;
    m_preparedBvid.clear();
    m_preparedCid.clear();
    m_preparedQuality = 0;
    m_preparedLoadSerial = 0;
    m_awaitedLoadSerial = m_player ? m_player->loadSerial() + 1 : 0;
    if (m_player) m_player->beginSourceTransition();
    m_pendingPosition = requestedStartPosition;
    m_pendingPaused = false;
    m_vodResolver->resolve(bvid, cid, requestedQuality);
    emit changed();
}

void PlaybackSession::playPgc(const QString &aid, const QString &bvid,
                              const QString &cid, const QString &epId,
                              const QString &title, const QString &cover, int quality) {
    playPgcInternal(aid, bvid, cid, epId, title, cover, 0.0, false, quality);
}

void PlaybackSession::playPgcAt(const QString &aid, const QString &bvid,
                                const QString &cid, const QString &epId,
                                const QString &title, const QString &cover,
                                double startPosition, int quality) {
    playPgcInternal(aid, bvid, cid, epId, title, cover,
                    startPosition, true, quality);
}

void PlaybackSession::playPgcInternal(const QString &aid, const QString &bvid,
                                      const QString &cid, const QString &epId,
                                      const QString &title, const QString &cover,
                                      double startPosition, bool resumeRequested,
                                      int quality) {
    if (cid.isEmpty() || (aid.isEmpty() && bvid.isEmpty()) || !m_vodResolver) return;
    leaveLiveSourceForOnDemand("pgc");
    const double requestedStartPosition = qMax(0.0, startPosition);
    const int requestedQuality = normalizedSoftwareQuality(quality);
    const bool wasActive = m_active;
    const bool sameVideo = m_active && m_pgc && m_cid == cid && m_epId == epId;
    const bool sameProgram = m_active && m_pgc && m_aid == aid;
    if (m_active && !sameVideo) reportPlaybackProgress("episode-switch", true);
    if (!sameProgram) m_retainedVideoAspectRatio = 0.0;
    m_title = title;
    m_cover = cover;
    m_aid = aid;
    m_bvid = bvid;
    m_cid = cid;
    m_epId = epId;
    m_pgc = true;
    m_mediaKind = PgcOnDemand;
    m_active = true;
    if (!m_historyReportTimer.isActive()) m_historyReportTimer.start();
    if (!wasActive) emit surfaceChanged();
    if (m_player) m_player->setVisible(m_currentHost);
    if (sameVideo) {
        if (resumeRequested) {
            qInfo() << "native history resume: active session retained"
                    << "kind" << "pgc" << "episodeId" << epId << "cid" << cid
                    << "requested" << requestedStartPosition
                    << "actual" << position();
        }
        m_initialResumePending = false;
        emit changed();
        return;
    }
    m_firstFrameReady = false;
    m_initialResumePending = resumeRequested;
    m_requestedResumePosition = requestedStartPosition;
    if (resumeRequested) {
        qInfo() << "native history resume: start accepted"
                << "kind" << "pgc" << "episodeId" << epId << "cid" << cid
                << "position" << requestedStartPosition
                << "directMediaLoad" << true << "postStartSeek" << false;
    }
    m_startupElapsed.restart();
    m_awaitedLoadSerial = m_player ? m_player->loadSerial() + 1 : 0;
    if (m_player) m_player->beginSourceTransition();
    m_pendingPosition = requestedStartPosition;
    m_pendingPaused = false;
    m_vodResolver->resolvePgc(aid, bvid, cid, epId, requestedQuality);
    emit changed();
}

void PlaybackSession::requestQuality(int quality) {
    if (!m_active) return;
    if (live()) {
        if (!m_liveResolver || m_liveRoomId.isEmpty()) return;
        const int requestedQuality = quality > 0 ? quality : 0;
        m_pendingPaused = paused();
        qInfo() << "native live: quality switch requested"
                << "from" << selectedQuality()
                << "to" << requestedQuality
                << "catalogChoices" << qualities().size()
                << "nonSeekable" << true
                << "presentationAspectRetained" << videoAspectRatio();
        m_liveResolver->resolve(m_liveRoomId, requestedQuality);
        return;
    }
    if (!m_vodResolver || m_bvid.isEmpty() || m_cid.isEmpty()) return;
    const int requestedQuality = normalizedSoftwareQuality(quality);
    qInfo() << "native player: quality switch requested"
            << "from" << selectedQuality()
            << "to" << requestedQuality
            << "catalogChoices" << qualities().size()
            << "positionRetained" << position()
            << "presentationAspectRetained" << videoAspectRatio();
    m_firstFrameReady = false;
    m_startupElapsed.restart();
    m_awaitedLoadSerial = m_player ? m_player->loadSerial() + 1 : 0;
    m_pendingPosition = position();
    m_pendingPaused = paused();
    if (m_pgc)
        m_vodResolver->resolvePgc(m_aid, m_bvid, m_cid, m_epId, requestedQuality);
    else
        m_vodResolver->resolve(m_bvid, m_cid, requestedQuality);
}

void PlaybackSession::playLive(const QString &roomId, const QString &title,
                               const QString &cover, int quality) {
    if (roomId.isEmpty() || !m_player || !m_liveResolver) return;

    // A live room participates in the same presentation session as VOD, but
    // its URL still belongs to LiveResolver. Clear any prepared/active VOD
    // before exposing the live session so stale resolver data can never load
    // into the process-lifetime player after this point.
    stop();
    m_mediaKind = LiveStream;
    m_active = true;
    m_pgc = false;
    m_liveRoomId = roomId;
    m_title = title.isEmpty() ? tr("直播间") : title;
    m_cover = cover;
    m_aid.clear();
    m_bvid.clear();
    m_cid.clear();
    m_epId.clear();
    m_firstFrameReady = true;
    m_awaitedLoadSerial = 0;
    m_pendingPaused = false;
    if (m_player) {
        // Speed belongs to seekable on-demand transport. A live room must not
        // inherit 1.25x/2x from the VOD session that was just closed.
        m_player->setSpeed(1.0);
        m_player->setVisible(m_currentHost);
    }
    qInfo() << "native playback session: live activated"
            << "roomId" << roomId
            << "singleDecoder" << true
            << "coverAndPipEligible" << true;
    m_liveResolver->resolve(roomId, quality);
    emit changed();
    emit surfaceChanged();
}

void PlaybackSession::leaveLiveSourceForOnDemand(const char *nextKind) {
    if (!live()) return;
    const QString previousRoomId = m_liveRoomId;
    if (m_liveResolver) m_liveResolver->cancel();
    m_liveRoomId.clear();
    if (m_player) m_player->setSpeed(1.0);
    qInfo() << "native playback session: live source left for on-demand"
            << "roomId" << previousRoomId
            << "nextKind" << nextKind
            << "liveRequestCancelled" << true
            << "speedReset" << true
            << "surfaceRetained" << true;
}

void PlaybackSession::setPaused(bool pausedValue) {
    qInfo() << "native transport: pause requested"
            << pausedValue
            << "loading" << loading()
            << "pendingIntent" << (!m_firstFrameReady);
    if (pausedValue) reportPlaybackProgress("pause", true);
    // A quality/source request can still be resolving when the user presses
    // pause. Preserve that intent for the incoming load instead of applying it
    // only to the outgoing source.
    if (m_active && !m_firstFrameReady) m_pendingPaused = pausedValue;
    if (m_active && m_player) m_player->setPaused(pausedValue);
}
void PlaybackSession::togglePaused() {
    if (m_active) setPaused(!paused());
}
void PlaybackSession::seek(double nextPosition) {
    if (!m_active || !m_player) return;
    if (live()) {
        qInfo() << "native live transport: seek ignored" << "nonSeekable" << true;
        return;
    }
    if (nextPosition < 0.0) nextPosition = 0.0;
    if (duration() > 0.0 && nextPosition > duration()) nextPosition = duration();
    qInfo() << "native transport: direct software seek"
            << "target" << nextPosition
            << "decoderSwitch" << false;
    if (!m_firstFrameReady) m_pendingPosition = nextPosition;
    m_player->seek(nextPosition);
}
void PlaybackSession::setVolume(double volumeValue) {
    if (m_player && m_active) m_player->setVolume(volumeValue);
}
void PlaybackSession::setBrightness(double brightnessValue) {
    if (m_player && m_active) m_player->setBrightness(brightnessValue);
}
void PlaybackSession::setSpeed(double speedValue) {
    if (!m_active || !m_player) return;
    if (live()) return;
    m_player->setSpeed(qBound(0.25, speedValue, 4.0));
}

void PlaybackSession::setVideoParts(const QString &bvid, const QVariantList &parts) {
    if (bvid.isEmpty() || parts.isEmpty()) return;
    m_videoPartsBvid = bvid;
    m_videoParts = parts;
    qInfo() << "native multipart: playlist synchronized"
            << "bvid" << bvid << "parts" << parts.size();
    // A very short first part can reach EOF while the parallel page-list
    // request is still completing. Reconsider it as soon as the list arrives.
    if (m_active && !m_pgc && m_bvid == bvid && ended()) {
        if (!scheduleNextVideoPart()) dismissFinishedSmallWindowPlayback();
    }
}

void PlaybackSession::setVideoAid(const QString &bvid, const QString &aid) {
    if (bvid.isEmpty() || aid.isEmpty()) return;
    m_videoAidBvid = bvid;
    m_videoAid = aid;
    if (m_active && !m_pgc && m_bvid == bvid) {
        m_aid = aid;
        if (m_firstFrameReady) reportPlaybackProgress("metadata-ready", true);
    }
}

void PlaybackSession::stop() {
    // Clear the public session state first. mpv's stop command resets ended(),
    // and its synchronous stateChanged signal must not make an ended compact
    // window visible again for one empty frame before active becomes false.
    const bool wasActive = m_active;
    const bool wasLive = live();
    if (wasActive) reportPlaybackProgress("stop", true);
    m_active = false;
    m_mediaKind = NoMedia;
    m_retainedVideoAspectRatio = 0.0;
    m_firstFrameReady = true;
    m_finishedSmallWindowStopScheduled = false;
    m_surfaceTransition = false;
    m_surfaceTransitionTimer.stop();
    if (wasActive) {
        emit surfaceChanged();
        emit changed();
    }
    if (m_player) {
        m_player->setVisible(false);
        m_player->stop();
    }
    m_foregroundRefreshTimer.stop();
    m_historyReportTimer.stop();
    if (wasLive && m_liveResolver) m_liveResolver->cancel();
    m_surfaceHost.clear();
    useHost(0);
    m_preparingVideo = false;
    m_preparedVideoReady = false;
    m_preparedBvid.clear();
    m_preparedCid.clear();
    m_preparedQuality = 0;
    m_preparedLoadSerial = 0;
    m_awaitedLoadSerial = 0;
    m_nextVideoPartScheduled = false;
    m_resumeAfterForeground = false;
    m_initialResumePending = false;
    m_requestedResumePosition = 0.0;
    m_liveRoomId.clear();
    if (!wasActive) emit changed();
}

void PlaybackSession::dismissCompactSurface() {
    if (!compact() || !m_player) return;
    qInfo() << "native compact player: surface dismissed"
            << "active" << m_active
            << "mediaKind" << mediaKind()
            << "paused" << paused()
            << "playing" << playing();
    m_surfaceHost.clear();
    useHost(0);
    emit surfaceChanged();
    emit changed();
}

void PlaybackSession::setBackgroundPlayback(bool enabled) {
    if (m_backgroundPlayback == enabled) return;
    m_backgroundPlayback = enabled;
    emit changed();
}

void PlaybackSession::setInAppMiniPlayerEnabled(bool enabled) {
    if (m_inAppMiniPlayerEnabled == enabled) return;
    m_inAppMiniPlayerEnabled = enabled;
    qInfo() << "native compact player: page-exit policy changed" << enabled;
    emit changed();
    if (!enabled && compact() && qApp
            && qApp->applicationState() == Qt::ApplicationActive) {
        stop();
    }
}

void PlaybackSession::resolverChanged() {
    if (live()) return;
    if (!m_active && m_preparingVideo && m_player
            && m_vodResolver->revision() != m_loadedRevision
            && !m_vodResolver->sourceUrl().isEmpty()) {
        m_player->setVisible(false);
        m_player->loadSourceWithAudio(m_vodResolver->sourceUrl(), m_vodResolver->audioUrl(),
                                      0.0, true, true);
        m_preparedLoadSerial = m_player->loadSerial();
        m_loadedRevision = m_vodResolver->revision();
        qInfo() << "native software video: hidden paused first-card media prepare started"
                << m_preparedBvid << m_preparedCid
                << "quality" << m_preparedQuality;
    } else if (!m_active && m_preparingVideo && !m_vodResolver->loading()
               && !m_vodResolver->errorMessage().isEmpty()) {
        const QString failedBvid = m_preparedBvid;
        const QString failedCid = m_preparedCid;
        const int failedQuality = m_preparedQuality;
        m_preparingVideo = false;
        m_preparedVideoReady = false;
        emit videoPrepared(failedBvid, failedCid, failedQuality, false);
    }
    if (m_active && m_player && m_vodResolver->revision() != m_loadedRevision
            && !m_vodResolver->sourceUrl().isEmpty()) {
        m_player->setVisible(m_currentHost && m_active);
        m_player->loadSourceWithAudio(m_vodResolver->sourceUrl(), m_vodResolver->audioUrl(),
                                      m_pendingPosition, m_pendingPaused, true);
        m_awaitedLoadSerial = m_player->loadSerial();
        m_loadedRevision = m_vodResolver->revision();
        qInfo() << "native software video: direct start requested"
                << "start" << m_pendingPosition
                << "pausedAfterLoad" << m_pendingPaused
                << "decoderSwitch" << false;
    }
    emit changed();
}

void PlaybackSession::liveResolverChanged() {
    if (!m_active || !live() || !m_liveResolver || !m_player) return;
    if (m_liveResolver->revision() != m_loadedLiveRevision
            && !m_liveResolver->sourceUrl().isEmpty()) {
        m_firstFrameReady = false;
        m_startupElapsed.restart();
        m_awaitedLoadSerial = m_player->loadSerial() + 1;
        m_pendingPosition = 0.0;
        m_player->beginSourceTransition();
        m_player->setVisible(m_currentHost && m_active);
        m_player->loadSource(m_liveResolver->sourceUrl(), 0.0, m_pendingPaused);
        m_loadedLiveRevision = m_liveResolver->revision();
        qInfo() << "native playback session: live source loaded"
                << "roomId" << m_liveRoomId
                << "quality" << m_liveResolver->selectedQuality()
                << "loadSerial" << m_player->loadSerial()
                << "nonSeekable" << true
                << "surfaceRetained" << true;
        emit surfaceChanged();
    }
    emit changed();
}

void PlaybackSession::playerChanged() {
    const double currentAspect = m_player ? m_player->videoAspectRatio() : 0.0;
    if (currentAspect > 0.0
            && qAbs(currentAspect - m_retainedVideoAspectRatio) > 0.0001) {
        m_retainedVideoAspectRatio = currentAspect;
        qInfo() << "native player: session presentation aspect retained"
                << m_retainedVideoAspectRatio
                << "mediaKind" << mediaKind()
                << "survivesQualityTransition" << true;
    }
    reconcileFirstFrameReady("player-state-level-check");
    if (ended()) reportPlaybackProgress("completed", true);
    if (scheduleNextVideoPart()) {
        emit changed();
        return;
    }
    emit changed();
    dismissFinishedSmallWindowPlayback();
}

void PlaybackSession::dismissFinishedSmallWindowPlayback() {
    const bool applicationBackgrounded = qApp
            && qApp->applicationState() != Qt::ApplicationActive;
    if (!m_active || !ended() || m_nextVideoPartScheduled
            || (!compact() && !applicationBackgrounded)
            || m_finishedSmallWindowStopScheduled)
        return;
    m_finishedSmallWindowStopScheduled = true;
    qInfo() << "native compact player: playback completed; auto-dismiss scheduled"
            << "inAppCompact" << compact()
            << "systemPiP" << applicationBackgrounded;
    QTimer::singleShot(0, this, [this]() {
        m_finishedSmallWindowStopScheduled = false;
        const bool applicationBackgrounded = qApp
                && qApp->applicationState() != Qt::ApplicationActive;
        if (!m_active || !ended() || m_nextVideoPartScheduled
                || (!compact() && !applicationBackgrounded))
            return;
        qInfo() << "native compact player: playback completed; auto-dismissed"
                << "sessionCleared" << true;
        stop();
    });
}

void PlaybackSession::firstFramePresented(int loadSerial, double framePosition) {
    if (!m_active && m_preparingVideo) {
        if (m_preparedLoadSerial > 0 && loadSerial != m_preparedLoadSerial) return;
        m_preparingVideo = false;
        m_preparedVideoReady = true;
        qInfo() << "native software video: first visible card prepared"
                << m_preparedBvid << m_preparedCid
                << "quality" << m_preparedQuality
                << "loadSerial" << loadSerial
                << "position" << framePosition;
        emit videoPrepared(m_preparedBvid, m_preparedCid, m_preparedQuality, true);
        return;
    }
    // A hardware first-frame failure restarts the same source internally in
    // software and advances MpvVideoItem's serial once. Reject genuinely stale
    // frames, but adopt a newer serial belonging to that current source so the
    // loading latch cannot wait forever on the retired hardware serial.
    if (!m_active || m_firstFrameReady
            || (m_awaitedLoadSerial > 0 && loadSerial < m_awaitedLoadSerial))
        return;
    if (m_awaitedLoadSerial > 0 && loadSerial > m_awaitedLoadSerial) {
        qInfo() << "native player: internal fallback load serial adopted"
                << "previous" << m_awaitedLoadSerial
                << "current" << loadSerial
                << "sameSession" << true;
        m_awaitedLoadSerial = loadSerial;
    }
    if (m_dropFirstFrameEdgeForTest) {
        m_dropFirstFrameEdgeForTest = false;
        qInfo() << "native software video: first-frame edge intentionally dropped for regression"
                << "loadSerial" << loadSerial;
        return;
    }
    m_firstFrameReady = true;
    confirmInitialResume(framePosition, "first-frame");
    const qint64 requestElapsedMs = m_startupElapsed.isValid()
            ? m_startupElapsed.elapsed() : -1;
    qInfo() << "native software video: first frame ready"
            << "loadSerial" << loadSerial
            << "position" << framePosition
            << "requestElapsedMs" << requestElapsedMs
            << "loadingCoverWithdrawn" << true;
    reportPlaybackProgress("first-frame", true);
    emit changed();
    emit surfaceChanged();
}

void PlaybackSession::hardwareFirstFrameTimedOut(int loadSerial, int width,
                                                 int height,
                                                 double framesPerSecond) {
    if (!m_active || !m_player
            || (m_awaitedLoadSerial > 0 && loadSerial != m_awaitedLoadSerial))
        return;
    if (live()) {
        requestSafeLiveQualityFallback(QStringLiteral(
                    "original-first-frame-timeout-%1x%2-%3fps")
                .arg(width).arg(height).arg(framesPerSecond, 0, 'f', 2));
        return;
    }
    if (!m_vodResolver) return;
    const int failedQuality = selectedQuality();
    if (failedQuality <= kMaximumStablePhoneQuality) return;
    const double retainedPosition = position();
    const bool retainedPaused = paused();
    qWarning() << "native player: UHD first-frame timeout recovery"
               << "failedQuality" << failedQuality
               << "geometry" << width << "x" << height
               << "sourceFps" << framesPerSecond
               << "retryQuality" << kMaximumStablePhoneQuality
               << "position" << retainedPosition
               << "sameSession" << true;
    if (!retainedPaused) m_player->setPaused(true);
    m_player->beginSourceTransition();
    m_firstFrameReady = false;
    m_pendingPosition = retainedPosition;
    m_pendingPaused = retainedPaused;
    m_awaitedLoadSerial = m_player->loadSerial() + 1;
    m_vodResolver->setOperationalMaximumQuality(
                kMaximumStablePhoneQuality,
                QStringLiteral("uhd-first-frame-timeout"));
    if (m_pgc)
        m_vodResolver->resolvePgc(m_aid, m_bvid, m_cid, m_epId,
                               failedQuality);
    else
        m_vodResolver->resolve(m_bvid, m_cid, failedQuality);
    emit changed();
}

void PlaybackSession::unsafeLiveQualityRejected(int loadSerial,
                                                const QString &reason) {
    if (!m_active || !live() || !m_player
            || (m_awaitedLoadSerial > 0 && loadSerial != m_awaitedLoadSerial))
        return;
    requestSafeLiveQualityFallback(reason);
}

bool PlaybackSession::requestSafeLiveQualityFallback(const QString &reason) {
    if (!m_active || !live() || !m_liveResolver || !m_player
            || m_liveRoomId.isEmpty()
            || selectedQuality() <= 0
            || selectedQuality() <= kMaximumStableLiveQuality)
        return false;
    const int failedQuality = selectedQuality();
    m_pendingPaused = paused();
    m_firstFrameReady = false;
    m_startupElapsed.restart();
    m_player->beginSourceTransition();
    m_awaitedLoadSerial = m_player->loadSerial() + 1;
    qWarning() << "native live quality: safe fallback requested"
               << "from" << failedQuality
               << "to" << kMaximumStableLiveQuality
               << "reason" << reason
               << "sameSession" << true
               << "unsafeSoftwareDecode" << false;
    m_liveResolver->resolve(m_liveRoomId, kMaximumStableLiveQuality);
    emit changed();
    emit surfaceChanged();
    return true;
}

void PlaybackSession::sharedTextureFrameChanged(int frameSerial) {
    if (frameSerial <= 0 || !m_active || m_firstFrameReady) return;
    reconcileFirstFrameReady("shared-texture-level-signal");
}

bool PlaybackSession::hasCurrentPresentedFrame() const {
    if (!m_player || m_player->presentedFrameSerial() <= 0) return false;
    return m_awaitedLoadSerial <= 0
            || m_player->presentedLoadSerial() >= m_awaitedLoadSerial;
}

bool PlaybackSession::reconcileFirstFrameReady(const char *reason) {
    if (!m_active || m_firstFrameReady || !hasCurrentPresentedFrame()
            || !errorMessage().isEmpty())
        return false;
    if (m_awaitedLoadSerial > 0
            && m_player->presentedLoadSerial() > m_awaitedLoadSerial) {
        qInfo() << "native player: internal fallback load serial reconciled"
                << "previous" << m_awaitedLoadSerial
                << "current" << m_player->presentedLoadSerial()
                << "sameSession" << true;
        m_awaitedLoadSerial = m_player->presentedLoadSerial();
    }
    m_firstFrameReady = true;
    confirmInitialResume(position(), reason);
    const qint64 requestElapsedMs = m_startupElapsed.isValid()
            ? m_startupElapsed.elapsed() : -1;
    qInfo() << "native software video: first-frame latch reconciled"
            << "reason" << reason
            << "loadSerial" << m_player->presentedLoadSerial()
            << "frameSerial" << m_player->presentedFrameSerial()
            << "position" << position()
            << "requestElapsedMs" << requestElapsedMs
            << "loadingCoverWithdrawn" << true;
    reportPlaybackProgress("first-frame-reconciled", true);
    emit changed();
    emit surfaceChanged();
    return true;
}

void PlaybackSession::confirmInitialResume(double actualPosition, const char *evidence) {
    if (!m_initialResumePending) return;
    const double tolerance = 2.5;
    const bool accepted = actualPosition + tolerance >= m_requestedResumePosition;
    qInfo() << "native history resume: first frame confirmed"
            << "requested" << m_requestedResumePosition
            << "actual" << actualPosition
            << "tolerance" << tolerance
            << "accepted" << accepted
            << "evidence" << evidence;
    m_initialResumePending = false;
}

bool PlaybackSession::scheduleNextVideoPart() {
    if (!m_active || live() || m_pgc || !ended() || m_nextVideoPartScheduled
            || m_videoPartsBvid != m_bvid || m_videoParts.isEmpty())
        return false;

    int currentIndex = -1;
    for (int index = 0; index < m_videoParts.size(); ++index) {
        if (m_videoParts.at(index).toMap().value(QStringLiteral("cid")).toString() == m_cid) {
            currentIndex = index;
            break;
        }
    }
    if (currentIndex < 0 || currentIndex + 1 >= m_videoParts.size()) return false;

    const QVariantMap nextPart = m_videoParts.at(currentIndex + 1).toMap();
    const QString nextCid = nextPart.value(QStringLiteral("cid")).toString();
    const QString nextTitle = nextPart.value(QStringLiteral("title")).toString();
    if (nextCid.isEmpty() || nextCid == m_cid) return false;

    const QString expectedBvid = m_bvid;
    const QString completedCid = m_cid;
    const QString nextDisplayTitle = nextTitle.isEmpty() ? m_title : nextTitle;
    const QString currentCover = m_cover;
    const int quality = selectedQuality() > 0 ? selectedQuality() : kDefaultSoftwareQuality;
    m_nextVideoPartScheduled = true;
    qInfo() << "native multipart: next part scheduled"
            << "bvid" << expectedBvid
            << "fromCid" << completedCid
            << "toCid" << nextCid
            << "nextIndex" << currentIndex + 2
            << "parts" << m_videoParts.size()
            << "surfaceRetained" << true;
    QTimer::singleShot(0, this, [this, expectedBvid, completedCid, nextCid,
                       nextDisplayTitle, currentCover, quality]() {
        if (!m_nextVideoPartScheduled) return;
        m_nextVideoPartScheduled = false;
        if (!m_active || m_pgc || m_bvid != expectedBvid || m_cid != completedCid
                || !ended())
            return;
        qInfo() << "native multipart: next part started"
                << "bvid" << expectedBvid
                << "fromCid" << completedCid
                << "toCid" << nextCid
                << "decoderReload" << false
                << "surfaceRetained" << true;
        playVideo(expectedBvid, nextCid, nextDisplayTitle, currentCover, quality);
    });
    return true;
}

bool PlaybackSession::reportPlaybackProgress(const char *reason, bool force) {
    if (!m_active || live() || !m_player || !m_accountService || m_aid.isEmpty()
            || m_cid.isEmpty())
        return false;
    if (!force && !playing()) return false;
    const int currentProgress = qMax(0, qRound(position()));
    const int currentDuration = qMax(0, qRound(duration()));
    const bool sameIdentity = m_lastHistoryBvid == m_bvid
            && m_lastHistoryCid == m_cid;
    if (!force && sameIdentity && m_lastHistoryProgress >= 0
            && currentProgress < m_lastHistoryProgress + 14)
        return false;
    if (force && sameIdentity && m_lastHistoryProgress == currentProgress
            && QByteArray(reason) != QByteArrayLiteral("completed"))
        return false;
    const bool requested = m_accountService->reportPlaybackHistory(
        m_aid, m_bvid, m_cid, m_epId, m_pgc,
        currentProgress, currentDuration, QString::fromLatin1(reason));
    if (!requested) return false;
    m_lastHistoryBvid = m_bvid;
    m_lastHistoryCid = m_cid;
    m_lastHistoryProgress = currentProgress;
    return true;
}

void PlaybackSession::applicationStateChanged(Qt::ApplicationState state) {
    if (state != Qt::ApplicationActive) {
        reportPlaybackProgress("background", true);
        m_foregroundRefreshTimer.stop();
    }
    if (state == Qt::ApplicationActive && m_active && m_player) {
        qInfo() << "native software video: foreground without reload or seek"
                << "position" << position()
                << "paused" << paused();
        refreshForegroundSurface();
    }
    dismissFinishedSmallWindowPlayback();
    if (m_backgroundPlayback || !m_active || !m_player) return;
    if (state != Qt::ApplicationActive) {
        if (m_player->playing()) {
            m_resumeAfterForeground = true;
            setPaused(true);
        }
    } else if (m_resumeAfterForeground) {
        m_resumeAfterForeground = false;
        setPaused(false);
    }
}

void PlaybackSession::useHost(QQuickItem *host) {
    QQuickItem *previousHost = m_currentHost.data();
    const bool parentReady = !m_player || m_player->parentItem() == host;
    if (m_currentHost == host && parentReady) {
        resizePlayer();
        if (m_player && host) m_player->refreshVideoOutput();
        return;
    }

    QObject::disconnect(m_widthConnection);
    QObject::disconnect(m_heightConnection);
    QObject::disconnect(m_destroyedConnection);
    m_currentHost = host;
    if (!m_player) return;
    if (!host) {
        if (previousHost) m_player->releaseSurface(previousHost);
        return;
    }

    // A newly claimed host starts from the bounded transition-safe profile.
    // PlayerPage promotes only its own still-current host after orientation and
    // PageStack geometry have remained stable for a short interval.
    m_player->setFullResolutionPresentation(false);
    m_player->claimSurface(host);
    m_player->setVisible(m_active);
    resizePlayer();
    m_widthConnection = connect(host, &QQuickItem::widthChanged,
                                this, &PlaybackSession::resizePlayer);
    m_heightConnection = connect(host, &QQuickItem::heightChanged,
                                 this, &PlaybackSession::resizePlayer);
    m_destroyedConnection = connect(host, &QObject::destroyed, this, [this, host]() {
        if (m_surfaceHost == host) m_surfaceHost.clear();
        if (m_fallbackHost == host) m_fallbackHost.clear();
        useHost(m_surfaceHost ? m_surfaceHost.data() : m_fallbackHost.data());
        emit surfaceChanged();
    });
    if (m_active) m_player->refreshVideoOutput();
}

void PlaybackSession::resizePlayer() {
    if (!m_player || !m_currentHost) return;
    m_player->setPosition(QPointF(0, 0));
    m_player->setSize(QSizeF(m_currentHost->width(), m_currentHost->height()));
}

void PlaybackSession::refreshForegroundSurface() {
    if (!m_active || !m_player) return;
    QQuickItem *host = m_surfaceHost ? m_surfaceHost.data() : m_fallbackHost.data();
    if (host) useHost(host);
    if (!m_currentHost) return;
    m_player->setVisible(true);
    resizePlayer();
    qInfo() << "native player: foreground surface refresh"
            << "host" << m_currentHost->width() << "x" << m_currentHost->height()
            << "position" << position()
            << "paused" << paused();
    m_player->refreshVideoOutput();
    emit surfaceChanged();
    emit changed();
}
