#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>
#include <QUrl>

namespace MediaUrlSelector {

inline bool ordinaryHttps(const QString &text) {
    const QUrl url(text);
    const QString host = url.host().toLower();
    return url.isValid() && !host.isEmpty() && url.scheme() == QStringLiteral("https")
            && url.port(443) == 443
            && !host.contains(QStringLiteral(".mcdn."))
            && !host.endsWith(QStringLiteral(".edge.mountaintoys.cn"));
}

inline QString primary(const QJsonObject &media) {
    QString primary = media.value(QStringLiteral("base_url")).toString();
    if (primary.isEmpty()) primary = media.value(QStringLiteral("baseUrl")).toString();
    if (primary.isEmpty()) primary = media.value(QStringLiteral("url")).toString();
    return primary;
}

inline QString select(const QJsonObject &media) {
    const QString primary = MediaUrlSelector::primary(media);
    // Keep an ordinary primary CDN in place. Only deprioritize peer/custom-port
    // endpoints when the SAME track offers an ordinary HTTPS backup. Never
    // rewrite signed URLs, synthesize hosts, or change the selected rendition.
    if (ordinaryHttps(primary)) return primary;
    QStringList backups;
    const char *keys[] = {"backup_url", "backupUrl"};
    for (const char *key : keys) {
        const QJsonArray urls = media.value(QString::fromLatin1(key)).toArray();
        for (const QJsonValue &url : urls) {
            const QString text = url.toString();
            if (!text.isEmpty()) backups.append(text);
        }
    }
    for (const QString &backup : backups)
        if (ordinaryHttps(backup)) return backup;
    if (!primary.isEmpty()) return primary;
    return backups.isEmpty() ? QString() : backups.first();
}

}
