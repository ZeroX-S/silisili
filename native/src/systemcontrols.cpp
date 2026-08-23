#include "systemcontrols.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegExp>
#include <QTextStream>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusMetaType>
#include <QtDBus/QDBusObjectPath>
#include <QtDBus/QDBusVariant>
#include <QtGlobal>

#include <unistd.h>

struct PulseVolumeChannel {
    quint32 position;
    quint32 volume;
};

typedef QList<PulseVolumeChannel> PulseVolumeChannels;

QDBusArgument &operator<<(QDBusArgument &argument,
                          const PulseVolumeChannel &channel) {
    argument.beginStructure();
    argument << channel.position << channel.volume;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument,
                                PulseVolumeChannel &channel) {
    argument.beginStructure();
    argument >> channel.position >> channel.volume;
    argument.endStructure();
    return argument;
}

Q_DECLARE_METATYPE(PulseVolumeChannel)
Q_DECLARE_METATYPE(PulseVolumeChannels)

namespace {
const int kSystemCommandTimeoutMs = 1800;
const quint32 kPulseVolumeNorm = 0x10000;
const char kStreamRestorePath[] = "/org/pulseaudio/stream_restore1";
const char kStreamRestoreInterface[] = "org.PulseAudio.Ext.StreamRestore1";
const char kStreamRestoreEntryInterface[] =
        "org.PulseAudio.Ext.StreamRestore1.RestoreEntry";
const char kPropertiesInterface[] = "org.freedesktop.DBus.Properties";
const char kMediaRestoreEntry[] = "sink-input-by-media-role:x-maemo";

int readIntegerFile(const QString &path, bool *ok) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (ok) *ok = false;
        return 0;
    }
    const QByteArray data = file.readAll().trimmed();
    const int value = QString::fromLatin1(data).toInt(ok);
    return value;
}

bool writeIntegerFile(const QString &path, int value) {
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    file.write(QByteArray::number(value));
    file.write("\n");
    return file.error() == QFile::NoError;
}

QStringList brightnessCandidateFiles() {
    QStringList result;
    const QStringList preferredRoots = QStringList()
            << QStringLiteral("/sys/class/backlight")
            << QStringLiteral("/sys/class/leds");
    for (const QString &root : preferredRoots) {
        QDir dir(root);
        const QFileInfoList entries = dir.entryInfoList(
                    QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &entry : entries) {
            const QString brightness = entry.absoluteFilePath()
                    + QStringLiteral("/brightness");
            if (QFileInfo::exists(brightness))
                result.append(brightness);
        }
    }
    QDirIterator iterator(QStringLiteral("/sys/devices/platform"),
                          QStringList() << QStringLiteral("brightness"),
                          QDir::Files,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext() && result.size() < 48) {
        const QString brightness = iterator.next();
        const QString parentPath = QFileInfo(brightness).absolutePath();
        const QString maximum = parentPath + QStringLiteral("/max_brightness");
        if (QFileInfo::exists(maximum)
                && (parentPath.contains(QStringLiteral("backlight"))
                    || parentPath.contains(QStringLiteral("display"))
                    || parentPath.contains(QStringLiteral("panel"))))
            result.append(brightness);
    }
    result.removeDuplicates();
    result.sort();
    return result;
}

double parseFirstPercent(const QString &text, bool *ok) {
    QRegExp percentRx(QStringLiteral("([0-9]+(?:\\.[0-9]+)?)%"));
    if (percentRx.indexIn(text) < 0) {
        if (ok) *ok = false;
        return 0.0;
    }
    const double value = percentRx.cap(1).toDouble(ok);
    return value;
}
}

SystemControls::SystemControls(QObject *parent)
    : QObject(parent),
      m_brightnessMaximum(0),
      m_brightnessUsesMce(false),
      m_volumeAvailable(false),
      m_pulsePeerConnectionName(
          QStringLiteral("silisili-native-pulse-peer-%1").arg(getpid())),
      m_sessionActive(false),
      m_savedBrightnessValid(false),
      m_savedVolumeValid(false),
      m_savedBrightnessValue(0),
      m_savedVolumePercent(0.0),
      m_cachedBrightnessPercent(50.0),
      m_cachedVolumePercent(100.0) {
    qRegisterMetaType<PulseVolumeChannel>("PulseVolumeChannel");
    qRegisterMetaType<PulseVolumeChannels>("PulseVolumeChannels");
    qDBusRegisterMetaType<PulseVolumeChannel>();
    qDBusRegisterMetaType<PulseVolumeChannels>();
    discoverBrightnessPath();
    discoverVolume();
    refresh();
    qInfo() << "native system controls: ready"
            << "brightnessAvailable" << brightnessAvailable()
            << "brightnessUsesMce" << m_brightnessUsesMce
            << "brightnessPath" << m_brightnessPath
            << "brightnessMaximum" << m_brightnessMaximum
            << "volumeAvailable" << m_volumeAvailable
            << "brightnessPercent" << m_cachedBrightnessPercent
            << "volumePercent" << m_cachedVolumePercent;
}

