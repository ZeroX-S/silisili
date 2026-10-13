#include "configmigration.h"
#include "appsettings.h"
#include "homefeedmodel.h"
#include "searchmodel.h"
#include "videodetailmodel.h"
#include "accountservice.h"
#include "accountlibrarymodel.h"
#include "qrcodeitem.h"
#include "regionfeedmodel.h"
#include "dynamicfeedmodel.h"
#include "inboxmodel.h"
#include "commentmodel.h"
#include "relatedmodel.h"
#include "playbackresolver.h"
#include "mpvvideoitem.h"
#include "playbacksession.h"
#include "mpriscontroller.h"
#include "danmakumodel.h"
#include "livefeedmodel.h"
#include "liveresolver.h"
#include "bilibiliimagenetwork.h"
#include "pgcfeedmodel.h"
#include "pgcdetailmodel.h"
#include "authorspacemodel.h"
#include "displayframemonitor.h"
#include "systempipcontroller.h"
#include "systemcontrols.h"

#include <QDebug>
#include <QCoreApplication>
#include <QEvent>
#include <QFile>
#include <QGuiApplication>
#include <QFileInfo>
#include <QLockFile>
#include <QOpenGLContext>
#include <QPluginLoader>
#include <QPointer>
#include <QQmlContext>
#include <QQuickView>
#include <QScopedPointer>
#include <QRegExp>
#include <QSurfaceFormat>
#include <QStringList>
#include <QSysInfo>
#include <QTimer>
#include <QtQml>
#include <sailfishapp.h>
#include <mpv/client.h>

#ifdef SILISILI_NATIVE_HAVE_DROIDMEDIA
extern "C" {
#include <droidmedia.h>
#include <droidmediacodec.h>
}
#endif

#include <clocale>
#include <cstring>

// Qt 5.6 exports this function as part of the Qt_5 ABI, but only declares it
// in a private header.  Sailfish's QQuickView and Cover scene graphs consult
// the global share context when AA_ShareOpenGLContexts is enabled.  Declaring
// the exported function here avoids a private-header build dependency.
QT_BEGIN_NAMESPACE
Q_GUI_EXPORT void qt_gl_set_global_share_context(QOpenGLContext *context);
QT_END_NAMESPACE

