#include "systempipcontroller.h"

#include "mpvvideoitem.h"
#include "playbacksession.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDebug>
#include <QDynamicPropertyChangeEvent>
#include <QGuiApplication>
#include <QLibrary>
#include <QPlatformSurfaceEvent>
#include <QProcess>
#include <QQmlContext>
#include <QQuickView>
#include <QScreen>
#include <QSettings>
#include <QSurfaceFormat>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>
#include <sailfishapp.h>

namespace {
const char kMceService[] = "com.nokia.mce";
const char kMceRequestPath[] = "/com/nokia/mce/request";
const char kMceRequestInterface[] = "com.nokia.mce.request";
const char kMceSignalPath[] = "/com/nokia/mce/signal";
const char kMceSignalInterface[] = "com.nokia.mce.signal";
const char kLipstickService[] = "org.nemomobile.lipstick";
const char kLipstickPath[] = "/";
const char kLipstickInterface[] = "org.nemomobile.compositor";
const char kBackgroundModeKey[] = "playback/backgroundPresentationMode";
const char kPipXRatioKey[] = "playback/systemPipXRatio";
const char kPipYRatioKey[] = "playback/systemPipYRatio";
const char kDesktopFile[] = "/usr/share/applications/cn.silisili.native.desktop";

int normalizedOrientation(int angle) {
    switch (angle) {
    case -90:
    case 0:
    case 90:
    case 180:
        return angle;
    case -180:
        return 180;
    case 270:
        return -90;
    default:
        return 0;
    }
}

struct WaylandClientApi {
    typedef void *(*MarshalFlags)(void *, quint32, const void *, quint32,
                                  quint32, ...);
    typedef quint32 (*ProxyGetVersion)(void *);

    QLibrary library;
    MarshalFlags marshalFlags;
    ProxyGetVersion proxyGetVersion;
    const void *regionInterface;

    WaylandClientApi()
        : library(QStringLiteral("libwayland-client.so.0")),
          marshalFlags(0), proxyGetVersion(0), regionInterface(0) {
        if (!library.load()) return;
        marshalFlags = reinterpret_cast<MarshalFlags>(
                    library.resolve("wl_proxy_marshal_flags"));
        proxyGetVersion = reinterpret_cast<ProxyGetVersion>(
                    library.resolve("wl_proxy_get_version"));
        regionInterface = reinterpret_cast<const void *>(
                    library.resolve("wl_region_interface"));
    }

    bool ready() const {
        return marshalFlags && proxyGetVersion && regionInterface;
    }
};

void setWaylandRegion(QWindow *window, const QRegion &region, bool input) {
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native || !window || !window->handle()) return;
    void *compositor = native->nativeResourceForIntegration("compositor");
    void *surface = native->nativeResourceForWindow("surface", window);
    static WaylandClientApi api;
    if (!compositor || !surface || !api.ready()) return;

    const quint32 compositorCreateRegion = 1;
    const quint32 regionDestroy = 0;
    const quint32 regionAdd = 1;
    const quint32 surfaceSetOpaqueRegion = 4;
    const quint32 surfaceSetInputRegion = 5;
    const quint32 surfaceCommit = 6;
    const quint32 marshalFlagDestroy = 1;
    void *waylandRegion = api.marshalFlags(
                compositor, compositorCreateRegion, api.regionInterface,
                api.proxyGetVersion(compositor), 0, static_cast<void *>(0));
    if (!waylandRegion) return;
    for (const QRect &rect : region.rects()) {
        api.marshalFlags(waylandRegion, regionAdd, 0,
                         api.proxyGetVersion(waylandRegion), 0,
                         rect.x(), rect.y(), rect.width(), rect.height());
    }
    api.marshalFlags(surface,
                     input ? surfaceSetInputRegion : surfaceSetOpaqueRegion,
                     0, api.proxyGetVersion(surface), 0, waylandRegion);
    api.marshalFlags(waylandRegion, regionDestroy, 0,
                     api.proxyGetVersion(waylandRegion), marshalFlagDestroy);
    api.marshalFlags(surface, surfaceCommit, 0,
                     api.proxyGetVersion(surface), 0);
}
}

