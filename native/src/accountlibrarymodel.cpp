#include "accountlibrarymodel.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

AccountLibraryModel::AccountLibraryModel(QObject *parent)
    : QAbstractListModel(parent),
      m_account(AccountService::instance()),
      m_collectionType(1),
      m_loading(false),
      m_hasMore(false),
      m_totalCount(0),
      m_page(1),
      m_historyMax(0),
      m_historyViewAt(0),
      m_generation(0) {}

int AccountLibraryModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant AccountLibraryModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case SubtitleRole: return item.subtitle;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case CidRole: return item.cid;
    case SeasonIdRole: return item.seasonId;
    case EpisodeIdRole: return item.episodeId;
    case RoomIdRole: return item.roomId;
    case FolderIdRole: return item.folderId;
    case FolderTypeRole: return item.folderType;
    case BadgeRole: return item.badge;
    case ProgressTextRole: return item.progressText;
    case ProgressRatioRole: return item.progressRatio;
    case ResumePositionRole: return item.resumePosition;
    case KindRole: return item.kind;
    case OwnerRole: return item.owner;
    case CanOpenRole: return item.canOpen;
    default: return QVariant();
    }
}

QHash<int, QByteArray> AccountLibraryModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[SubtitleRole] = "subtitle";
    roles[CoverRole] = "cover";
    roles[BvidRole] = "bvid";
    roles[CidRole] = "cid";
    roles[SeasonIdRole] = "seasonId";
    roles[EpisodeIdRole] = "episodeId";
    roles[RoomIdRole] = "roomId";
    roles[FolderIdRole] = "folderId";
    roles[FolderTypeRole] = "folderType";
    roles[BadgeRole] = "badge";
    roles[ProgressTextRole] = "progressText";
    roles[ProgressRatioRole] = "progressRatio";
    roles[ResumePositionRole] = "resumePosition";
    roles[KindRole] = "kindLabel";
    roles[OwnerRole] = "owner";
    roles[CanOpenRole] = "canOpen";
    return roles;
}

void AccountLibraryModel::setMode(const QString &mode) {
    const QString next = mode.trimmed();
    if (m_mode == next) return;
    m_mode = next;
    emit configurationChanged();
}

void AccountLibraryModel::setCollectionId(const QString &collectionId) {
    if (m_collectionId == collectionId) return;
    m_collectionId = collectionId;
    emit configurationChanged();
}

void AccountLibraryModel::setCollectionType(int collectionType) {
    const int next = collectionType == 2 ? 2 : 1;
    if (m_collectionType == next) return;
    m_collectionType = next;
    emit configurationChanged();
}

QString AccountLibraryModel::jsonId(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isDouble()) return QString::number(static_cast<qint64>(value.toDouble()));
    return QString();
}

QString AccountLibraryModel::normalizedUrl(QString value) {
    if (value.startsWith(QStringLiteral("//"))) value.prepend(QStringLiteral("https:"));
    return value.replace(QStringLiteral("http://"), QStringLiteral("https://"));
}