namespace {

#ifndef SILISILI_NATIVE_APP_VERSION
#define SILISILI_NATIVE_APP_VERSION "1.1.0"
#endif
#ifndef SILISILI_NATIVE_PACKAGE_RELEASE
#define SILISILI_NATIVE_PACKAGE_RELEASE "development"
#endif
#ifndef SILISILI_NATIVE_PACKAGE_NAME
#define SILISILI_NATIVE_PACKAGE_NAME "silisili-native-devel"
#endif

QString sailfishReleaseText() {
    QFile releaseFile(QStringLiteral("/etc/sailfish-release"));
    if (!releaseFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(releaseFile.readAll()).trimmed();
}

void parseSailfishVersion(const QString &releaseText, int *major, int *minor) {
    *major = -1;
    *minor = -1;
    // Sailfish images have used both VERSION_ID="5.2.0.0" and a human
    // readable "Sailfish OS 5.2" line. Keep this deliberately permissive so
    // the renderer choice follows the installed image rather than a build
    // target string.
    QRegExp versionRx(QStringLiteral("(VERSION_ID|Sailfish OS)[^0-9]*([0-9]+)\\.([0-9]+)"));
    if (versionRx.indexIn(releaseText) >= 0) {
        *major = versionRx.cap(2).toInt();
        *minor = versionRx.cap(3).toInt();
    }
}

QString conciseSailfishVersion(const QString &releaseText) {
    QRegExp versionRx(QStringLiteral(
        "(VERSION_ID|Sailfish OS)[^0-9]*([0-9]+(?:\\.[0-9]+){1,3})"));
    if (versionRx.indexIn(releaseText) >= 0)
        return versionRx.cap(2);
    return QStringLiteral("unknown");
}

QString mpvApiVersionText() {
    const unsigned long version = mpv_client_api_version();
    return QStringLiteral("%1.%2").arg(version >> 16).arg(version & 0xffff);
}

DirectVideoCapabilities directDroidMediaCapabilities(int sailfishVersionMajor,
                                                     int sailfishVersionMinor) {
    static bool probed = false;
    static DirectVideoCapabilities cached;
    if (probed) return cached;
    probed = true;
#ifdef SILISILI_NATIVE_HAVE_DROIDMEDIA
    const bool sailfish50 = sailfishVersionMajor == 5
            && sailfishVersionMinor == 0;
    const bool forceSailfish50Hardware = qgetenv(
                "SILISILI_NATIVE_ENABLE_SFOS50_DROIDMEDIA")
            == QByteArrayLiteral("1");
    if (sailfish50 && !forceSailfish50Hardware) {
        // Sailfish 5.0's device-side libdroidmedia BufferQueue permits only
        // two acquired buffers. Later official droidmedia fixes raise that
        // limit for devices and Codec2 B-frames. The statically linked
        // libdroidmedia.a is only a hybris symbol wrapper, so it cannot patch
        // the old device implementation. Avoid its audio-continues/video-
        // freezes failure mode by using the existing software path on 5.0.
        qWarning() << "native hardware video: Sailfish 5.0 compatibility route"
                   << "hardware" << false
                   << "fallback" << "libmpv-software"
                   << "reason" << "device-droidmedia-bufferqueue-two-buffer"
                   << "override" << "SILISILI_NATIVE_ENABLE_SFOS50_DROIDMEDIA=1";
        return cached;
    }
    if (sailfish50 && forceSailfish50Hardware) {
        qWarning() << "native hardware video: Sailfish 5.0 diagnostic override"
                   << "hardware" << true;
    }
    if (!droid_media_init()) {
        qWarning() << "native hardware video: droidmedia initialization failed"
                   << "fallback" << "software";
        return cached;
    }
    const struct Candidate {
        const char *mime;
        int codecId;
        int width;
        int height;
        int framesPerSecond;
    } candidates[] = {
        {"video/avc", 7, 4096, 2304, 60},
        {"video/avc", 7, 4096, 2304, 30},
        {"video/avc", 7, 3840, 2160, 60},
        {"video/avc", 7, 3840, 2160, 30},
        {"video/avc", 7, 1920, 1080, 60},
        {"video/avc", 7, 1920, 1080, 30},
        {"video/hevc", 12, 4096, 2304, 60},
        {"video/hevc", 12, 4096, 2304, 30},
        {"video/hevc", 12, 3840, 2160, 60},
        {"video/hevc", 12, 3840, 2160, 30},
        {"video/hevc", 12, 1920, 1080, 60},
        {"video/hevc", 12, 1920, 1080, 30}
    };
    for (const Candidate &candidate : candidates) {
        DroidMediaCodecMetaData metadata;
        std::memset(&metadata, 0, sizeof(metadata));
        metadata.type = candidate.mime;
        metadata.width = candidate.width;
        metadata.height = candidate.height;
        metadata.fps = candidate.framesPerSecond;
        metadata.flags = DROID_MEDIA_CODEC_HW_ONLY;
        const bool supported = droid_media_codec_is_supported(&metadata, false);
        qInfo() << "native hardware video: droidmedia capability"
                << candidate.mime
                << candidate.width << "x" << candidate.height
                << "fps" << candidate.framesPerSecond
                << "hardware" << supported;
        if (!supported) continue;
        const bool highCadence = candidate.framesPerSecond > 30;
        int *maximumWidth = candidate.codecId == 7
                ? (highCadence ? &cached.avc60MaximumWidth
                               : &cached.avc30MaximumWidth)
                : (highCadence ? &cached.hevc60MaximumWidth
                               : &cached.hevc30MaximumWidth);
        int *maximumHeight = candidate.codecId == 7
                ? (highCadence ? &cached.avc60MaximumHeight
                               : &cached.avc30MaximumHeight)
                : (highCadence ? &cached.hevc60MaximumHeight
                               : &cached.hevc30MaximumHeight);
        const qint64 candidatePixels = static_cast<qint64>(candidate.width)
                * candidate.height;
        const qint64 currentPixels = static_cast<qint64>(*maximumWidth)
                * *maximumHeight;
        if (candidatePixels > currentPixels) {
            *maximumWidth = candidate.width;
            *maximumHeight = candidate.height;
        }
    }
    qInfo() << "native hardware video: direct droidmedia route"
            << (cached.available() ? "available" : "unavailable")
            << "fallback" << (cached.available() ? "capability-driven" : "software")
            << "avc30Maximum" << cached.avc30MaximumWidth << "x"
            << cached.avc30MaximumHeight
            << "avc60Maximum" << cached.avc60MaximumWidth << "x"
            << cached.avc60MaximumHeight
            << "hevc30Maximum" << cached.hevc30MaximumWidth << "x"
            << cached.hevc30MaximumHeight
            << "hevc60Maximum" << cached.hevc60MaximumWidth << "x"
            << cached.hevc60MaximumHeight
            << "source" << "RooTheater-SailfishOS architecture";
#endif
    return cached;
}

bool amberBarcodeModuleAvailable() {
    const QStringList moduleDirs = QStringList()
            << QStringLiteral("/usr/lib64/qt5/qml/Amber/Barcode")
            << QStringLiteral("/usr/lib/qt5/qml/Amber/Barcode")
            << QStringLiteral("/usr/share/qt5/qml/Amber/Barcode")
            << QStringLiteral("/opt/qt5/qml/Amber/Barcode");
    for (const QString &moduleDir : moduleDirs) {
        if (QFileInfo::exists(moduleDir + QStringLiteral("/qmldir")))
            return true;
    }
    return false;
}

class ApplicationCloseFilter : public QObject {
public:
    ApplicationCloseFilter(QQuickView *mainView,
                           SystemPipController *pipController,
                           PlaybackSession *playbackSession,
                           QObject *parent)
        : QObject(parent), m_mainView(mainView), m_pipController(pipController),
          m_playbackSession(playbackSession), m_closeRequested(false) {}

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (watched == m_mainView && event && event->type() == QEvent::Close
                && !m_closeRequested) {
            m_closeRequested = true;
            qInfo() << "native application shutdown: main window close received"
                    << "systemPiPVisible"
                    << (m_pipController && m_pipController->visible());
            if (m_pipController) m_pipController->shutdown();
            if (m_playbackSession) m_playbackSession->stop();
            QTimer::singleShot(0, qApp, SLOT(quit()));
        }
        return QObject::eventFilter(watched, event);
    }

private:
    QPointer<QQuickView> m_mainView;
    SystemPipController *m_pipController;
    PlaybackSession *m_playbackSession;
    bool m_closeRequested;
};

} // namespace