SystemPipController::SystemPipController(QQuickView *mainView,
                                         PlaybackSession *session,
                                         MpvVideoItem *videoItem,
                                         QObject *parent)
    : QObject(parent), m_mainView(mainView), m_view(0), m_session(session),
      m_videoItem(videoItem), m_swapFrames(0), m_remapAttempts(0),
      m_orientationAngle(0), m_forcedTestOrientation(-1000),
      m_available(false), m_deviceUnlocked(false), m_displayOn(false),
      m_applicationForeground(true), m_foregroundProbePending(false),
      m_restoreInProgress(false),
      m_backgroundPlaybackMode(
          QSettings().value(QString::fromLatin1(kBackgroundModeKey),
                            QStringLiteral("cover")).toString()) {
    if (!mainView || !session || !videoItem) {
        qWarning() << "native system PiP: unavailable due to missing application objects";
        return;
    }

    if (m_backgroundPlaybackMode != QStringLiteral("pip"))
        m_backgroundPlaybackMode = QStringLiteral("cover");

    bool forcedOrientationReady = false;
    const int forcedOrientation = qEnvironmentVariableIntValue(
                "SILISILI_NATIVE_TEST_PIP_ORIENTATION", &forcedOrientationReady);
    if (forcedOrientationReady)
        m_forcedTestOrientation = normalizedOrientation(forcedOrientation);

    m_view = SailfishApp::createView();
    m_view->setTitle(QStringLiteral("SiliSili PiP"));
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_view->setColor(QColor(0, 0, 0, 0));
    m_view->setClearBeforeRendering(true);
    m_view->setPersistentSceneGraph(true);
    m_view->setPersistentOpenGLContext(true);
    QSurfaceFormat format = m_view->format();
    format.setAlphaBufferSize(8);
    format.setSwapInterval(0);
    m_view->setFormat(format);
    m_view->setFlags(Qt::Tool | Qt::FramelessWindowHint
                     | Qt::WindowStaysOnTopHint
                     | Qt::WindowDoesNotAcceptFocus);
    m_view->setTransientParent(0);
    m_view->installEventFilter(this);
    m_view->rootContext()->setContextProperty(QStringLiteral("systemPipController"),
                                              this);
    m_view->rootContext()->setContextProperty(QStringLiteral("playbackVideo"),
                                              videoItem);
    m_view->rootContext()->setContextProperty(QStringLiteral("playbackSession"),
                                              session);
    updateOverlayGeometry();
    m_view->setSource(QUrl(QStringLiteral("qrc:/qml/SystemPipWindow.qml")));
    if (m_view->status() == QQuickView::Error) {
        for (const QQmlError &error : m_view->errors())
            qWarning() << "native system PiP: overlay QML error" << error;
    }
    m_view->create();
    configureLipstickSurface();
    m_view->hide();

    connect(qApp, &QGuiApplication::applicationStateChanged,
            this, &SystemPipController::applicationStateChanged);
    connect(mainView, &QWindow::activeChanged, this, [this]() {
        if (m_mainView && m_mainView->isActive()) {
            m_applicationForeground = true;
            updateVisibility();
        } else {
            probeForegroundState();
        }
    });
    connect(session, &PlaybackSession::changed,
            this, &SystemPipController::updateVisibility);
    connect(session, &PlaybackSession::surfaceChanged,
            this, &SystemPipController::updateVisibility);
    if (QGuiApplication::primaryScreen()) {
        connect(QGuiApplication::primaryScreen(), &QScreen::geometryChanged,
                this, [this](const QRect &) { updateOverlayGeometry(); });
    }
    connect(m_view, &QQuickWindow::frameSwapped,
            this, &SystemPipController::overlayFrameSwapped,
            Qt::QueuedConnection);
    connect(m_view, &QWindow::visibilityChanged, this,
            [this](QWindow::Visibility visibility) {
        if (visibility != QWindow::Hidden || !m_session || !qApp) return;
        const bool shouldRemap = !m_restoreInProgress
                && !m_applicationForeground
                && m_backgroundPlaybackMode == QStringLiteral("pip")
                && m_available && m_deviceUnlocked && m_displayOn
                && m_session->active() && !m_session->ended();
        if (!shouldRemap || m_remapAttempts >= 3) return;
        ++m_remapAttempts;
        m_visibilityDelayTimer.start(140);
        qInfo() << "native system PiP: compositor transition hid overlay; remap scheduled"
                << "attempt" << m_remapAttempts;
    });

    m_visibilityDelayTimer.setSingleShot(true);
    connect(&m_visibilityDelayTimer, &QTimer::timeout,
            this, &SystemPipController::updateVisibility);

    m_foregroundProbeTimer.setInterval(220);
    connect(&m_foregroundProbeTimer, &QTimer::timeout,
            this, &SystemPipController::probeForegroundState);
    m_foregroundProbeTimer.start();
    QTimer::singleShot(0, this, SLOT(probeForegroundState()));

    // lca-tool activation is asynchronous. Keep the overlay suppressed while
    // Lipstick moves the existing task back to the foreground, otherwise the
    // hidden-surface remap guard can briefly show PiP again in that gap.
    m_restoreGuardTimer.setSingleShot(true);
    m_restoreGuardTimer.setInterval(1400);
    connect(&m_restoreGuardTimer, &QTimer::timeout, this, [this]() {
        if (!m_restoreInProgress) return;
        m_restoreInProgress = false;
        qInfo() << "native system PiP: foreground restore guard expired; state reprobe";
        probeForegroundState();
    });

    QDBusConnection systemBus = QDBusConnection::systemBus();
    systemBus.connect(QString::fromLatin1(kMceService),
                      QString::fromLatin1(kMceSignalPath),
                      QString::fromLatin1(kMceSignalInterface),
                      QStringLiteral("tklock_mode_ind"),
                      this, SLOT(tklockModeChanged(QString)));
    systemBus.connect(QString::fromLatin1(kMceService),
                      QString::fromLatin1(kMceSignalPath),
                      QString::fromLatin1(kMceSignalInterface),
                      QStringLiteral("display_status_ind"),
                      this, SLOT(displayStatusChanged(QString)));
    refreshDeviceState();

    m_swapSampleTimer.setInterval(100);
    connect(&m_swapSampleTimer, &QTimer::timeout,
            this, &SystemPipController::sampleFrameSwaps);
    m_swapSampleTimer.start();

    m_presentationTimer.setInterval(16);
    connect(&m_presentationTimer, &QTimer::timeout,
            this, &SystemPipController::requestPresentationFrame);

    qInfo() << "native system PiP: full-screen transparent notification overlay initialized"
            << "available" << m_available
            << "mode" << m_backgroundPlaybackMode
            << "category" << "notification"
            << "singleDecoder" << true
            << "mirrorOnly" << true
            << "qmlSharedTexturePresentation" << true
            << "movableInputRegion" << true
            << "orientationSensor" << true
            << "forcedTestOrientation" << m_forcedTestOrientation
            << "visualModel" << "unused";
}

