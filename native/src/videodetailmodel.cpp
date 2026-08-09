#include "videodetailmodel.h"
#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

VideoDetailModel::VideoDetailModel(QObject *parent) : QObject(parent), m_loading(false) {}

void VideoDetailModel::load(const QString &bvid) {
    if (bvid.isEmpty() || m_loading) return;
    m_bvid = bvid; m_loading = true; m_errorMessage.clear();
    m_firstCid.clear(); m_pages.clear(); emit changed();

    // The full view payload is needed for the detail page, but first playback
    // only needs a cid. Fetch the small page list in parallel and publish its
    // first cid immediately so decoder startup does not wait for descriptions,
    // statistics and all other detail fields.
    QUrl pagesUrl(QStringLiteral("https://api.bilibili.com/x/player/pagelist"));
    QUrlQuery pagesQuery;
    pagesQuery.addQueryItem(QStringLiteral("bvid"), bvid);
    pagesUrl.setQuery(pagesQuery);
    QNetworkRequest pagesRequest(pagesUrl);
    pagesRequest.setRawHeader("User-Agent", "silisili-native/1.1 SailfishOS");
    pagesRequest.setRawHeader("Referer", "https://www.bilibili.com/");
    pagesRequest.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *pagesReply = m_network.get(pagesRequest);
    NetworkUtils::setReplyTimeout(pagesReply, 7000);
    connect(pagesReply, &QNetworkReply::finished, this,
            [this, pagesReply, bvid]() {
        const QByteArray payload = pagesReply->readAll();
        const bool ok = pagesReply->error() == QNetworkReply::NoError;
        pagesReply->deleteLater();
        if (m_bvid != bvid || !ok || !m_firstCid.isEmpty()) return;
        const QJsonObject root = QJsonDocument::fromJson(payload).object();
        if (root.value(QStringLiteral("code")).toInt(-1) != 0) return;
        QVariantList earlyPages;
        QString earlyCid;
        for (const QJsonValue &value : root.value(QStringLiteral("data")).toArray()) {
            const QJsonObject object = value.toObject();
            const QString cid = QString::number(static_cast<qint64>(
                            object.value(QStringLiteral("cid")).toDouble()));
            if (cid == QStringLiteral("0")) continue;
            QVariantMap item;
            item.insert(QStringLiteral("cid"), cid);
            item.insert(QStringLiteral("title"), object.value(QStringLiteral("part")).toString());
            item.insert(QStringLiteral("page"), object.value(QStringLiteral("page")).toInt());
            earlyPages.append(item);
            if (earlyCid.isEmpty()) earlyCid = cid;
        }
        if (earlyCid.isEmpty()) return;
        m_firstCid = earlyCid;
        m_pages = earlyPages;
        qInfo() << "native detail perf: early cid ready"
                << "parts" << m_pages.size();
        emit changed();
    });

    QUrl url(QStringLiteral("https://api.bilibili.com/x/web-interface/view")); QUrlQuery query;
    query.addQueryItem(QStringLiteral("bvid"), bvid); url.setQuery(query);
    QNetworkRequest request(url); request.setRawHeader("User-Agent", "silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/"); request.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 9000);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = reply->readAll(); const auto networkError = reply->error(); reply->deleteLater(); m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_errorMessage = NetworkUtils::replyTimedOut(reply)
                    ? tr("详情请求超时，请重试") : tr("详情请求失败");
            emit changed(); return;
        }
        QJsonParseError error; const QJsonObject root = QJsonDocument::fromJson(payload, &error).object();
        if (error.error != QJsonParseError::NoError || root.value("code").toDouble(-1) != 0) { m_errorMessage = tr("详情解析失败"); emit changed(); return; }
        const QJsonObject data = root.value("data").toObject(); const QJsonObject owner = data.value("owner").toObject();
        const QJsonObject stat = data.value("stat").toObject(); m_title = data.value("title").toString();
        m_aid = QString::number(static_cast<qint64>(data.value("aid").toDouble()));
        m_owner = owner.value("name").toString();
        m_ownerMid = QString::number(static_cast<qint64>(owner.value("mid").toDouble()));
        if (m_ownerMid == QStringLiteral("0")) m_ownerMid.clear();
        m_cover = data.value("pic").toString().replace("http://", "https://");
        m_description = data.value("desc").toString();
        m_stats = tr("播放 %1 · 弹幕 %2 · 点赞 %3").arg(static_cast<qint64>(stat.value("view").toDouble()))
                  .arg(static_cast<qint64>(stat.value("danmaku").toDouble())).arg(static_cast<qint64>(stat.value("like").toDouble()));
        m_pages.clear(); m_firstCid.clear(); const QJsonArray pages = data.value("pages").toArray();
        for (const QJsonValue &value : pages) {
            const QJsonObject page = value.toObject(); QVariantMap item;
            const QString cid = QString::number(static_cast<qint64>(page.value("cid").toDouble()));
            item.insert(QStringLiteral("cid"), cid);
            item.insert(QStringLiteral("title"), page.value("part").toString());
            item.insert(QStringLiteral("page"), page.value("page").toInt());
            m_pages.append(item); if (m_firstCid.isEmpty()) m_firstCid = cid;
        }
        emit changed();
    });
}