int main(int argc, char *argv[]) {
    // libmpv refuses to create a client when LC_NUMERIC uses localized decimal
    // separators. Lipstick/sailjail launches inherit the device locale, unlike
    // the direct validation scripts, so normalize this before any mpv object
    // can be constructed.
    std::setlocale(LC_NUMERIC, "C");

    // The player owns an offscreen GL context and double-buffered video
    // textures. Put every Qt context in one share group before QGuiApplication
    // is constructed so rebuilt Cover/foreground scene graphs can sample the
    // same persistent textures without reloading or seeking the stream.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setApplicationName(QStringLiteral("silisili-native"));
    app->setOrganizationName(QStringLiteral("cn.silisili.native"));
    app->setApplicationVersion(QString::fromLatin1(SILISILI_NATIVE_APP_VERSION));

    // On Sailfish 5.1 the AA_ShareOpenGLContexts flag alone does not create a
    // root context before the first QQuickView is initialized.  A cold direct
    // live launch then has no global share group: the foreground can share
    // with its own window as a fallback, but the separately rendered Cover
    // cannot sample that texture.  Seed the process-wide root before creating
    // either view so foreground, Cover and system PiP join the same group.
    QScopedPointer<QOpenGLContext> seededGlobalShareContext;
    if (!QOpenGLContext::globalShareContext()) {
        seededGlobalShareContext.reset(new QOpenGLContext);
        seededGlobalShareContext->setFormat(QSurfaceFormat::defaultFormat());
        if (seededGlobalShareContext->create()) {
            qt_gl_set_global_share_context(seededGlobalShareContext.data());
            qInfo() << "native player: seeded process-wide global share context"
                    << "valid" << seededGlobalShareContext->isValid();
        } else {
            qWarning() << "native player: global share context seed failed;"
                       << "per-window compatibility fallback remains available";
            seededGlobalShareContext.reset();
        }
    }

    // Lipstick normally activates the existing task, but development package
    // replacement and crash recovery can race a second launcher. Keep the VOD
    // backend process-wide as well as session-wide.
    QLockFile instanceLock(QStringLiteral("/tmp/silisili-native-defaultuser.lock"));
    instanceLock.setStaleLockTime(3000);
    if (!instanceLock.tryLock(100)) {
        qWarning() << "native app: another instance may already be running; checking stale lock";
        if (!instanceLock.removeStaleLockFile() || !instanceLock.tryLock(100)) {
            qWarning() << "native app: another instance is already running";
            return 0;
        }
        qWarning() << "native app: recovered stale single-instance lock";
    }

    // Sailfish OS 5.1 ships its QR image generator inside the system sharing
    // plugin. Sailfish OS 5.2 moved the supported QML API to Amber.Barcode.
    // Probe both at runtime and load the 5.1 plugin softly; the QML page then
    // tries Amber first on 5.2 and falls back to QrShareImage if needed.
    const QString qrSailfishRelease = sailfishReleaseText();
    int qrSailfishVersionMajor = -1;
    int qrSailfishVersionMinor = -1;
    parseSailfishVersion(qrSailfishRelease,
                         &qrSailfishVersionMajor,
                         &qrSailfishVersionMinor);
    const bool qrBarcodeAvailable = amberBarcodeModuleAvailable();
    const QString qrPluginPath = QStringLiteral(
        "/usr/lib64/nemo-transferengine/plugins/sharing/libqrshareplugin.so");
    QPluginLoader *qrPluginLoader = new QPluginLoader(qrPluginPath, app.data());
    const bool qrShareAvailable = QFileInfo::exists(qrPluginPath)
                                  && qrPluginLoader->load()
                                  && qrPluginLoader->instance();
    int qrBuiltInSelfTestModules = 0;
    const bool qrBuiltInAvailable = QrCodeItem::selfTest(
                &qrBuiltInSelfTestModules);
    qInfo() << "native account: system QR renderer" << qrShareAvailable
            << (qrShareAvailable ? QString() : qrPluginLoader->errorString());
    qInfo() << "native account: Amber.Barcode module" << qrBarcodeAvailable
            << "Sailfish release" << qrSailfishRelease
            << "version" << qrSailfishVersionMajor << qrSailfishVersionMinor;
    qInfo() << "native account: built-in QR renderer" << qrBuiltInAvailable
            << "selfTestModules" << qrBuiltInSelfTestModules
            << "backend" << "Nayuki-QtQuick-painted";

    qmlRegisterType<VideoDetailModel>("cn.silisili.native.models", 1, 0, "VideoDetailModel");
    qmlRegisterType<CommentModel>("cn.silisili.native.models", 1, 0, "CommentModel");
    qmlRegisterType<RelatedModel>("cn.silisili.native.models", 1, 0, "RelatedModel");
    qmlRegisterType<PgcFeedModel>("cn.silisili.native.models", 1, 0, "PgcFeedModel");
    qmlRegisterType<PgcDetailModel>("cn.silisili.native.models", 1, 0, "PgcDetailModel");
    qmlRegisterType<AuthorSpaceModel>("cn.silisili.native.models", 1, 0, "AuthorSpaceModel");
    qmlRegisterType<AccountLibraryModel>("cn.silisili.native.models", 1, 0, "AccountLibraryModel");
    qmlRegisterType<QrCodeItem>("cn.silisili.native.qr", 1, 0, "QrCodeImage");
    qmlRegisterType<MpvVideoItem>("cn.silisili.native.player", 1, 0, "MpvVideoItem");
    qmlRegisterType<MpvVideoMirrorItem>("cn.silisili.native.player", 1, 0,
                                        "MpvVideoMirrorItem");

    const QString configMigrationState = ConfigMigration::migrateStableConfig();
    const DirectVideoCapabilities directVideoCapabilities =
            directDroidMediaCapabilities(qrSailfishVersionMajor,
                                         qrSailfishVersionMinor);
    const bool nativeHardwareDecodeAvailable = directVideoCapabilities.available();
    AppSettings appSettings;
    AccountService accountService;
    SearchModel searchModel(&accountService);
    HomeFeedModel homeFeed(&accountService);
    PlaybackResolver playbackResolver(&accountService, directVideoCapabilities);
    LiveResolver liveResolver(&accountService, directVideoCapabilities);
    MpvVideoItem playbackVideo;
    PlaybackSession playbackSession(&playbackResolver, &liveResolver,
                                    &accountService);
    playbackSession.setInAppMiniPlayerEnabled(
                appSettings.continueInAppMiniPlayer());
    QObject::connect(&appSettings, &AppSettings::continueInAppMiniPlayerChanged,
                     &playbackSession, [&]() {
        playbackSession.setInAppMiniPlayerEnabled(
                    appSettings.continueInAppMiniPlayer());
    });
    DisplayFrameMonitor displayFrameMonitor(&playbackSession);
    playbackSession.attachPlayer(&playbackVideo);
    SystemControls systemControls(app.data());
    QObject::connect(&playbackSession, &PlaybackSession::changed,
                     &systemControls, [&]() {
        if (playbackSession.active() && !playbackSession.ended()) {
            systemControls.beginPlaybackSession();
        } else {
            systemControls.restorePlaybackSession(
                        playbackSession.ended()
                        ? QStringLiteral("playback-ended")
                        : QStringLiteral("playback-inactive"));
        }
    });
    DanmakuModel danmakuModel;
    LiveFeedModel liveFeed;
    RegionFeedModel regionFeed;
    DynamicFeedModel dynamicFeed(&accountService);
    InboxModel inboxModel(&accountService);
    QScopedPointer<QQuickView> view(SailfishApp::createView());
    MprisController mprisController(&playbackSession);
    QObject::connect(&mprisController, &MprisController::raiseRequested,
                     view.data(), [&]() { view->requestActivate(); });
    SystemPipController systemPipController(view.data(), &playbackSession,
                                            &playbackVideo, app.data());
    ApplicationCloseFilter applicationCloseFilter(
                view.data(), &systemPipController, &playbackSession, app.data());
    view->installEventFilter(&applicationCloseFilter);
    QObject::connect(app.data(), &QCoreApplication::aboutToQuit, [&]() {
        qInfo() << "native application shutdown: barrier started"
                << "systemPiPVisible" << systemPipController.visible()
                << "playbackActive" << playbackSession.active();
        systemPipController.shutdown();
        systemControls.restorePlaybackSession(QStringLiteral("application-quit"));
        playbackSession.stop();
        playbackVideo.shutdown();
        qInfo() << "native application shutdown: barrier complete"
                << "systemPiPVisible" << systemPipController.visible()
                << "playbackActive" << playbackSession.active();
    });
    // Device regression hook: enter a real background system-PiP state, then
    // issue the same QWindow Close event as task-switcher application closure.
    // Production never schedules this path.
    if (qgetenv("SILISILI_NATIVE_TEST_CLOSE_WHILE_PIP")
            == QByteArrayLiteral("1")) {
        QObject::connect(&systemPipController,
                         &SystemPipController::visibilityChanged,
                         app.data(), [&]() {
            if (!systemPipController.visible()
                    || app->property("pipCloseScheduled").toBool())
                return;
            app->setProperty("pipCloseScheduled", true);
            qInfo() << "native application shutdown test: close scheduled"
                    << "systemPiPVisible" << true;
            const QPointer<QQuickView> guardedView(view.data());
            QTimer::singleShot(2500, app.data(), [guardedView]() {
                if (guardedView) guardedView->close();
            });
        });
    }
    QObject::connect(view.data(), &QQuickWindow::frameSwapped,
                     &displayFrameMonitor, &DisplayFrameMonitor::frameSwapped,
                     Qt::QueuedConnection);
    QObject::connect(view.data(), &QQuickWindow::frameSwapped,
                     &playbackVideo, &MpvVideoItem::reportDisplaySwap,
                     Qt::QueuedConnection);
    QObject::connect(view.data(), &QQuickWindow::sceneGraphInitialized,
                     &playbackVideo, &MpvVideoItem::prewarm,
                     Qt::QueuedConnection);
    // QML Image requests otherwise use Qt's generic headers and memory-only
    // cache. Bilibili's avatar CDN intermittently rejects or drops those
    // requests. Supply the same public Referer/User-Agent as the API clients
    // and retain successful images in a bounded application cache.
    view->engine()->setNetworkAccessManagerFactory(new BilibiliImageNetworkFactory);
    // Sailfish hides the application window while its Cover is active.  Keep
    // the scene graph and GL context alive so the one libmpv render context is
    // not torn down and recreated on every background/foreground transition.
    view->setPersistentSceneGraph(true);
    view->setPersistentOpenGLContext(true);
    view->rootContext()->setContextProperty(QStringLiteral("homeFeed"), &homeFeed);
    view->rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    view->rootContext()->setContextProperty(QStringLiteral("searchModel"), &searchModel);
    view->rootContext()->setContextProperty(QStringLiteral("accountService"), &accountService);
    view->rootContext()->setContextProperty(QStringLiteral("playbackResolver"), &playbackResolver);
    view->rootContext()->setContextProperty(QStringLiteral("playbackVideo"), &playbackVideo);
    view->rootContext()->setContextProperty(QStringLiteral("playbackSession"), &playbackSession);
    view->rootContext()->setContextProperty(QStringLiteral("systemPipController"),
                                            &systemPipController);
    view->rootContext()->setContextProperty(QStringLiteral("systemControls"),
                                            &systemControls);
    view->rootContext()->setContextProperty(QStringLiteral("danmakuModel"), &danmakuModel);
    view->rootContext()->setContextProperty(QStringLiteral("liveFeed"), &liveFeed);
    view->rootContext()->setContextProperty(QStringLiteral("regionFeed"), &regionFeed);
    view->rootContext()->setContextProperty(QStringLiteral("dynamicFeed"), &dynamicFeed);
    view->rootContext()->setContextProperty(QStringLiteral("inboxModel"), &inboxModel);
    view->rootContext()->setContextProperty(QStringLiteral("configMigrationState"), configMigrationState);
    view->rootContext()->setContextProperty(QStringLiteral("qrShareAvailable"), qrShareAvailable);
    view->rootContext()->setContextProperty(QStringLiteral("qrBarcodeAvailable"), qrBarcodeAvailable);
    view->rootContext()->setContextProperty(QStringLiteral("qrBuiltInAvailable"),
                                            qrBuiltInAvailable);
    view->rootContext()->setContextProperty(QStringLiteral("qrSailfishRelease"), qrSailfishRelease);
    view->rootContext()->setContextProperty(QStringLiteral("qrSailfishVersionMajor"),
                                            qrSailfishVersionMajor);
    view->rootContext()->setContextProperty(QStringLiteral("qrSailfishVersionMinor"),
                                            qrSailfishVersionMinor);
    const QString nativeAppVersion = QString::fromLatin1(SILISILI_NATIVE_APP_VERSION);
    const QString nativePackageRelease = QString::fromLatin1(
        SILISILI_NATIVE_PACKAGE_RELEASE);
    view->rootContext()->setContextProperty(QStringLiteral("nativeAppVersion"),
                                            nativeAppVersion);
    view->rootContext()->setContextProperty(QStringLiteral("nativePackageRelease"),
                                            nativePackageRelease);
    view->rootContext()->setContextProperty(QStringLiteral("nativePackageName"),
                                            QString::fromLatin1(SILISILI_NATIVE_PACKAGE_NAME));
    view->rootContext()->setContextProperty(QStringLiteral("nativePackageVersion"),
                                            nativeAppVersion + QStringLiteral("-")
                                            + nativePackageRelease);
    view->rootContext()->setContextProperty(QStringLiteral("nativeBuildArchitecture"),
                                            QSysInfo::buildCpuArchitecture());
    view->rootContext()->setContextProperty(QStringLiteral("nativeQtVersion"),
                                            QString::fromLatin1(qVersion()));
    view->rootContext()->setContextProperty(QStringLiteral("nativeMpvApiVersion"),
                                            mpvApiVersionText());
    view->rootContext()->setContextProperty(QStringLiteral("nativeHardwareDecodeAvailable"),
                                            nativeHardwareDecodeAvailable);
    view->rootContext()->setContextProperty(QStringLiteral("nativeSailfishVersion"),
                                            conciseSailfishVersion(qrSailfishRelease));
    qInfo() << "native app: build identity"
            << QString::fromLatin1(SILISILI_NATIVE_PACKAGE_NAME)
            << nativeAppVersion << nativePackageRelease
            << "architecture" << QSysInfo::buildCpuArchitecture()
            << "Qt" << qVersion() << "mpvApi" << mpvApiVersionText();
    // Production follows the device sensor.  The development-only environment
    // override lets a real-device regression force one orientation without
    // changing the user's normal orientation policy or relying on screenshots.
    const QString forcedOrientation = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_FORCE_ORIENTATION")).trimmed().toLower();
    const QString testPage = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_PAGE")).trimmed().toLower();
    const QString testBvid = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_BVID")).trimmed();
    const QString testCid = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_CID")).trimmed();
    const QString testRoomId = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_ROOM_ID")).trimmed();
    const QString testAid = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_AID")).trimmed();
    const QString testContentMode = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_CONTENT_MODE")).trimmed().toLower();
    const QString testMid = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_MID")).trimmed();
    bool testQualityReady = false;
    const int testQuality = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_QUALITY")).trimmed()
            .toInt(&testQualityReady);
    bool testStartPositionReady = false;
    const double testStartPosition = QString::fromLocal8Bit(
        qgetenv("SILISILI_NATIVE_TEST_START_POSITION")).trimmed()
            .toDouble(&testStartPositionReady);
    view->rootContext()->setContextProperty(QStringLiteral("nativeForcedOrientation"),
                                            forcedOrientation);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestPage"), testPage);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestBvid"), testBvid);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestCid"), testCid);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestRoomId"), testRoomId);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestAid"), testAid);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestContentMode"),
                                            testContentMode);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestMid"), testMid);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestQuality"),
                                            testQualityReady
                                            ? qBound(1, testQuality, 127) : 0);
    view->rootContext()->setContextProperty(QStringLiteral("nativeTestStartPosition"),
                                            testStartPositionReady
                                            ? qMax(0.0, testStartPosition) : 0.0);
    qInfo() << "native system PiP: configurable background presentation ready"
            << "mode" << systemPipController.backgroundPlaybackMode()
            << "available" << systemPipController.available();
    qInfo() << "native layout: forced orientation"
            << (forcedOrientation.isEmpty() ? QStringLiteral("device") : forcedOrientation);
    qInfo() << "native layout: development initial page"
            << (testPage.isEmpty() ? QStringLiteral("home") : testPage);
    view->setSource(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    view->showFullScreen();
    const bool directPlaybackRegression = testPage == QStringLiteral("video-detail")
            || testPage == QStringLiteral("history-resume")
            || testPage == QStringLiteral("comment-actions")
            || testPage == QStringLiteral("pgc-consistency")
            || testPage == QStringLiteral("about")
            || testPage == QStringLiteral("playback-presentation")
            || testPage == QStringLiteral("compact")
            || testPage == QStringLiteral("compact-continuity")
            || testPage == QStringLiteral("multipart-autonext")
            || testPage == QStringLiteral("live-player");
    if (testPage == QStringLiteral("network-recovery")) {
        // Isolate the deterministic network-transition regression from the
        // unrelated account refresh so the one-shot failure always targets
        // the home-feed request that the QML recovery probe observes.
        homeFeed.refresh();
    } else if (testPage == QStringLiteral("comment-actions")) {
        // The comment regression needs the authenticated /nav result so the
        // same login gates as production enable its controls. Keep unrelated
        // home-feed work out of the mutation test.
        accountService.refresh();
    } else if (!directPlaybackRegression) {
        homeFeed.refresh();
        accountService.refresh();
    } else {
        // The direct playback gate models tapping a video after the already
        // visible home feed has settled. Do not let unrelated cold-start home
        // and account requests contend with the measured playurl/media path.
        qInfo() << "native detail perf: unrelated startup refresh suppressed"
                << "testPage" << testPage;
    }
    return app->exec();
}