SystemPipController::~SystemPipController() {
    delete m_view;
    m_view = 0;
}

bool SystemPipController::visible() const {
    return m_view && m_view->isVisible();
}

bool SystemPipController::eventFilter(QObject *watched, QEvent *event) {
    if (watched != m_view || !event) return QObject::eventFilter(watched, event);
    if (event->type() == QEvent::PlatformSurface) {
        QPlatformSurfaceEvent *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        if (surfaceEvent->surfaceEventType()
                == QPlatformSurfaceEvent::SurfaceCreated) {
            configureLipstickSurface();
        }
    } else if (event->type() == QEvent::DynamicPropertyChange) {
        QDynamicPropertyChangeEvent *propertyEvent =
                static_cast<QDynamicPropertyChangeEvent *>(event);
        if (propertyEvent->propertyName() == QByteArrayLiteral("MOUSE_REGION"))
            applyInputRegion();
    }
    return QObject::eventFilter(watched, event);
}

void SystemPipController::configureLipstickSurface() {
    if (!m_view || !m_view->handle()) return;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native) return;

    native->setWindowProperty(m_view->handle(), QStringLiteral("CATEGORY"),
                              QStringLiteral("notification"));
    setWaylandRegion(m_view, QRegion(), false);
    applyInputRegion();
    if (!m_available) {
        m_available = true;
        emit availabilityChanged();
    }
    qInfo() << "native system PiP: Lipstick surface configured"
            << "category" << "notification"
            << "surface" << m_view->width() << "x" << m_view->height()
            << "opaqueRegionEmpty" << true
            << "inputRegionRects" << m_inputRegion.rectCount()
            << "privilegedSessionRequired" << true;
}

