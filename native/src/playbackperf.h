#pragma once

#include <QFile>
#include <QString>
#include <chrono>
#include <mutex>

// Deterministic device probes cannot rely on journald retaining every message
// while other services flood its ring buffer. This sink is inactive in normal
// launches and records only explicit timing/state markers, never media URLs.
namespace PlaybackPerf {
inline void record(const QString &message) {
    static const QString path = []() {
        if (qgetenv("SILISILI_NATIVE_TEST_PAGE").isEmpty()) return QString();
        const QString value = QString::fromLocal8Bit(qgetenv("SILISILI_NATIVE_TEST_PERF_LOG"));
        const QString prefix = QStringLiteral("/tmp/silisili-perf-native-");
        if (!value.startsWith(prefix) || !value.endsWith(QStringLiteral(".log")))
            return QString();
        const QString name = value.mid(prefix.size(), value.size() - prefix.size() - 4);
        if (name.isEmpty()) return QString();
        for (const QChar c : name)
            if (!c.isLetterOrNumber() && c != QLatin1Char('_') && c != QLatin1Char('-'))
                return QString();
        return value;
    }();
    if (path.isEmpty()) return;
    static std::mutex mutex;
    std::lock_guard<std::mutex> lock(mutex);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append)) return;
    file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
    const qint64 us = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
    file.write((QStringLiteral("[%1] ").arg(us / 1000000.0, 0, 'f', 6)
                + message + QLatin1Char('\n')).toUtf8());
}
}