SystemControls::~SystemControls() {
    restorePlaybackSession(QStringLiteral("application-destruction"));
    QDBusConnection::disconnectFromPeer(m_pulsePeerConnectionName);
}

void SystemControls::discoverBrightnessPath() {
    bool mceOk = false;
    const double mceBrightness = queryMceBrightnessPercent(&mceOk);
    if (mceOk) {
        m_brightnessUsesMce = true;
        m_brightnessMaximum = 100;
        m_cachedBrightnessPercent = mceBrightness;
        qInfo() << "native system controls: brightness route"
                << "route" << "mcetool"
                << "percent" << m_cachedBrightnessPercent;
        return;
    }
    for (const QString &candidate : brightnessCandidateFiles()) {
        const QString maximumPath = QFileInfo(candidate).absolutePath()
                + QStringLiteral("/max_brightness");
        bool brightnessOk = false;
        bool maximumOk = false;
        readIntegerFile(candidate, &brightnessOk);
        const int maximum = readIntegerFile(maximumPath, &maximumOk);
        if (!brightnessOk || !maximumOk || maximum <= 0
                || !QFileInfo(candidate).isWritable())
            continue;
        m_brightnessPath = candidate;
        m_brightnessMaximum = maximum;
        m_brightnessUsesMce = false;
        return;
    }
}

void SystemControls::discoverVolume() {
    bool ok = false;
    queryVolumePercent(&ok);
    m_volumeAvailable = ok;
}

int SystemControls::readBrightnessValue() const {
    if (m_brightnessUsesMce) {
        bool ok = false;
        const double value = queryMceBrightnessPercent(&ok);
        return ok ? qRound(value) : -1;
    }
    if (m_brightnessPath.isEmpty())
        return -1;
    bool ok = false;
    const int value = readIntegerFile(m_brightnessPath, &ok);
    return ok ? value : -1;
}

bool SystemControls::writeBrightnessValue(int value) {
    if (!brightnessAvailable())
        return false;
    if (m_brightnessUsesMce)
        return writeMceBrightnessPercent(value);
    const int bounded = qBound(1, value, m_brightnessMaximum);
    const bool ok = writeIntegerFile(m_brightnessPath, bounded);
    if (!ok) {
        qWarning() << "native system controls: brightness write failed"
                   << m_brightnessPath << bounded;
        return false;
    }
    m_cachedBrightnessPercent = 100.0 * bounded / m_brightnessMaximum;
    emit changed();
    return true;
}

QString SystemControls::runMceTool(const QStringList &arguments, bool *ok) const {
    QProcess process;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    if (environment.value(QStringLiteral("XDG_RUNTIME_DIR")).isEmpty()) {
        const QString uidRuntime = QStringLiteral("/run/user/%1").arg(getuid());
        if (QFileInfo(uidRuntime).isDir())
            environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), uidRuntime);
    }
    process.setProcessEnvironment(environment);
    process.start(QStringLiteral("mcetool"), arguments);
    if (!process.waitForFinished(kSystemCommandTimeoutMs)) {
        process.kill();
        process.waitForFinished(250);
        if (ok) *ok = false;
        return QString();
    }
    const bool success = process.exitStatus() == QProcess::NormalExit
            && process.exitCode() == 0;
    if (ok) *ok = success;
    if (!success)
        return QString::fromLocal8Bit(process.readAllStandardError());
    return QString::fromLocal8Bit(process.readAllStandardOutput());
}

double SystemControls::queryMceBrightnessPercent(bool *ok) const {
    bool commandOk = false;
    const QString output = runMceTool(QStringList() << QStringLiteral("-N"),
                                     &commandOk);
    QRegExp brightnessRx(QStringLiteral("Brightness:\\s*([0-9]+)\\s*\\("));
    const bool parseOk = commandOk && brightnessRx.indexIn(output) >= 0;
    if (ok) *ok = parseOk;
    return parseOk ? qBound(1.0, brightnessRx.cap(1).toDouble(), 100.0) : 0.0;
}