void SystemPipController::applyInputRegion() {
    if (!m_view || !m_view->handle()) return;
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    if (!native) return;
    native->setWindowProperty(m_view->handle(), QStringLiteral("MOUSE_REGION"),
                              QVariant::fromValue(m_inputRegion));
    setWaylandRegion(m_view, m_inputRegion, true);
}

void SystemPipController::setInputRect(qreal x, qreal y,
                                       qreal width, qreal height) {
    if (!m_view) return;
    QRect bounds(QPoint(0, 0), m_view->size());
    QRect input(qRound(x), qRound(y), qRound(width), qRound(height));
    input = input.adjusted(-2, -2, 2, 2).intersected(bounds);
    if (input.isEmpty()) return;
    const QRegion nextRegion(input);
    if (nextRegion == m_inputRegion) return;
    m_inputRegion = nextRegion;
    m_view->setMask(m_inputRegion);
    m_view->setProperty("MOUSE_REGION", QVariant::fromValue(m_inputRegion));
    applyInputRegion();
    qInfo() << "native system PiP: input region updated"
            << input.x() << input.y() << input.width() << input.height()
            << "orientation" << m_orientationAngle;
}

void SystemPipController::commitOverlayPosition(qreal x, qreal y,
                                                qreal width, qreal height) {
    if (!m_view) return;
    const QRect bounds(QPoint(0, 0), m_view->size());
    const int boxWidth = qMax(1, qRound(width));
    const int boxHeight = qMax(1, qRound(height));
    const int nextX = qBound(0, qRound(x), qMax(0, bounds.width() - boxWidth));
    const int nextY = qBound(0, qRound(y), qMax(0, bounds.height() - boxHeight));
    m_overlayRect = QRect(nextX, nextY, boxWidth, boxHeight);
    saveWindowPosition();
    emit overlayGeometryChanged();
    setInputRect(nextX, nextY, boxWidth, boxHeight);
    qInfo() << "native system PiP: drag completed"
            << "geometry" << m_overlayRect
            << "orientation" << m_orientationAngle
            << "persisted" << true;
}

void SystemPipController::setSensorOrientation(int angle) {
    const int sensorAngle = normalizedOrientation(angle);
    const int nextAngle = m_forcedTestOrientation != -1000
            ? m_forcedTestOrientation : sensorAngle;
    if (m_orientationAngle == nextAngle) {
        setInputRect(m_overlayRect.x(), m_overlayRect.y(),
                     m_overlayRect.width(), m_overlayRect.height());
        return;
    }
    m_orientationAngle = nextAngle;
    emit orientationAngleChanged();
    updateOverlayGeometry();
    qInfo() << "native system PiP: orientation applied"
            << "sensor" << sensorAngle
            << "effective" << m_orientationAngle
            << "bounds" << m_overlayRect;
}

void SystemPipController::setBackgroundPlaybackMode(const QString &mode) {
    const QString normalized = mode.trimmed().toLower();
    if (normalized != QStringLiteral("cover")
            && normalized != QStringLiteral("pip")) {
        qWarning() << "native background presentation: rejected mode" << mode;
        return;
    }
    if (m_backgroundPlaybackMode == normalized) return;
    m_backgroundPlaybackMode = normalized;
    QSettings().setValue(QString::fromLatin1(kBackgroundModeKey), normalized);
    emit backgroundPlaybackModeChanged();
    qInfo() << "native background presentation: mode changed"
            << normalized
            << "coverVideoEnabled" << (normalized == QStringLiteral("cover"))
            << "systemPipEnabled" << (normalized == QStringLiteral("pip"));
    updateVisibility();
}

