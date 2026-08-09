#include "pgcdetailmodel.h"
#include "networkutils.h"

#include "accountservice.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

PgcDetailModel::PgcDetailModel(QObject *parent) : QObject(parent), m_loading(false) {}

void PgcDetailModel::load(const QString &seasonId) {
    loadById(QStringLiteral("season_id"), seasonId);
}

void PgcDetailModel::loadEpisode(const QString &episodeId) {
    loadById(QStringLiteral("ep_id"), episodeId);
}

void PgcDetailModel::loadById(const QString &queryKey, const QString &queryValue) {
    if (queryValue.isEmpty() || m_loading) return;
    m_seasonId = queryValue;
    m_loading = true;
    m_error.clear();
    emit changed();
    QUrl url(QStringLiteral("https://api.bilibili.com/pgc/view/web/season"));
    QUrlQuery query;
    query.addQueryItem(queryKey, queryValue);
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    AccountService *account = AccountService::instance();
    if (account && !account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", account->cookieHeader());
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        m_loading = false;
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_error = tr("番剧详情请求失败");
            emit changed();
            return;
        }
        const QJsonObject result = root.value(QStringLiteral("result")).toObject();
        m_title = result.value(QStringLiteral("season_title")).toString();
        m_cover = result.value(QStringLiteral("cover")).toString()
                  .replace(QStringLiteral("http://"), QStringLiteral("https://"));
        m_description = result.value(QStringLiteral("evaluate")).toString();
        const QJsonObject rating = result.value(QStringLiteral("rating")).toObject();
        m_ratingText = rating.isEmpty() ? QString() : tr("评分 %1 · %2 人")
                       .arg(rating.value(QStringLiteral("score")).toDouble(), 0, 'f', 1)
                       .arg(rating.value(QStringLiteral("count")).toInt());
        const QJsonObject stat = result.value(QStringLiteral("stat")).toObject();
        m_stats = tr("播放 %1 · 弹幕 %2 · 评论 %3")
                  .arg(QString::number(static_cast<qint64>(stat.value(QStringLiteral("views")).toDouble())))
                  .arg(QString::number(static_cast<qint64>(stat.value(QStringLiteral("danmakus")).toDouble())))
                  .arg(QString::number(static_cast<qint64>(stat.value(QStringLiteral("reply")).toDouble())));
        QVariantList episodes;
        for (const QJsonValue &value : result.value(QStringLiteral("episodes")).toArray()) {
            const QJsonObject episode = value.toObject();
            QVariantMap item;
            item.insert(QStringLiteral("epId"), QString::number(static_cast<qint64>(
                episode.value(QStringLiteral("id")).toDouble())));
            item.insert(QStringLiteral("aid"), QString::number(static_cast<qint64>(
                episode.value(QStringLiteral("aid")).toDouble())));
            item.insert(QStringLiteral("cid"), QString::number(static_cast<qint64>(
                episode.value(QStringLiteral("cid")).toDouble())));
            item.insert(QStringLiteral("bvid"), episode.value(QStringLiteral("bvid")).toString());
            const QString index = episode.value(QStringLiteral("title")).toString();
            const QString longTitle = episode.value(QStringLiteral("long_title")).toString();
            item.insert(QStringLiteral("title"), longTitle.isEmpty() ? tr("第 %1 话").arg(index)
                                                                     : tr("%1 · %2").arg(index).arg(longTitle));
            item.insert(QStringLiteral("cover"), episode.value(QStringLiteral("cover")).toString()
                        .replace(QStringLiteral("http://"), QStringLiteral("https://")));
            item.insert(QStringLiteral("duration"), episode.value(QStringLiteral("duration")).toInt() / 1000);
            if (!item.value(QStringLiteral("cid")).toString().isEmpty()) episodes.append(item);
        }
        m_episodes = episodes;
        if (m_episodes.isEmpty()) m_error = tr("没有可播放的分集");
        emit changed();
    });
}