bool SystemControls::writeMceBrightnessPercent(double percent) {
    const int bounded = qBound(1, qRound(percent), 100);
    bool ok = false;
    runMceTool(QStringList()
               << QStringLiteral("--set-display-brightness=%1").arg(bounded),
               &ok);
    if (!ok) {
        qWarning() << "native system controls: mcetool brightness write failed"
                   << bounded;
        return false;
    }
    m_cachedBrightnessPercent = bounded;
    emit changed();
    return true;
}

QStringList SystemControls::activeSinkInputIndexes() const {
    bool commandOk = false;
    const QString output = runPactl(QStringList()
                                    << QStringLiteral("list")
                                    << QStringLiteral("sink-inputs"),
                                    &commandOk);
    QStringList indexes;
    if (!commandOk)
        return indexes;

    const QStringList lines = output.split(QLatin1Char('\n'));
    QString currentIndex;
    bool currentMatches = false;
    const QString pidToken = QStringLiteral("application.process.id = \"%1\"")
            .arg(getpid());
    for (const QString &line : lines) {
        QRegExp inputRx(QStringLiteral("^Sink Input #([0-9]+)"));
        if (inputRx.indexIn(line) >= 0) {
            if (!currentIndex.isEmpty() && currentMatches)
                indexes.append(currentIndex);
            currentIndex = inputRx.cap(1);
            currentMatches = false;
            continue;
        }
        if (line.contains(pidToken)
                || line.contains(QStringLiteral("application.process.binary = \"silisili-native\""))
                || line.contains(QStringLiteral("application.process.arg0 = \"/usr/bin/silisili-native\""))) {
            currentMatches = true;
        }
    }
    if (!currentIndex.isEmpty() && currentMatches)
        indexes.append(currentIndex);
    indexes.removeDuplicates();
    return indexes;
}

double SystemControls::queryActiveSinkInputVolumePercent(bool *ok) const {
    bool commandOk = false;
    const QString output = runPactl(QStringList()
                                    << QStringLiteral("list")
                                    << QStringLiteral("sink-inputs"),
                                    &commandOk);
    if (!commandOk) {
        if (ok) *ok = false;
        return 0.0;
    }

    const QStringList lines = output.split(QLatin1Char('\n'));
    bool inCurrentInput = false;
    bool currentMatches = false;
    bool currentVolumeValid = false;
    double currentVolume = 0.0;
    const QString pidToken = QStringLiteral("application.process.id = \"%1\"")
            .arg(getpid());
    for (const QString &line : lines) {
        if (line.startsWith(QStringLiteral("Sink Input #"))) {
            if (inCurrentInput && currentMatches && currentVolumeValid) {
                if (ok) *ok = true;
                return qBound(0.0, currentVolume, 150.0);
            }
            inCurrentInput = true;
            currentMatches = false;
            currentVolumeValid = false;
            currentVolume = 0.0;
            continue;
        }
        if (!inCurrentInput)
            continue;
        if (line.contains(pidToken)
                || line.contains(QStringLiteral("application.process.binary = \"silisili-native\""))
                || line.contains(QStringLiteral("application.process.arg0 = \"/usr/bin/silisili-native\""))) {
            currentMatches = true;
        }
        if (line.trimmed().startsWith(QStringLiteral("Volume:"))) {
            bool parseOk = false;
            const double value = parseFirstPercent(line, &parseOk);
            if (parseOk) {
                currentVolumeValid = true;
                currentVolume = value;
            }
        }
    }
    if (inCurrentInput && currentMatches && currentVolumeValid) {
        if (ok) *ok = true;
        return qBound(0.0, currentVolume, 150.0);
    }
    if (ok) *ok = false;
    return 0.0;
}