void SystemPipController::restoreApplication() {
    m_restoreInProgress = true;
    m_applicationForeground = true;
    m_visibilityDelayTimer.stop();
    m_backgroundTransitionElapsed.invalidate();
    m_remapAttempts = 0;
    m_restoreGuardTimer.start();
    if (m_view) {
        m_presentationTimer.stop();
        m_view->hide();
        emit visibilityChanged();
    }
    if (m_mainView) {
        m_mainView->raise();
        m_mainView->requestActivate();
    }
    const bool launcherActivation = QProcess::startDetached(
                QStringLiteral("/usr/bin/lca-tool"),
                QStringList() << QStringLiteral("--triggerdesktop")
                              << QString::fromLatin1(kDesktopFile));
    qInfo() << "native system PiP: foreground restore requested"
            << "raise" << true
            << "launcherActivation" << launcherActivation
            << "desktop" << kDesktopFile;
}

void SystemPipController::applicationStateChanged(Qt::ApplicationState state) {
    if (state != Qt::ApplicationActive) {
        m_applicationForeground = false;
        m_backgroundTransitionElapsed.restart();
        m_remapAttempts = 0;
        refreshDeviceState();
    } else {
        probeForegroundState();
    }
    QTimer::singleShot(0, this, SLOT(updateVisibility()));
}

void SystemPipController::probeForegroundState() {
    if (m_foregroundProbePending) return;
    QDBusInterface lipstick(QString::fromLatin1(kLipstickService),
                            QString::fromLatin1(kLipstickPath),
                            QString::fromLatin1(kLipstickInterface),
                            QDBusConnection::sessionBus());
    if (!lipstick.isValid()) {
        const bool foreground = qApp
                && qApp->applicationState() == Qt::ApplicationActive;
        if (m_applicationForeground != foreground) {
            m_applicationForeground = foreground;
            updateVisibility();
        }
        return;
    }

    m_foregroundProbePending = true;
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
                lipstick.asyncCall(QStringLiteral("privateTopmostWindowProcessId")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *completed) {
        m_foregroundProbePending = false;
        QDBusPendingReply<int> reply = *completed;
        completed->deleteLater();
        if (reply.isError()) return;
        const int topPid = reply.value();
        bool foreground = topPid == QCoreApplication::applicationPid();
        if (foreground && m_view && m_view->isVisible()
                && (!m_mainView || !m_mainView->isActive())) {
            foreground = false;
        }
        if (m_restoreInProgress) {
            if (!foreground) {
                qInfo() << "native system PiP: foreground restore guard suppresses remap"
                        << "topPid" << topPid
                        << "appPid" << QCoreApplication::applicationPid();
                return;
            }
            m_restoreInProgress = false;
            m_restoreGuardTimer.stop();
            qInfo() << "native system PiP: foreground restore guard completed"
                    << "topPid" << topPid;
        }
        if (m_applicationForeground == foreground) return;

        m_applicationForeground = foreground;
        if (foreground) {
            m_visibilityDelayTimer.stop();
            m_backgroundTransitionElapsed.invalidate();
        } else {
            m_backgroundTransitionElapsed.restart();
            m_remapAttempts = 0;
            refreshDeviceState();
        }
        qInfo() << "native system PiP: Lipstick foreground state"
                << "foreground" << foreground
                << "topPid" << topPid
                << "appPid" << QCoreApplication::applicationPid();
        updateVisibility();
    });
}

void SystemPipController::tklockModeChanged(const QString &mode) {
    m_deviceUnlocked = mode == QStringLiteral("unlocked");
    qInfo() << "native system PiP: lock state" << mode;
    updateVisibility();
}

void SystemPipController::displayStatusChanged(const QString &status) {
    m_displayOn = status == QStringLiteral("on");
    qInfo() << "native system PiP: display state" << status;
    updateVisibility();
}

