#include "configmigration.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>

QString ConfigMigration::migrateStableConfig() {
    QString configRoot = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (configRoot.isEmpty())
        configRoot = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    const QString stable = configRoot + QStringLiteral("/silisili/silisili_config.json");
    const QString nativeDir = configRoot + QStringLiteral("/cn.silisili.native");
    const QString legacyNativeDir = configRoot + QStringLiteral("/silisili-native");
    const QString snapshot = nativeDir + QStringLiteral("/stable_config_snapshot.json");
    const QString legacySnapshot = legacyNativeDir + QStringLiteral("/stable_config_snapshot.json");
    if (!QFile::exists(snapshot) && QFile::exists(stable)) {
        QDir().mkpath(nativeDir);
        if (!QFile::copy(stable, snapshot)) return QStringLiteral("copy-failed");
        QFile::setPermissions(snapshot, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        return QStringLiteral("copied");
    }
    if (!QFile::exists(snapshot) && QFile::exists(legacySnapshot)) {
        QDir().mkpath(nativeDir);
        if (!QFile::copy(legacySnapshot, snapshot)) return QStringLiteral("copy-failed");
        QFile::setPermissions(snapshot, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        return QStringLiteral("legacy-copied");
    }
    return QFile::exists(snapshot) ? QStringLiteral("present") : QStringLiteral("none");
}
