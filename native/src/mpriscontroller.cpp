#include "mpriscontroller.h"
#include "playbacksession.h"

#include <QCoreApplication>
#include <QDebug>
#include <QRegExp>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusError>
#include <QtDBus/QDBusMessage>
#include <cmath>

namespace {
const char service[] = "org.mpris.MediaPlayer2.silisili";
const char objectPath[] = "/org/mpris/MediaPlayer2";
const char playerInterface[] = "org.mpris.MediaPlayer2.Player";
qlonglong toMicroseconds(double seconds) {
    return qRound64(qMax(0.0, seconds) * 1000000.0);
}
}

MprisController::MprisController(PlaybackSession *session, QObject *parent)
    : QObject(parent), m_session(session), m_registered(false), m_pendingSeek(-1) {
    new MprisRootAdaptor(this);
    new MprisPlayerAdaptor(this);
    connect(session, &PlaybackSession::changed, this, &MprisController::publish);
    connect(session, &PlaybackSession::positionChanged,
            this, &MprisController::positionChanged);
    publish();
}

MprisController::~MprisController() {
    if (m_registered) {
        QDBusConnection::sessionBus().unregisterService(QString::fromLatin1(service));
        QDBusConnection::sessionBus().unregisterObject(QString::fromLatin1(objectPath));
    }
}

QString MprisController::playbackStatus() const {
    if (!m_session->active() || m_session->ended() || !m_session->errorMessage().isEmpty())
        return QStringLiteral("Stopped");
    return m_session->paused() ? QStringLiteral("Paused") : QStringLiteral("Playing");
}

QDBusObjectPath MprisController::trackId() const {
    if (!m_session->active())
        return QDBusObjectPath(QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack"));
    QString key = m_session->live()
            ? QStringLiteral("live_") + m_session->liveRoomId()
            : m_session->bvid() + QLatin1Char('_') + m_session->cid();
    key.replace(QRegExp(QStringLiteral("[^A-Za-z0-9_]")), QStringLiteral("_"));
    return QDBusObjectPath(QStringLiteral("/cn/silisili/track/") + key);
}

QVariantMap MprisController::metadata() const {
    QVariantMap result;
    result.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(trackId()));
    if (!m_session->active()) return result;
    result.insert(QStringLiteral("xesam:title"), m_session->title());
    if (!m_session->live())
        result.insert(QStringLiteral("mpris:length"), toMicroseconds(m_session->duration()));
    QString cover = m_session->cover();
    if (cover.startsWith(QStringLiteral("//"))) cover.prepend(QStringLiteral("https:"));
    if (!cover.isEmpty()) result.insert(QStringLiteral("mpris:artUrl"), cover);
    return result;
}

qlonglong MprisController::position() const { return toMicroseconds(m_session->position()); }
bool MprisController::canSeek() const {
    return m_session->active() && !m_session->live() && m_session->duration() > 0;
}

void MprisController::seekTo(qlonglong microseconds) {
    if (!canSeek()) return;
    m_pendingSeek = qBound<qlonglong>(0, microseconds, toMicroseconds(m_session->duration()));
    qInfo() << "native MPRIS: seek handled" << "targetUs" << m_pendingSeek;
    m_session->seek(m_pendingSeek / 1000000.0);
}

void MprisController::positionChanged() {
    if (m_pendingSeek >= 0 && qAbs(position() - m_pendingSeek) < 750000) {
        m_pendingSeek = -1;
        emit seekCompleted(position());
    }
}

