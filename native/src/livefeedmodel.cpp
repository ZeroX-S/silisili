#include "livefeedmodel.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

LiveFeedModel::LiveFeedModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false), m_hasMore(false),
      m_page(1), m_generation(0) {}

int LiveFeedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant LiveFeedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case RoomIdRole: return item.roomId;
    case TitleRole: return item.title;
    case OwnerRole: return item.owner;
    case CoverRole: return item.cover;
    case AreaRole: return item.area;
    case WatchedRole: return item.watched;
    default: return QVariant();
    }
}

QHash<int, QByteArray> LiveFeedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[RoomIdRole] = "roomId";
    roles[TitleRole] = "title";
    roles[OwnerRole] = "owner";
    roles[CoverRole] = "cover";
    roles[AreaRole] = "area";
    roles[WatchedRole] = "watched";
    return roles;
}

void LiveFeedModel::setLoading(bool value) {
    if (m_loading == value) return;
    m_loading = value;
    emit loadingChanged();
}

void LiveFeedModel::setErrorMessage(const QString &value) {
    if (m_errorMessage == value) return;
    m_errorMessage = value;
    emit errorMessageChanged();
}

void LiveFeedModel::setHasMore(bool value) {
    if (m_hasMore == value) return;
    m_hasMore = value;
    emit hasMoreChanged();
}

void LiveFeedModel::refresh() {
    ++m_generation;
    if (m_activeReply) {
        QNetworkReply *obsolete = m_activeReply.data();
        m_activeReply.clear();
        obsolete->abort();
        qInfo() << "native live feed: obsolete request cancelled for refresh";
    }
    setLoading(false);
    m_page = 1;
    m_seenRoomIds.clear();
    beginResetModel();
    m_items.clear();
    endResetModel();
    setHasMore(true);
    requestPage(true);
}

void LiveFeedModel::loadMore() {
    if (m_loading || !m_hasMore) return;
    requestPage(false);
}