QString AccountLibraryModel::formatDuration(int seconds) {
    if (seconds < 0) return QString();
    const int hours = seconds / 3600;
    const int minutes = (seconds % 3600) / 60;
    const int remaining = seconds % 60;
    if (hours > 0)
        return QStringLiteral("%1:%2:%3").arg(hours).arg(minutes, 2, 10, QLatin1Char('0'))
                .arg(remaining, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(minutes).arg(remaining, 2, 10, QLatin1Char('0'));
}

QString AccountLibraryModel::formatDate(qint64 epochSeconds) {
    if (epochSeconds <= 0) return QString();
    return QDateTime::fromMSecsSinceEpoch(epochSeconds * 1000).toLocalTime()
            .toString(QStringLiteral("MM-dd hh:mm"));
}

QString AccountLibraryModel::formatCount(qint64 count) {
    if (count >= 100000000) return QString::number(count / 100000000.0, 'f', 1) + tr("亿");
    if (count >= 10000) return QString::number(count / 10000.0, 'f', count >= 100000 ? 1 : 2) + tr("万");
    return QString::number(qMax<qint64>(0, count));
}

QNetworkRequest AccountLibraryModel::requestFor(const QUrl &url) const {
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    if (m_account && !m_account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", m_account->cookieHeader());
    return request;
}

void AccountLibraryModel::refresh() {
    ++m_generation;
    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply.clear();
    }
    // A superseded reply ignores its old generation. Clear its loading latch
    // before issuing the replacement request.
    m_loading = false;
    m_page = 1;
    m_historyMax = 0;
    m_historyViewAt = 0;
    m_historyBusiness.clear();
    m_hasMore = true;
    m_totalCount = 0;
    m_errorMessage.clear();
    const AccountService *account = AccountService::instance();
    const QString identity = (account ? account->userId() : QString())
            + QLatin1Char('/') + m_mode + QLatin1Char('/') + m_collectionId
            + QLatin1Char('/') + QString::number(m_collectionType);
    if (identity != m_displayedIdentity || !account || !account->hasSessionCredentials()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
    }
    m_displayedIdentity = identity;
    emit stateChanged();
    request(true);
}

void AccountLibraryModel::loadMore() {
    if (m_loading || !m_hasMore || !m_errorMessage.isEmpty()) return;
    request(false);
}

void AccountLibraryModel::request(bool reset) {
    if (m_loading || m_mode.isEmpty()) return;
    m_account = AccountService::instance();
    if (!m_account || m_account->cookieHeader().isEmpty()
            || m_account->userId().isEmpty()) {
        m_hasMore = false;
        m_errorMessage = tr("请先登录账户后查看个人内容");
        emit stateChanged();
        return;
    }

    QUrl url;
    QUrlQuery query;
    if (m_mode == QStringLiteral("history")) {
        url = QUrl(QStringLiteral("https://api.bilibili.com/x/web-interface/history/cursor"));
        query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
        query.addQueryItem(QStringLiteral("max"), QString::number(m_historyMax));
        query.addQueryItem(QStringLiteral("view_at"), QString::number(m_historyViewAt));
        query.addQueryItem(QStringLiteral("business"), m_historyBusiness);
    } else if (m_mode == QStringLiteral("favorites") || m_mode == QStringLiteral("subscriptions")) {
        url = QUrl(m_mode == QStringLiteral("favorites")
                   ? QStringLiteral("https://api.bilibili.com/x/v3/fav/folder/created/list")
                   : QStringLiteral("https://api.bilibili.com/x/v3/fav/folder/collected/list"));
        query.addQueryItem(QStringLiteral("platform"), m_mode == QStringLiteral("favorites")
                           ? QStringLiteral("pc") : QStringLiteral("web"));
        query.addQueryItem(QStringLiteral("up_mid"), m_account->userId());
        query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
        query.addQueryItem(QStringLiteral("pn"), QString::number(m_page));
    } else if (m_mode == QStringLiteral("anime") || m_mode == QStringLiteral("cinema")) {
        url = QUrl(QStringLiteral("https://api.bilibili.com/x/space/bangumi/follow/list"));
        query.addQueryItem(QStringLiteral("vmid"), m_account->userId());
        query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
        query.addQueryItem(QStringLiteral("pn"), QString::number(m_page));
        query.addQueryItem(QStringLiteral("type"), m_mode == QStringLiteral("anime")
                           ? QStringLiteral("1") : QStringLiteral("2"));
        query.addQueryItem(QStringLiteral("platform"), QStringLiteral("web"));
        query.addQueryItem(QStringLiteral("follow_status"), QStringLiteral("0"));
    } else if (m_mode == QStringLiteral("later")) {
        url = QUrl(QStringLiteral("https://api.bilibili.com/x/v2/history/toview/web"));
    } else if (m_mode == QStringLiteral("collection")) {
        if (m_collectionId.isEmpty()) {
            m_hasMore = false;
            m_errorMessage = tr("收藏夹参数不完整");
            emit stateChanged();
            return;
        }
        url = QUrl(m_collectionType == 2
                   ? QStringLiteral("https://api.bilibili.com/x/space/fav/season/list")
                   : QStringLiteral("https://api.bilibili.com/x/v3/fav/resource/list"));
        query.addQueryItem(m_collectionType == 2 ? QStringLiteral("season_id")
                                                 : QStringLiteral("media_id"), m_collectionId);
        query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
        query.addQueryItem(QStringLiteral("pn"), QString::number(m_page));
        query.addQueryItem(QStringLiteral("platform"), QStringLiteral("web"));
    } else {
        m_hasMore = false;
        m_errorMessage = tr("不支持的个人内容类型");
        emit stateChanged();
        return;
    }
    url.setQuery(query);

    const int generation = m_generation;
    qInfo() << "native account library: request"
            << "mode" << m_mode << "generation" << generation
            << "sessionReady" << !m_account->cookieHeader().isEmpty();
    m_loading = true;
    m_errorMessage.clear();
    emit stateChanged();
    QNetworkReply *reply = m_network.get(requestFor(url));
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation, reset]() {
        const QByteArray body = reply->readAll();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        if (m_activeReply == reply) m_activeReply.clear();
        if (generation != m_generation) return;
        m_loading = false;
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(body, &parseError).object();
        const int code = root.value(QStringLiteral("code")).toInt(-1);
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError || code != 0) {
            const QString serverMessage = root.value(QStringLiteral("message")).toString();
            m_errorMessage = timedOut ? tr("个人内容请求超时，请下拉重试")
                                      : serverMessage.isEmpty()
                                        ? tr("个人内容请求失败，请下拉重试") : serverMessage;
            m_hasMore = false;
            qWarning() << "native account library: request failed" << m_mode
                       << "network" << networkError << "timeout" << timedOut
                       << "code" << code << m_errorMessage;
            emit stateChanged();
            return;
        }

        const QJsonObject dataObject = root.value(QStringLiteral("data")).toObject();
        const QVector<Item> parsed = parseItems(dataObject, reset);
        if (reset) {
            beginResetModel();
            m_items = parsed;
            endResetModel();
        } else if (!parsed.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + parsed.size() - 1);
            m_items += parsed;
            endInsertRows();
        }
        if (m_totalCount <= 0) m_totalCount = m_items.size();
        qInfo() << "native account library: ready"
                << "mode" << m_mode << "items" << m_items.size()
                << "page" << m_page << "total" << m_totalCount
                << "hasMore" << m_hasMore;
        emit stateChanged();
    });
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseItems(const QJsonObject &data, bool reset) {
    Q_UNUSED(reset)
    if (m_mode == QStringLiteral("history")) return parseHistory(data);
    if (m_mode == QStringLiteral("favorites")) return parseFolders(data, false);
    if (m_mode == QStringLiteral("subscriptions")) return parseFolders(data, true);
    if (m_mode == QStringLiteral("anime") || m_mode == QStringLiteral("cinema")) return parseBangumi(data);
    if (m_mode == QStringLiteral("later")) return parseLater(data);
    if (m_mode == QStringLiteral("collection")) return parseCollection(data);
    m_hasMore = false;
    return QVector<Item>();
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseHistory(const QJsonObject &data) {
    QVector<Item> result;
    const QJsonArray list = data.value(QStringLiteral("list")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject object = value.toObject();
        const QJsonObject history = object.value(QStringLiteral("history")).toObject();
        Item item;
        item.title = object.value(QStringLiteral("title")).toString();
        const QJsonArray covers = object.value(QStringLiteral("covers")).toArray();
        item.cover = normalizedUrl(covers.isEmpty() ? object.value(QStringLiteral("cover")).toString()
                                                    : covers.first().toString());
        item.owner = object.value(QStringLiteral("author_name")).toString();
        const QString showTitle = object.value(QStringLiteral("show_title")).toString();
        item.subtitle = item.owner;
        if (!showTitle.isEmpty()) item.subtitle += (item.subtitle.isEmpty() ? QString() : QStringLiteral(" · ")) + showTitle;
        const QString date = formatDate(static_cast<qint64>(object.value(QStringLiteral("view_at")).toDouble()));
        if (!date.isEmpty()) item.subtitle += (item.subtitle.isEmpty() ? QString() : QStringLiteral(" · ")) + date;
        const int duration = object.value(QStringLiteral("duration")).toInt(-1);
        const int progress = object.value(QStringLiteral("progress")).toInt(-2);
        item.resumePosition = progress >= 0 ? progress : 0.0;
        if (progress == -1) {
            item.progressText = tr("已看完");
            item.progressRatio = 1.0;
        } else if (progress >= 0 && duration > 0) {
            item.progressText = tr("%1 / %2").arg(formatDuration(progress), formatDuration(duration));
            item.progressRatio = qBound<qreal>(0.0, progress / qreal(duration), 1.0);
        }
        item.badge = object.value(QStringLiteral("badge")).toString();
        const QString business = history.value(QStringLiteral("business")).toString();
        item.cid = jsonId(history.value(QStringLiteral("cid")));
        if (business == QStringLiteral("archive")) {
            item.kind = tr("视频");
            item.bvid = history.value(QStringLiteral("bvid")).toString();
        } else if (business == QStringLiteral("pgc")) {
            item.kind = tr("番剧");
            item.episodeId = jsonId(history.value(QStringLiteral("epid")));
        } else if (business == QStringLiteral("live")) {
            item.kind = tr("直播");
            if (object.value(QStringLiteral("live_status")).toInt() == 1)
                item.roomId = jsonId(history.value(QStringLiteral("oid")));
            else if (item.badge.isEmpty()) item.badge = tr("未开播");
        } else if (business.startsWith(QStringLiteral("article"))) {
            item.kind = tr("专栏");
        } else {
            item.kind = business;
        }
        item.canOpen = !item.bvid.isEmpty() || !item.episodeId.isEmpty() || !item.roomId.isEmpty();
        result.append(item);
    }
    const QJsonObject cursor = data.value(QStringLiteral("cursor")).toObject();
    m_historyMax = static_cast<qint64>(cursor.value(QStringLiteral("max")).toDouble());
    m_historyViewAt = static_cast<qint64>(cursor.value(QStringLiteral("view_at")).toDouble());
    m_historyBusiness = cursor.value(QStringLiteral("business")).toString();
    m_hasMore = !list.isEmpty() && m_historyViewAt > 0;
    m_totalCount = m_items.size() + result.size() + (m_hasMore ? 1 : 0);
    return result;
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseFolders(const QJsonObject &data, bool subscriptions) {
    QVector<Item> result;
    const QJsonArray list = data.value(QStringLiteral("list")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject object = value.toObject();
        const QJsonObject upper = object.value(QStringLiteral("upper")).toObject();
        Item item;
        item.title = object.value(QStringLiteral("title")).toString();
        item.cover = normalizedUrl(object.value(QStringLiteral("cover")).toString());
        item.folderId = jsonId(object.value(QStringLiteral("id")));
        const int apiType = object.value(QStringLiteral("type")).toInt();
        item.folderType = subscriptions && apiType == 21 ? 2 : 1;
        item.owner = upper.value(QStringLiteral("name")).toString();
        const int count = object.value(QStringLiteral("media_count")).toInt();
        item.subtitle = tr("%1 个视频").arg(count);
        if (!item.owner.isEmpty()) item.subtitle += QStringLiteral(" · ") + item.owner;
        item.kind = subscriptions ? (item.folderType == 2 ? tr("订阅合集") : tr("订阅收藏夹"))
                                  : tr("我的收藏夹");
        item.badge = subscriptions ? QString() : ((object.value(QStringLiteral("attr")).toInt() & 1)
                                                   ? tr("私密") : tr("公开"));
        item.canOpen = !item.folderId.isEmpty();
        result.append(item);
    }
    m_totalCount = data.value(QStringLiteral("count")).toInt(m_items.size() + result.size());
    m_hasMore = data.value(QStringLiteral("has_more")).toBool(false);
    if (m_hasMore) ++m_page;
    return result;
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseCollection(const QJsonObject &data) {
    QVector<Item> result;
    const QJsonArray list = data.value(QStringLiteral("medias")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject object = value.toObject();
        const QJsonObject upper = object.value(QStringLiteral("upper")).toObject();
        const QJsonObject countInfo = object.value(QStringLiteral("cnt_info")).toObject();
        Item item;
        item.title = object.value(QStringLiteral("title")).toString();
        item.cover = normalizedUrl(object.value(QStringLiteral("cover")).toString());
        item.bvid = object.value(QStringLiteral("bvid")).toString();
        if (item.bvid.isEmpty()) item.bvid = object.value(QStringLiteral("bv_id")).toString();
        const QJsonObject season = object.value(QStringLiteral("season")).toObject();
        item.seasonId = jsonId(season.value(QStringLiteral("season_id")));
        item.owner = upper.value(QStringLiteral("name")).toString();
        item.subtitle = item.owner;
        const qint64 plays = static_cast<qint64>(countInfo.value(QStringLiteral("play")).toDouble());
        if (plays > 0) item.subtitle += (item.subtitle.isEmpty() ? QString() : QStringLiteral(" · "))
                                      + tr("播放 %1").arg(formatCount(plays));
        const int duration = object.value(QStringLiteral("duration")).toInt(-1);
        item.progressText = duration >= 0 ? formatDuration(duration) : QString();
        item.kind = m_collectionType == 2 ? tr("订阅合集") : tr("收藏视频");
        item.canOpen = !item.bvid.isEmpty() || !item.seasonId.isEmpty();
        result.append(item);
    }
    m_hasMore = m_collectionType == 1 && data.value(QStringLiteral("has_more")).toBool(false);
    if (m_hasMore) ++m_page;
    const QJsonObject info = data.value(QStringLiteral("info")).toObject();
    m_totalCount = info.value(QStringLiteral("media_count")).toInt(m_items.size() + result.size());
    return result;
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseBangumi(const QJsonObject &data) {
    QVector<Item> result;
    const QJsonArray list = data.value(QStringLiteral("list")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject object = value.toObject();
        Item item;
        item.title = object.value(QStringLiteral("season_title")).toString();
        if (item.title.isEmpty()) item.title = object.value(QStringLiteral("title")).toString();
        item.cover = normalizedUrl(object.value(QStringLiteral("cover")).toString());
        item.seasonId = jsonId(object.value(QStringLiteral("season_id")));
        item.subtitle = object.value(QStringLiteral("progress")).toString();
        if (item.subtitle.isEmpty()) item.subtitle = object.value(QStringLiteral("renewal_time")).toString();
        if (item.subtitle.isEmpty()) item.subtitle = object.value(QStringLiteral("evaluate")).toString();
        item.badge = object.value(QStringLiteral("badge")).toString();
        if (item.badge.isEmpty())
            item.badge = object.value(QStringLiteral("new_ep")).toObject()
                    .value(QStringLiteral("index_show")).toString();
        item.kind = m_mode == QStringLiteral("anime") ? tr("追番") : tr("追剧");
        item.canOpen = !item.seasonId.isEmpty();
        result.append(item);
    }
    m_totalCount = data.value(QStringLiteral("total")).toInt(m_items.size() + result.size());
    const int responsePage = data.value(QStringLiteral("pn")).toInt(m_page);
    const int pageSize = qMax(1, data.value(QStringLiteral("ps")).toInt(20));
    m_hasMore = responsePage * pageSize < m_totalCount;
    if (m_hasMore) m_page = responsePage + 1;
    return result;
}

QVector<AccountLibraryModel::Item> AccountLibraryModel::parseLater(const QJsonObject &data) {
    QVector<Item> result;
    const QJsonArray list = data.value(QStringLiteral("list")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject object = value.toObject();
        const QJsonObject owner = object.value(QStringLiteral("owner")).toObject();
        const QJsonObject stat = object.value(QStringLiteral("stat")).toObject();
        Item item;
        item.title = object.value(QStringLiteral("title")).toString();
        item.cover = normalizedUrl(object.value(QStringLiteral("pic")).toString());
        item.bvid = object.value(QStringLiteral("bvid")).toString();
        item.owner = owner.value(QStringLiteral("name")).toString();
        item.subtitle = item.owner;
        const qint64 plays = static_cast<qint64>(stat.value(QStringLiteral("view")).toDouble());
        if (plays > 0) item.subtitle += (item.subtitle.isEmpty() ? QString() : QStringLiteral(" · "))
                                      + tr("播放 %1").arg(formatCount(plays));
        const int duration = object.value(QStringLiteral("duration")).toInt(-1);
        const int progress = object.value(QStringLiteral("progress")).toInt(-1);
        item.progressText = progress >= 0 && duration > 0
                ? tr("%1 / %2").arg(formatDuration(progress), formatDuration(duration))
                : formatDuration(duration);
        item.progressRatio = progress >= 0 && duration > 0
                ? qBound<qreal>(0.0, progress / qreal(duration), 1.0) : -1.0;
        item.kind = tr("稍后再看");
        item.canOpen = !item.bvid.isEmpty();
        result.append(item);
    }
    m_totalCount = data.value(QStringLiteral("count")).toInt(result.size());
    m_hasMore = false;
    return result;
}
