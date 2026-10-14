#include "bilibiliimagenetwork.h"
#include "networkutils.h"

#include <QDebug>
#include <QDir>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QUrl>

namespace {
bool isBilibiliImageHost(const QString &host)
{
    return host == QStringLiteral("hdslb.com")
            || host.endsWith(QStringLiteral(".hdslb.com"))
            || host == QStringLiteral("biliimg.com")
            || host.endsWith(QStringLiteral(".biliimg.com"));
}
}

BilibiliImageNetworkAccessManager::BilibiliImageNetworkAccessManager(QObject *parent)
    : QNetworkAccessManager(parent)
{
    QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cacheRoot.isEmpty()) cacheRoot = QDir::tempPath() + QStringLiteral("/silisili-native");
    const QString cachePath = cacheRoot + QStringLiteral("/qml-images");
    QDir().mkpath(cachePath);
    QNetworkDiskCache *diskCache = new QNetworkDiskCache(this);
    diskCache->setCacheDirectory(cachePath);
    diskCache->setMaximumCacheSize(32 * 1024 * 1024);
    setCache(diskCache);

    connect(this, &QNetworkAccessManager::finished, this, [](QNetworkReply *reply) {
        if (!reply || !isBilibiliImageHost(reply->url().host())) return;
        // Virtualized delegates routinely cancel an image when it leaves the
        // cache viewport. Logging every cancellation makes fast scrolling
        // compete with journald. Keep genuine timeouts/bearer failures visible.
        if (reply->error() == QNetworkReply::OperationCanceledError
                && !NetworkUtils::replyTimedOut(reply)
                && !NetworkUtils::replyNetworkChanged(reply)) return;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::NoError && status >= 200 && status < 400)
            return;
        qWarning() << "native image: CDN request failed"
                   << "host" << reply->url().host()
                   << "status" << status
                   << "error" << reply->error();
    });
}

QNetworkReply *BilibiliImageNetworkAccessManager::createRequest(
        Operation operation, const QNetworkRequest &original, QIODevice *outgoingData)
{
    QNetworkRequest request(original);
    if (isBilibiliImageHost(request.url().host())) {
        request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
        request.setRawHeader("Referer", "https://www.bilibili.com/");
        request.setRawHeader("Accept-Encoding", "identity");
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                             QNetworkRequest::PreferCache);
        request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, true);
    }
    QNetworkReply *reply = QNetworkAccessManager::createRequest(
                operation, request, outgoingData);
    if (isBilibiliImageHost(request.url().host()))
        NetworkUtils::setReplyTimeout(reply, 8000);
    return reply;
}

QNetworkAccessManager *BilibiliImageNetworkFactory::create(QObject *parent)
{
    return new BilibiliImageNetworkAccessManager(parent);
}