void LiveFeedModel::requestPage(bool reset) {
    if (m_loading) return;
    setLoading(true);
    setErrorMessage(QString());

    // The old webMain endpoint returns only a small fixed recommendation
    // block. feedV2 is the real paginated source used upstream. Its app-style
    // query requires the legacy Bilibili signature: sort the encoded query,
    // then MD5(query + app secret).
    QMap<QString, QString> parameters;
    parameters.insert(QStringLiteral("appkey"), QStringLiteral("aa1e74ee4874176e"));
    parameters.insert(QStringLiteral("area_id"), QStringLiteral("0"));
    parameters.insert(QStringLiteral("build"), QStringLiteral("1001011000"));
    parameters.insert(QStringLiteral("device"), QStringLiteral("switch"));
    parameters.insert(QStringLiteral("mobi_app"), QStringLiteral("pc_electron"));
    parameters.insert(QStringLiteral("page"), QString::number(m_page));
    parameters.insert(QStringLiteral("parent_area_id"), QStringLiteral("0"));
    parameters.insert(QStringLiteral("platform"), QStringLiteral("web"));
    parameters.insert(QStringLiteral("scale"), QStringLiteral("xxhdpi"));
    parameters.insert(QStringLiteral("source_name"), QStringLiteral("pc"));
    parameters.insert(QStringLiteral("ts"), QString::number(QDateTime::currentMSecsSinceEpoch()));
    QByteArray encodedQuery;
    for (auto it = parameters.constBegin(); it != parameters.constEnd(); ++it) {
        if (!encodedQuery.isEmpty()) encodedQuery.append('&');
        encodedQuery.append(QUrl::toPercentEncoding(it.key()));
        encodedQuery.append('=');
        encodedQuery.append(QUrl::toPercentEncoding(it.value()));
    }
    const QByteArray signature = QCryptographicHash::hash(
                encodedQuery + QByteArrayLiteral("54e6a9a31b911cd5fc0daa66ebf94bc4"),
                QCryptographicHash::Md5).toHex();
    QUrl url(QStringLiteral("https://api.live.bilibili.com/xlive/app-interface/v2/index/feedV2"));
    url.setQuery(QString::fromLatin1(encodedQuery + QByteArrayLiteral("&sign=") + signature));
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://live.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    AccountService *account = AccountService::instance();
    if (account && !account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", account->cookieHeader());

    const int requestPage = m_page;
    const int generation = m_generation;
    QNetworkReply *reply = m_network.get(request);
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestPage, generation, reset]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        const bool networkChanged = NetworkUtils::replyNetworkChanged(reply);
        if (m_activeReply == reply) m_activeReply.clear();
        reply->deleteLater();
        if (generation != m_generation) return;
        setLoading(false);
        if (networkError != QNetworkReply::NoError) {
            setErrorMessage(networkChanged ? tr("网络已切换，请下拉重试")
                            : timedOut ? tr("直播列表请求超时，请下拉重试")
                                       : tr("直播列表请求失败"));
            qWarning() << "native live feed: request failed"
                       << "timeout" << timedOut
                       << "networkChanged" << networkChanged
                       << "error" << networkError;
            setHasMore(false);
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            setErrorMessage(tr("直播列表解析失败"));
            setHasMore(false);
            return;
        }

        QVector<Item> next;
        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        const QJsonArray cards = data.value(QStringLiteral("card_list")).toArray();
        for (const QJsonValue &value : cards) {
            const QJsonObject card = value.toObject();
            const QString cardType = card.value(QStringLiteral("card_type")).toString();
            const QJsonObject cardData = card.value(QStringLiteral("card_data")).toObject();
            if (cardType == QStringLiteral("my_idol_v1")) {
                const QJsonArray followed = cardData.value(cardType).toObject()
                        .value(QStringLiteral("list")).toArray();
                for (const QJsonValue &followedValue : followed) {
                    const QJsonObject object = followedValue.toObject();
                    const QString roomId = QString::number(static_cast<qint64>(
                        object.value(QStringLiteral("roomid")).toDouble(
                            object.value(QStringLiteral("id")).toDouble())));
                    if (roomId.isEmpty() || roomId == QStringLiteral("0")
                            || m_seenRoomIds.contains(roomId)) continue;
                    Item item;
                    item.roomId = roomId;
                    item.title = object.value(QStringLiteral("title")).toString();
                    item.owner = object.value(QStringLiteral("uname")).toString();
                    item.cover = object.value(QStringLiteral("cover")).toString()
                            .replace(QStringLiteral("http://"), QStringLiteral("https://"));
                    item.area = object.value(QStringLiteral("area_name")).toString();
                    item.watched = tr("已关注");
                    if (!item.title.isEmpty()) {
                        m_seenRoomIds.insert(roomId);
                        next.append(item);
                    }
                }
                continue;
            }
            if (cardType != QStringLiteral("small_card_v1")
                    && cardType != QStringLiteral("second_card_v1")) continue;
            const QJsonObject object = cardData.value(cardType).toObject();
            Item item;
            item.roomId = QString::number(static_cast<qint64>(
                object.value(QStringLiteral("roomid")).toDouble(
                    object.value(QStringLiteral("id")).toDouble())));
            if (item.roomId == QStringLiteral("0") || m_seenRoomIds.contains(item.roomId)) continue;
            item.title = object.value(QStringLiteral("title")).toString();
            item.owner = object.value(QStringLiteral("uname")).toString();
            item.cover = object.value(QStringLiteral("cover")).toString().replace(QStringLiteral("http://"), QStringLiteral("https://"));
            if (item.cover.isEmpty())
                item.cover = object.value(QStringLiteral("keyframe")).toString().replace(QStringLiteral("http://"), QStringLiteral("https://"));
            item.area = object.value(QStringLiteral("area_name")).toString();
            item.watched = object.value(QStringLiteral("watched_show")).toObject()
                               .value(QStringLiteral("text_large")).toString();
            if (!item.roomId.isEmpty() && !item.title.isEmpty()) {
                m_seenRoomIds.insert(item.roomId);
                next.append(item);
            }
        }

        if (reset) {
            beginResetModel();
            m_items = next;
            endResetModel();
        } else if (!next.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + next.size() - 1);
            m_items += next;
            endInsertRows();
        }
        const bool hasMore = data.value(QStringLiteral("has_more")).toInt() != 0
                && !next.isEmpty();
        setHasMore(hasMore);
        if (hasMore) m_page = requestPage + 1;
        qInfo() << "native live feed: page ready"
                << "page" << requestPage << "added" << next.size()
                << "total" << m_items.size() << "hasMore" << hasMore;
        if (m_items.isEmpty()) setErrorMessage(tr("当前没有可显示的直播"));
    });
}