void SystemPipController::refreshDeviceState() {
    QDBusInterface mce(QString::fromLatin1(kMceService),
                       QString::fromLatin1(kMceRequestPath),
                       QString::fromLatin1(kMceRequestInterface),
                       QDBusConnection::systemBus());
    const QDBusReply<QString> lockReply = mce.call(QStringLiteral("get_tklock_mode"));
    const QDBusReply<QString> displayReply = mce.call(QStringLiteral("get_display_status"));
    m_deviceUnlocked = lockReply.isValid()
            && lockReply.value() == QStringLiteral("unlocked");
    m_displayOn = displayReply.isValid()
            && displayReply.value() == QStringLiteral("on");
    if (!lockReply.isValid() || !displayReply.isValid())
        qWarning() << "native system PiP: MCE privacy state unavailable; overlay disabled";
}

void SystemPipController::updateVisibility() {
    if (!m_view || !m_session) return;
    const bool backgrounded = !m_applicationForeground;
    if (m_backgroundPlaybackMode == QStringLiteral("pip")
            && !m_restoreInProgress
            && backgrounded && m_backgroundTransitionElapsed.isValid()
            && m_backgroundTransitionElapsed.elapsed() < 360) {
        const int remaining = 360
                - static_cast<int>(m_backgroundTransitionElapsed.elapsed());
        if (!m_visibilityDelayTimer.isActive()
                || m_visibilityDelayTimer.remainingTime() > remaining)
            m_visibilityDelayTimer.start(qMax(1, remaining));
        return;
    }
    const bool shouldShow = m_backgroundPlaybackMode == QStringLiteral("pip")
            && !m_restoreInProgress && m_available && backgrounded
            && m_deviceUnlocked && m_displayOn
            && m_session->active() && !m_session->ended();
    if (shouldShow && !m_view->isVisible()) {
        updateOverlayGeometry();
        m_swapFrames = 0;
        m_swapWindow.invalidate();
        m_view->show();
        m_view->raise();
        applyInputRegion();
        m_view->update();
        m_presentationTimer.start();
        emit visibilityChanged();
        qInfo() << "native system PiP: shown over system interface"
                << "category" << "notification"
                << "fullScreenTransparentCanvas" << true
                << "surface" << m_view->width() << "x" << m_view->height()
                << "content" << m_overlayRect
                << "singleDecoder" << true
                << "mode" << m_backgroundPlaybackMode
                << "mediaKind" << m_session->mediaKind()
                << "position" << m_session->position();
    } else if (!shouldShow && m_view->isVisible()) {
        m_presentationTimer.stop();
        m_view->hide();
        emit visibilityChanged();
        qInfo() << "native system PiP: hidden"
                << "mode" << m_backgroundPlaybackMode
                << "foreground" << !backgrounded
                << "locked" << !m_deviceUnlocked
                << "displayOn" << m_displayOn
                << "active" << m_session->active()
                << "ended" << m_session->ended();
        m_swapFrames = 0;
        m_swapWindow.invalidate();
    } else if (!shouldShow) {
        m_presentationTimer.stop();
    }
}

QSize SystemPipController::orientedBoundsSize() const {
    if (qAbs(m_orientationAngle) == 90)
        return QSize(m_contentSize.height(), m_contentSize.width());
    return m_contentSize;
}

