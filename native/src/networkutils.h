#pragma once

#include <QString>
#include <QUrl>

class QJsonObject;
class QNetworkReply;

namespace NetworkUtils {

// Qt 5.6 has no transfer timeout on QNetworkRequest. Abort a reply after a
// bounded interval and mark it so callers can distinguish a timeout from an
// ordinary cancellation.
void setReplyTimeout(QNetworkReply *reply, int timeoutMs = 12000);
bool replyTimedOut(const QNetworkReply *reply);

// Bilibili's space and high-quality player endpoints require a WBI signature.
// The mixin key is derived from /x/web-interface/nav and remains valid for the
// current application session.
QString wbiMixinKey(const QJsonObject &navData);
QUrl signWbiUrl(const QUrl &url, const QString &mixinKey);

}
