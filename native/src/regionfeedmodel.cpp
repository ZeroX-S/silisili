#include "regionfeedmodel.h"

#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

RegionFeedModel::RegionFeedModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false), m_generation(0) {}

int RegionFeedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant RegionFeedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case OwnerRole: return item.owner;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case PlayRole: return item.play;
    case DanmakuRole: return item.danmaku;
    default: return QVariant();
    }
}

QHash<int, QByteArray> RegionFeedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[OwnerRole] = "owner";
    roles[CoverRole] = "cover";
    roles[BvidRole] = "bvid";
    roles[PlayRole] = "playCount";
    roles[DanmakuRole] = "danmakuCount";
    return roles;
}

void RegionFeedModel::load(int regionId, const QString &title) {
    if (regionId <= 0) return;

    ++m_generation;
    const int generation = m_generation;
    if (m_reply) m_reply->abort();
    m_reply.clear();

    m_loading = true;
    m_title = title;
    m_errorMessage.clear();
    beginResetModel();
    m_items.clear();
    endResetModel();
    emit stateChanged();

    QUrl url(QStringLiteral("https://api.bilibili.com/x/web-interface/ranking/region"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("rid"), QString::number(regionId));
    query.addQueryItem(QStringLiteral("day"), QStringLiteral("3"));
    query.addQueryItem(QStringLiteral("original"), QStringLiteral("0"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *reply = m_network.get(request);
    m_reply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, generation, regionId]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        if (m_reply == reply) m_reply.clear();
        reply->deleteLater();
        if (generation != m_generation) {
            qInfo() << "native region: stale response ignored"
                    << "region" << regionId << "generation" << generation
                    << "current" << m_generation;
            return;
        }

        m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_errorMessage = timedOut ? tr("分区内容请求超时") : tr("分区内容请求失败");
            emit stateChanged();
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toDouble(-1) != 0) {
            m_errorMessage = tr("分区内容解析失败");
            emit stateChanged();
            return;
        }

        QVector<Item> next;
        const QJsonArray list = root.value(QStringLiteral("data")).toArray();
        for (const QJsonValue &value : list) {
            const QJsonObject object = value.toObject();
            Item item;
            item.title = object.value(QStringLiteral("title")).toString();
            item.owner = object.value(QStringLiteral("author")).toString();
            item.cover = object.value(QStringLiteral("pic")).toString()
                    .replace(QStringLiteral("http://"), QStringLiteral("https://"));
            item.bvid = object.value(QStringLiteral("bvid")).toString();
            item.play = QString::number(static_cast<qint64>(
                                           object.value(QStringLiteral("play")).toDouble()));
            item.danmaku = QString::number(static_cast<qint64>(
                                              object.value(QStringLiteral("video_review")).toDouble()));
            if (!item.bvid.isEmpty()) next.append(item);
        }
        beginResetModel();
        m_items = next;
        endResetModel();
        if (m_items.isEmpty()) m_errorMessage = tr("该分区暂无内容");
        qInfo() << "native region: response committed"
                << "region" << regionId << "items" << m_items.size()
                << "generation" << generation;
        emit stateChanged();
    });
}