bool SystemControls::ensurePulseStreamRestore() {
    if (!m_streamRestoreEntryPath.isEmpty()
            && QDBusConnection(m_pulsePeerConnectionName).isConnected())
        return true;

    QString runtime = QProcessEnvironment::systemEnvironment().value(
                QStringLiteral("XDG_RUNTIME_DIR"));
    const QString uidRuntime = QStringLiteral("/run/user/%1").arg(getuid());
    if (runtime.isEmpty()
            || !QFileInfo(runtime + QStringLiteral("/pulse/dbus-socket")).exists())
        runtime = uidRuntime;
    const QString socketPath = runtime + QStringLiteral("/pulse/dbus-socket");
    if (!QFileInfo(socketPath).exists())
        return false;

    if (!QDBusConnection(m_pulsePeerConnectionName).isConnected()) {
        const QDBusConnection created = QDBusConnection::connectToPeer(
                    QStringLiteral("unix:path=%1").arg(socketPath),
                    m_pulsePeerConnectionName);
        if (!created.isConnected()) {
            qWarning() << "native system controls: PulseAudio peer connection failed"
                       << socketPath << created.lastError().message();
            return false;
        }
    }

    QDBusMessage request = QDBusMessage::createMethodCall(
                QString(), QString::fromLatin1(kStreamRestorePath),
                QString::fromLatin1(kStreamRestoreInterface),
                QStringLiteral("GetEntryByName"));
    request << QString::fromLatin1(kMediaRestoreEntry);
    const QDBusMessage response = QDBusConnection(m_pulsePeerConnectionName)
            .call(request, QDBus::Block, kSystemCommandTimeoutMs);
    if (response.type() == QDBusMessage::ErrorMessage
            || response.arguments().isEmpty()) {
        qWarning() << "native system controls: media StreamRestore entry unavailable"
                   << response.errorMessage();
        return false;
    }
    const QDBusObjectPath entry = qvariant_cast<QDBusObjectPath>(
                response.arguments().first());
    if (entry.path().isEmpty())
        return false;
    m_streamRestoreEntryPath = entry.path();
    qInfo() << "native system controls: volume route"
            << "route" << "pulse-stream-restore"
            << "entry" << kMediaRestoreEntry
            << "path" << m_streamRestoreEntryPath;
    return true;
}

bool SystemControls::readPulseStreamRestoreVolume(double *percent) {
    if (!ensurePulseStreamRestore())
        return false;
    QDBusMessage request = QDBusMessage::createMethodCall(
                QString(), m_streamRestoreEntryPath,
                QString::fromLatin1(kPropertiesInterface),
                QStringLiteral("Get"));
    request << QString::fromLatin1(kStreamRestoreEntryInterface)
            << QStringLiteral("Volume");
    const QDBusMessage response = QDBusConnection(m_pulsePeerConnectionName)
            .call(request, QDBus::Block, kSystemCommandTimeoutMs);
    if (response.type() == QDBusMessage::ErrorMessage
            || response.arguments().isEmpty())
        return false;

    QVariant value = response.arguments().first();
    if (value.userType() == qMetaTypeId<QDBusVariant>())
        value = qvariant_cast<QDBusVariant>(value).variant();
    const PulseVolumeChannels channels = qdbus_cast<PulseVolumeChannels>(value);
    if (channels.isEmpty())
        return false;
    quint64 total = 0;
    for (const PulseVolumeChannel &channel : channels)
        total += channel.volume;
    const double average = static_cast<double>(total) / channels.size();
    if (percent)
        *percent = qBound(0.0, average * 100.0 / kPulseVolumeNorm, 100.0);
    return true;
}

bool SystemControls::writePulseStreamRestoreVolume(double percent) {
    if (!ensurePulseStreamRestore())
        return false;

    QDBusMessage getRequest = QDBusMessage::createMethodCall(
                QString(), m_streamRestoreEntryPath,
                QString::fromLatin1(kPropertiesInterface),
                QStringLiteral("Get"));
    getRequest << QString::fromLatin1(kStreamRestoreEntryInterface)
               << QStringLiteral("Volume");
    const QDBusMessage getResponse = QDBusConnection(m_pulsePeerConnectionName)
            .call(getRequest, QDBus::Block, kSystemCommandTimeoutMs);
    if (getResponse.type() == QDBusMessage::ErrorMessage
            || getResponse.arguments().isEmpty())
        return false;
    QVariant value = getResponse.arguments().first();
    if (value.userType() == qMetaTypeId<QDBusVariant>())
        value = qvariant_cast<QDBusVariant>(value).variant();
    PulseVolumeChannels channels = qdbus_cast<PulseVolumeChannels>(value);
    if (channels.isEmpty())
        return false;

    const quint32 raw = qRound(qBound(0.0, percent, 100.0)
                               * kPulseVolumeNorm / 100.0);
    for (PulseVolumeChannel &channel : channels)
        channel.volume = raw;

    QDBusMessage setRequest = QDBusMessage::createMethodCall(
                QString(), m_streamRestoreEntryPath,
                QString::fromLatin1(kPropertiesInterface),
                QStringLiteral("Set"));
    setRequest << QString::fromLatin1(kStreamRestoreEntryInterface)
               << QStringLiteral("Volume")
               << QVariant::fromValue(
                      QDBusVariant(QVariant::fromValue(channels)));
    const QDBusMessage setResponse = QDBusConnection(m_pulsePeerConnectionName)
            .call(setRequest, QDBus::Block, kSystemCommandTimeoutMs);
    if (setResponse.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "native system controls: media StreamRestore write failed"
                   << setResponse.errorMessage();
        return false;
    }
    m_cachedVolumePercent = qBound(0.0, percent, 100.0);
    return true;
}