void SystemPipController::updateOverlayGeometry() {
    if (!m_view || !QGuiApplication::primaryScreen()) return;
    const QRect screen = QGuiApplication::primaryScreen()->geometry();
    if (screen.width() < 2 || screen.height() < 2) return;
    if (m_view->geometry() != screen)
        m_view->setGeometry(screen);

    const int shortEdge = qMin(screen.width(), screen.height());
    const qreal deviceScale = qMax(0.5, shortEdge / 1080.0);
    const int margin = qMax(12, qRound(36 * deviceScale));
    const int bottomClearance = qMax(margin, qRound(160 * deviceScale));
    const qreal sourceAspect = m_session && m_session->videoAspectRatio() > 0.0
            ? m_session->videoAspectRatio() : 16.0 / 9.0;
    const qreal aspect = qMax(16.0 / 9.0, sourceAspect);
    const int preferredWidth = qRound(shortEdge * 0.65);
    const int contentWidth = qMax(240, qMin(screen.width() - 2 * margin,
                                            preferredWidth));
    const int contentHeight = qMax(135, qRound(contentWidth / aspect));
    const QSize nextContentSize(contentWidth, contentHeight);
    const bool contentSizeChanged = nextContentSize != m_contentSize;
    m_contentSize = nextContentSize;
    const QSize boundsSize = orientedBoundsSize();

    QSettings settings;
    bool xRatioReady = false;
    bool yRatioReady = false;
    const qreal xRatio = settings.value(QString::fromLatin1(kPipXRatioKey))
            .toDouble(&xRatioReady);
    const qreal yRatio = settings.value(QString::fromLatin1(kPipYRatioKey))
            .toDouble(&yRatioReady);
    int x = qMax(margin, screen.width() - boundsSize.width() - margin);
    int y = qMax(margin, screen.height() - boundsSize.height() - bottomClearance);
    if (xRatioReady && yRatioReady) {
        const int usableWidth = qMax(0, screen.width() - boundsSize.width());
        const int usableHeight = qMax(0, screen.height() - boundsSize.height());
        x = qRound(qBound(0.0, xRatio, 1.0) * usableWidth);
        y = qRound(qBound(0.0, yRatio, 1.0) * usableHeight);
    }
    const QRect nextRect(x, y, boundsSize.width(), boundsSize.height());
    if (nextRect != m_overlayRect || contentSizeChanged) {
        m_overlayRect = nextRect;
        emit overlayGeometryChanged();
    }
    setInputRect(nextRect.x(), nextRect.y(), nextRect.width(), nextRect.height());
    qInfo() << "native system PiP: transparent canvas geometry"
            << "surface" << screen.width() << screen.height()
            << "content" << m_overlayRect
            << "videoItem" << m_contentSize
            << "orientation" << m_orientationAngle
            << "clickThroughOutside" << true;
}

void SystemPipController::saveWindowPosition() {
    if (!m_view || m_overlayRect.isEmpty()) return;
    const int usableWidth = qMax(1, m_view->width() - m_overlayRect.width());
    const int usableHeight = qMax(1, m_view->height() - m_overlayRect.height());
    const qreal xRatio = qBound(0.0, qreal(m_overlayRect.x()) / usableWidth, 1.0);
    const qreal yRatio = qBound(0.0, qreal(m_overlayRect.y()) / usableHeight, 1.0);
    QSettings settings;
    settings.setValue(QString::fromLatin1(kPipXRatioKey), xRatio);
    settings.setValue(QString::fromLatin1(kPipYRatioKey), yRatio);
    settings.sync();
    qInfo() << "native system PiP: position persisted"
            << "xRatio" << xRatio << "yRatio" << yRatio;
}

void SystemPipController::requestPresentationFrame() {
    if (!m_view || !m_view->isVisible()) {
        m_presentationTimer.stop();
        return;
    }
    m_view->update();
}

void SystemPipController::overlayFrameSwapped() {
    if (m_view && m_view->isVisible())
        ++m_swapFrames;
}

void SystemPipController::sampleFrameSwaps() {
    if (!m_view || !m_view->isVisible()) {
        m_swapFrames = 0;
        m_swapWindow.invalidate();
        return;
    }
    if (!m_swapWindow.isValid()) {
        m_swapWindow.start();
        return;
    }
    const qint64 elapsedMs = m_swapWindow.elapsed();
    if (elapsedMs < 1000) return;
    const double framesPerSecond = elapsedMs > 0
            ? 1000.0 * m_swapFrames / elapsedMs : 0.0;
    qInfo() << "native system PiP: frame swap window"
            << "frames" << m_swapFrames
            << "elapsedMs" << elapsedMs
            << "fps" << framesPerSecond
            << "below45" << (framesPerSecond + 0.001 < 45.0)
            << "qmlSceneGraph" << true;
    m_swapFrames = 0;
    m_swapWindow.restart();
}
