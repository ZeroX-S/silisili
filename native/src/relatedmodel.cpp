#include "relatedmodel.h"

#include "networkutils.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

RelatedModel::RelatedModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false) {}

int RelatedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant RelatedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case OwnerRole: return item.owner;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case PlayRole: return item.play;
    default: return QVariant();
    }
}

QHash<int, QByteArray> RelatedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[OwnerRole] = "owner";
    roles[CoverRole] = "cover";
    roles[BvidRole] = "bvid";
    roles[PlayRole] = "playCount";
    return roles;
}

QVariantMap RelatedModel::get(int row) const {
    QVariantMap result;
    if (row < 0 || row >= m_items.size()) return result;
    const Item &item = m_items.at(row);
    result.insert(QStringLiteral("title"), item.title);
    result.insert(QStringLiteral("owner"), item.owner);
    result.insert(QStringLiteral("cover"), item.cover);
    result.insert(QStringLiteral("bvid"), item.bvid);
    result.insert(QStringLiteral("playCount"), item.play);
    return result;
}

void RelatedModel::load(const QString &bvid) {
    if (bvid.isEmpty() || m_loading || (m_bvid == bvid && !m_items.isEmpty()))
        return;
    m_bvid = bvid;
    m_loading = true;
    emit stateChanged();

    QUrl url(QStringLiteral("https://api.bilibili.com/x/web-interface/archive/related"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("bvid"), bvid);
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, bvid]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            if (m_bvid == bvid) m_bvid.clear();
            emit stateChanged();
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toDouble(-1) != 0) {
            if (m_bvid == bvid) m_bvid.clear();
            emit stateChanged();
            return;
        }

        QVector<Item> next;
        const QJsonArray data = root.value(QStringLiteral("data")).toArray();
        for (const QJsonValue &value : data) {
            const QJsonObject object = value.toObject();
            const QJsonObject owner = object.value(QStringLiteral("owner")).toObject();
            const QJsonObject stat = object.value(QStringLiteral("stat")).toObject();
            Item item;
            item.title = object.value(QStringLiteral("title")).toString();
            item.owner = owner.value(QStringLiteral("name")).toString();
            item.cover = object.value(QStringLiteral("pic")).toString()
                    .replace(QStringLiteral("http://"), QStringLiteral("https://"));
            item.bvid = object.value(QStringLiteral("bvid")).toString();
            item.play = QString::number(static_cast<qint64>(
                                           stat.value(QStringLiteral("view")).toDouble()));
            if (!item.bvid.isEmpty()) next.append(item);
        }
        beginResetModel();
        m_items = next;
        endResetModel();
        emit stateChanged();
    });
}