void MprisController::publish() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (m_session->active() && !m_registered) {
        if (!bus.registerObject(QString::fromLatin1(objectPath), this,
                                QDBusConnection::ExportAdaptors)) {
            qWarning() << "native MPRIS: object registration failed" << bus.lastError().message();
            return;
        }
        if (!bus.registerService(QString::fromLatin1(service))) {
            bus.unregisterObject(QString::fromLatin1(objectPath));
            qWarning() << "native MPRIS: service registration failed" << bus.lastError().message();
            return;
        }
        m_registered = true;
        m_lastProperties.clear();
        qInfo() << "native MPRIS: service registered" << service;
    }
    if (!m_registered) return;
    QVariantMap values;
    values.insert(QStringLiteral("PlaybackStatus"), playbackStatus());
    values.insert(QStringLiteral("Metadata"), metadata());
    values.insert(QStringLiteral("Rate"), m_session->speed());
    values.insert(QStringLiteral("MinimumRate"), m_session->live() ? 1.0 : 0.25);
    values.insert(QStringLiteral("MaximumRate"), m_session->live() ? 1.0 : 4.0);
    values.insert(QStringLiteral("Volume"), m_session->volume() / 100.0);
    values.insert(QStringLiteral("CanSeek"), canSeek());
    values.insert(QStringLiteral("CanPlay"), m_session->active());
    values.insert(QStringLiteral("CanPause"), m_session->active() && !m_session->ended());
    values.insert(QStringLiteral("CanControl"), m_session->active());
    QVariantMap changed;
    for (QVariantMap::const_iterator it = values.constBegin(); it != values.constEnd(); ++it)
        if (m_lastProperties.value(it.key()) != it.value()) changed.insert(it.key(), it.value());
    m_lastProperties = values;
    if (!changed.isEmpty()) {
        QDBusMessage signal = QDBusMessage::createSignal(QString::fromLatin1(objectPath),
                QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
        signal << QString::fromLatin1(playerInterface) << changed << QStringList();
        bus.send(signal);
    }
    if (!m_session->active()) {
        bus.unregisterService(QString::fromLatin1(service));
        bus.unregisterObject(QString::fromLatin1(objectPath));
        m_registered = false;
        m_pendingSeek = -1;
        qInfo() << "native MPRIS: service released" << "playbackActive" << false;
    }
}

MprisRootAdaptor::MprisRootAdaptor(MprisController *controller)
    : QDBusAbstractAdaptor(controller), m_controller(controller) {}
void MprisRootAdaptor::Raise() { emit m_controller->raiseRequested(); }
void MprisRootAdaptor::Quit() { QCoreApplication::quit(); }

MprisPlayerAdaptor::MprisPlayerAdaptor(MprisController *controller)
    : QDBusAbstractAdaptor(controller), m_controller(controller) {
    connect(controller, &MprisController::seekCompleted, this, &MprisPlayerAdaptor::Seeked);
}
QString MprisPlayerAdaptor::playbackStatus() const { return m_controller->playbackStatus(); }
QVariantMap MprisPlayerAdaptor::metadata() const { return m_controller->metadata(); }
qlonglong MprisPlayerAdaptor::position() const { return m_controller->position(); }
bool MprisPlayerAdaptor::canSeek() const { return m_controller->canSeek(); }
bool MprisPlayerAdaptor::canPlay() const { return m_controller->session()->active(); }
bool MprisPlayerAdaptor::canPause() const { return canPlay() && !m_controller->session()->ended(); }
double MprisPlayerAdaptor::rate() const { return m_controller->session()->speed(); }
double MprisPlayerAdaptor::minimumRate() const { return m_controller->session()->live() ? 1.0 : 0.25; }
double MprisPlayerAdaptor::maximumRate() const { return m_controller->session()->live() ? 1.0 : 4.0; }
void MprisPlayerAdaptor::setRate(double value) {
    if (canPlay() && std::isfinite(value) && value > 0) m_controller->session()->setSpeed(value);
}
double MprisPlayerAdaptor::volume() const { return m_controller->session()->volume() / 100.0; }
void MprisPlayerAdaptor::setVolume(double value) {
    if (canPlay() && std::isfinite(value)) m_controller->session()->setVolume(qBound(0.0, value, 1.0) * 100.0);
}
void MprisPlayerAdaptor::Play() {
    if (canPlay()) {
        qInfo() << "native MPRIS: play handled";
        m_controller->session()->setPaused(false);
    }
}
void MprisPlayerAdaptor::Pause() {
    if (canPause()) {
        qInfo() << "native MPRIS: pause handled";
        m_controller->session()->setPaused(true);
    }
}
void MprisPlayerAdaptor::PlayPause() {
    if (canPlay()) {
        qInfo() << "native MPRIS: toggle handled";
        m_controller->session()->togglePaused();
    }
}
void MprisPlayerAdaptor::Stop() {
    if (canPlay()) {
        qInfo() << "native MPRIS: stop handled";
        m_controller->session()->stop();
    }
}
void MprisPlayerAdaptor::Seek(qlonglong offset) {
    if (!canSeek()) return;
    // Bound in seconds to avoid signed overflow from an untrusted D-Bus offset.
    const double target = m_controller->session()->position() + offset / 1000000.0;
    m_controller->seekTo(toMicroseconds(qBound(0.0, target, m_controller->session()->duration())));
}
void MprisPlayerAdaptor::SetPosition(const QDBusObjectPath &track, qlonglong position) {
    if (track.path() == m_controller->trackId().path()) m_controller->seekTo(position);
}