QString SystemControls::runPactl(const QStringList &arguments, bool *ok) const {
    QProcess process;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    QString runtime = environment.value(QStringLiteral("XDG_RUNTIME_DIR"));
    const QString uidRuntime = QStringLiteral("/run/user/%1").arg(getuid());
    if (runtime.isEmpty()
            || !QFileInfo(runtime + QStringLiteral("/pulse/native")).exists()) {
        if (QFileInfo(uidRuntime + QStringLiteral("/pulse/native")).exists()) {
            runtime = uidRuntime;
        } else if (QFileInfo(QStringLiteral("/run/user/100000/pulse/native")).exists()) {
            runtime = QStringLiteral("/run/user/100000");
        }
        if (!runtime.isEmpty())
            environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtime);
    }
    if (!runtime.isEmpty()) {
        environment.insert(QStringLiteral("PULSE_SERVER"),
                           QStringLiteral("unix:%1/pulse/native").arg(runtime));
    }
    process.setProcessEnvironment(environment);
    process.start(QStringLiteral("pactl"), arguments);
    if (!process.waitForFinished(kSystemCommandTimeoutMs)) {
        process.kill();
        process.waitForFinished(250);
        if (ok) *ok = false;
        return QString();
    }
    const bool success = process.exitStatus() == QProcess::NormalExit
            && process.exitCode() == 0;
    if (ok) *ok = success;
    if (!success)
        return QString::fromLocal8Bit(process.readAllStandardError());
    return QString::fromLocal8Bit(process.readAllStandardOutput());
}

double SystemControls::queryVolumePercent(bool *ok) const {
    double restoredValue = 0.0;
    if (const_cast<SystemControls *>(this)->readPulseStreamRestoreVolume(
                &restoredValue)) {
        if (ok) *ok = true;
        return restoredValue;
    }

    bool inputOk = false;
    const double inputValue = queryActiveSinkInputVolumePercent(&inputOk);
    if (inputOk) {
        if (ok) *ok = true;
        return inputValue;
    }

    bool commandOk = false;
    QString output = runPactl(QStringList()
                              << QStringLiteral("get-sink-volume")
                              << QStringLiteral("@DEFAULT_SINK@"),
                              &commandOk);
    bool parseOk = false;
    double value = commandOk ? parseFirstPercent(output, &parseOk) : 0.0;
    if (!parseOk) {
        output = runPactl(QStringList() << QStringLiteral("list")
                          << QStringLiteral("sinks"), &commandOk);
        value = commandOk ? parseFirstPercent(output, &parseOk) : 0.0;
    }
    if (ok) *ok = parseOk;
    return qBound(0.0, value, 150.0);
}

bool SystemControls::writeVolumePercent(double percent) {
    const double bounded = qBound(0.0, percent, 150.0);
    if (writePulseStreamRestoreVolume(bounded)) {
        m_volumeAvailable = true;
        qInfo() << "native system controls: volume write"
                << "route" << "pulse-stream-restore"
                << "entry" << kMediaRestoreEntry
                << "percent" << bounded;
        emit changed();
        return true;
    }

    bool ok = false;
    runPactl(QStringList() << QStringLiteral("set-sink-volume")
             << QStringLiteral("@DEFAULT_SINK@")
             << QStringLiteral("%1%").arg(bounded, 0, 'f', 3), &ok);
    const QStringList sinkInputs = activeSinkInputIndexes();
    bool inputOk = false;
    for (const QString &index : sinkInputs) {
        bool singleInputOk = false;
        runPactl(QStringList() << QStringLiteral("set-sink-input-volume")
                 << index
                 << QStringLiteral("%1%").arg(bounded, 0, 'f', 3),
                 &singleInputOk);
        inputOk = inputOk || singleInputOk;
        if (!singleInputOk) {
            qWarning() << "native system controls: sink-input volume write failed"
                       << "index" << index
                       << "percent" << bounded;
        }
    }
    if (!ok && !inputOk) {
        qWarning() << "native system controls: volume write failed" << bounded;
        return false;
    }
    m_volumeAvailable = true;
    m_cachedVolumePercent = bounded;
    qInfo() << "native system controls: volume write"
            << "route" << "pactl-fallback"
            << "sinkOk" << ok
            << "sinkInputOk" << inputOk
            << "sinkInputCount" << sinkInputs.size()
            << "percent" << bounded;
    emit changed();
    return true;
}

double SystemControls::brightnessPercent() {
    if (!brightnessAvailable())
        return m_cachedBrightnessPercent;
    const int value = readBrightnessValue();
    if (value >= 0)
        m_cachedBrightnessPercent = 100.0 * value / m_brightnessMaximum;
    return m_cachedBrightnessPercent;
}

double SystemControls::volumePercent() {
    bool ok = false;
    const double value = queryVolumePercent(&ok);
    if (ok) {
        m_volumeAvailable = true;
        m_cachedVolumePercent = value;
    }
    return m_cachedVolumePercent;
}

void SystemControls::beginPlaybackSession() {
    if (m_sessionActive)
        return;
    m_sessionActive = true;
    const int brightness = readBrightnessValue();
    m_savedBrightnessValid = brightness >= 0;
    m_savedBrightnessValue = brightness;
    bool volumeOk = false;
    const double volume = queryVolumePercent(&volumeOk);
    m_savedVolumeValid = volumeOk;
    m_savedVolumePercent = volume;
    if (m_savedBrightnessValid && m_brightnessMaximum > 0)
        m_cachedBrightnessPercent = 100.0 * brightness / m_brightnessMaximum;
    if (m_savedVolumeValid) {
        m_volumeAvailable = true;
        m_cachedVolumePercent = volume;
    }
    qInfo() << "native system controls: playback session saved"
            << "brightnessValid" << m_savedBrightnessValid
            << "brightness" << m_savedBrightnessValue
            << "brightnessMaximum" << m_brightnessMaximum
            << "volumeValid" << m_savedVolumeValid
            << "volumePercent" << m_savedVolumePercent;
    emit changed();
}

void SystemControls::restorePlaybackSession(const QString &reason) {
    if (!m_sessionActive)
        return;
    const bool brightnessRestored = m_savedBrightnessValid
            && writeBrightnessValue(m_savedBrightnessValue);
    const bool volumeRestored = m_savedVolumeValid
            && writeVolumePercent(m_savedVolumePercent);
    qInfo() << "native system controls: playback session restored"
            << "reason" << reason
            << "brightnessRestored" << brightnessRestored
            << "volumeRestored" << volumeRestored
            << "brightnessTarget" << m_savedBrightnessValue
            << "volumeTarget" << m_savedVolumePercent;
    m_sessionActive = false;
    m_savedBrightnessValid = false;
    m_savedVolumeValid = false;
    refresh();
}

bool SystemControls::setBrightnessPercent(double percent) {
    if (!m_sessionActive)
        beginPlaybackSession();
    if (!brightnessAvailable()) {
        qWarning() << "native system controls: brightness unavailable";
        return false;
    }
    const int value = m_brightnessUsesMce
            ? qBound(1, qRound(percent), 100)
            : qBound(1, qRound(m_brightnessMaximum
                               * qBound(0.0, percent, 100.0) / 100.0),
                     m_brightnessMaximum);
    if (writeBrightnessValue(value)) {
        qInfo() << "native system controls: brightness changed"
                << "percent" << qRound(m_cachedBrightnessPercent)
                << "raw" << value
                << "maximum" << m_brightnessMaximum;
        return true;
    }
    return false;
}

bool SystemControls::setVolumePercent(double percent) {
    if (!m_sessionActive)
        beginPlaybackSession();
    if (writeVolumePercent(qBound(0.0, percent, 100.0))) {
        qInfo() << "native system controls: volume changed"
                << "percent" << qRound(m_cachedVolumePercent);
        return true;
    }
    return false;
}

void SystemControls::refresh() {
    brightnessPercent();
    volumePercent();
    emit changed();
}
