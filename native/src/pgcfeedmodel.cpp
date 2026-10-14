#include "pgcfeedmodel.h"
#include "networkutils.h"

#include "accountservice.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

namespace {
QString formatCount(qint64 value) {
    if (value >= 100000000)
        return QString::number(value / 100000000.0, 'f', value >= 1000000000 ? 1 : 2)
                + QStringLiteral("亿");
    if (value >= 10000)
        return QString::number(value / 10000.0, 'f', value >= 100000 ? 1 : 2)
                + QStringLiteral("万");
    return QString::number(value);
}

QString normalizedHttps(QString value) {
    return value.replace(QStringLiteral("http://"), QStringLiteral("https://"));
}
}

PgcFeedModel::PgcFeedModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false), m_hasMore(false),
      m_category(QStringLiteral("bangumi_rank")), m_requestGeneration(0) {}

int PgcFeedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant PgcFeedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case DescriptionRole: return item.description;
    case CoverRole: return item.cover;
    case SeasonIdRole: return item.seasonId;
    case BadgeRole: return item.badge;
    case SectionRole: return item.section;
    default: return QVariant();
    }
}

QHash<int, QByteArray> PgcFeedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[DescriptionRole] = "descriptionText";
    roles[CoverRole] = "cover";
    roles[SeasonIdRole] = "seasonId";
    roles[BadgeRole] = "badge";
    roles[SectionRole] = "sectionTitle";
    return roles;
}

QString PgcFeedModel::feedTitle() const {
    if (m_category == QStringLiteral("bangumi_rank")) return tr("追番热搜榜");
    return m_category == QStringLiteral("cinema") ? tr("影视") : tr("番剧");
}

QString PgcFeedModel::signatureFor(const QVector<Item> &items) const {
    QStringList seasonIds;
    seasonIds.reserve(items.size());
    for (const Item &item : items) seasonIds.append(item.seasonId);
    return seasonIds.join(QStringLiteral(","));
}

void PgcFeedModel::showBangumiRank() {
    selectCategory(QStringLiteral("bangumi_rank"));
}

void PgcFeedModel::showBangumi() {
    selectCategory(QStringLiteral("bangumi"));
}

void PgcFeedModel::showCinema() {
    selectCategory(QStringLiteral("cinema"));
}

void PgcFeedModel::refresh() {
    // Pull-down refresh is the one explicit user action that asks the service
    // to rotate recommendation content. Category selection must not do this.
    refreshInternal(true);
}

void PgcFeedModel::cancelActiveRequest() {
    ++m_requestGeneration;
    if (m_reply) {
        // A category selection is authoritative. Do not let a slower response
        // replace the list after the user has moved to another category.
        m_reply->abort();
        m_reply->deleteLater();
        m_reply.clear();
    }
}

void PgcFeedModel::clearCurrentState(bool keepRows) {
    // Keep the loading latch raised while the old rows are reset. Otherwise a
    // ListView already positioned at the end can re-enter loadMore() between
    // clearing the cursor and starting the replacement request.
    m_loading = true;
    m_cursor.clear();
    m_seen.clear();
    m_initialSignature.clear();
    m_hasMore = true;
    m_error.clear();
    if (!keepRows && !m_items.isEmpty()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
    }
}

void PgcFeedModel::storeCurrentSnapshot() {
    CategorySnapshot snapshot;
    snapshot.items = m_items;
    snapshot.seen = m_seen;
    snapshot.cursor = m_cursor;
    snapshot.error = m_error;
    snapshot.initialSignature = m_initialSignature;
    snapshot.hasMore = m_hasMore;
    snapshot.valid = true;
    m_snapshots.insert(m_category, snapshot);
    qInfo() << "native pgc consistency: snapshot stored"
            << "category" << m_category << "items" << m_items.size()
            << "initialSignature" << m_initialSignature
            << "cursor" << m_cursor << "hasMore" << m_hasMore;
}

bool PgcFeedModel::restoreSnapshot(const QString &category) {
    const QHash<QString, CategorySnapshot>::const_iterator it =
            m_snapshots.constFind(category);
    if (it == m_snapshots.constEnd() || !it.value().valid) return false;

    const CategorySnapshot snapshot = it.value();
    m_loading = true;
    beginResetModel();
    m_items = snapshot.items;
    endResetModel();
    m_seen = snapshot.seen;
    m_cursor = snapshot.cursor;
    m_error = snapshot.error;
    m_initialSignature = snapshot.initialSignature;
    m_hasMore = snapshot.hasMore;
    m_loading = false;
    qInfo() << "native pgc consistency: snapshot restored"
            << "category" << category << "items" << m_items.size()
            << "initialSignature" << m_initialSignature
            << "cursor" << m_cursor << "hasMore" << m_hasMore;
    emit stateChanged();
    return true;
}

void PgcFeedModel::selectCategory(const QString &category) {
    if (category != QStringLiteral("bangumi_rank")
            && category != QStringLiteral("bangumi")
            && category != QStringLiteral("cinema")) return;
    if (category == m_category && (m_loading || !m_items.isEmpty())) return;

    const QString previousCategory = m_category;
    cancelActiveRequest();
    m_category = category;
    qInfo() << "native pgc consistency: category selected"
            << "from" << previousCategory << "to" << m_category;
    if (restoreSnapshot(m_category)) return;

    clearCurrentState();
    qInfo() << "native pgc consistency: snapshot miss"
            << "category" << m_category;
    emit stateChanged();
    m_loading = false;
    request(true, false);
}

void PgcFeedModel::refreshInternal(bool rotateContent) {
    cancelActiveRequest();
    // An explicit pull-down refresh is the only operation that replaces the
    // current page-lifetime snapshot. Other categories remain intact.
    m_snapshots.remove(m_category);
    clearCurrentState(true);
    qInfo() << "native pgc consistency: explicit refresh"
            << "category" << m_category
            << "rotateContent" << rotateContent
            << "generation" << m_requestGeneration;
    emit stateChanged();
    m_loading = false;
    request(true, rotateContent);
}

void PgcFeedModel::loadMore() {
    if (m_loading || !m_hasMore || !m_error.isEmpty()) return;
    if (m_category != QStringLiteral("bangumi_rank") && m_cursor.isEmpty()) {
        // Model resets can briefly report atYEnd. Pagination is only valid
        // after the initial response has atomically published its cursor.
        qWarning() << "native pgc consistency: pagination blocked"
                   << "category" << m_category
                   << "reason" << "cursor-not-published";
        return;
    }
    request(false, false);
}

void PgcFeedModel::request(bool reset, bool rotateContent) {
    if (m_category == QStringLiteral("bangumi_rank")) {
        requestRank(reset, rotateContent);
        return;
    }
    requestTab(reset, rotateContent);
}

void PgcFeedModel::requestRank(bool reset, bool rotateContent) {
    if (m_loading) return;
    m_loading = true;
    m_error.clear();
    emit stateChanged();

    QUrl url(QStringLiteral("https://api.bilibili.com/pgc/web/rank/list"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("season_type"), QStringLiteral("1"));
    query.addQueryItem(QStringLiteral("day"), QStringLiteral("3"));
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/anime/");
    request.setRawHeader("Accept-Encoding", "identity");
    AccountService *account = AccountService::instance();
    if (account && !account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", account->cookieHeader());

    const int generation = m_requestGeneration;
    const QString requestedCategory = m_category;
    qInfo() << "native pgc consistency: request started"
            << "category" << requestedCategory << "reset" << reset
            << "rotateContent" << rotateContent
            << "cursor" << QString() << "generation" << generation;
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation, requestedCategory]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool current = generation == m_requestGeneration
                             && requestedCategory == m_category && m_reply == reply;
        reply->deleteLater();
        if (!current) {
            qInfo() << "native pgc consistency: stale response ignored"
                    << "category" << requestedCategory
                    << "generation" << generation
                    << "currentCategory" << m_category
                    << "currentGeneration" << m_requestGeneration;
            return;
        }
        m_reply.clear();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_loading = false;
            m_error = tr("追番热搜榜请求失败");
            emit stateChanged();
            return;
        }

        QJsonObject dataObject = root.value(QStringLiteral("result")).toObject();
        if (dataObject.isEmpty())
            dataObject = root.value(QStringLiteral("data")).toObject();

        QVector<Item> nextItems;
        const QJsonArray list = dataObject.value(QStringLiteral("list")).toArray();
        QSet<QString> seen;
        for (const QJsonValue &itemValue : list) {
            const QJsonObject object = itemValue.toObject();
            const QString seasonId = QString::number(static_cast<qint64>(
                object.value(QStringLiteral("season_id")).toDouble()));
            if (seasonId.isEmpty() || seasonId == QStringLiteral("0") || seen.contains(seasonId))
                continue;

            Item item;
            item.title = object.value(QStringLiteral("title")).toString();
            item.cover = normalizedHttps(object.value(QStringLiteral("cover")).toString());
            item.seasonId = seasonId;
            const int rank = object.value(QStringLiteral("rank")).toInt(nextItems.size() + 1);
            item.section = tr("热搜榜 #%1").arg(rank);
            item.badge = object.value(QStringLiteral("new_ep")).toObject()
                         .value(QStringLiteral("index_show")).toString();
            if (item.badge.isEmpty())
                item.badge = object.value(QStringLiteral("badge")).toString();

            QStringList descriptionParts;
            const QString desc = object.value(QStringLiteral("desc")).toString();
            const QString rating = object.value(QStringLiteral("rating")).toString();
            if (!rating.isEmpty()) descriptionParts.append(rating);
            if (!desc.isEmpty()) descriptionParts.append(desc);
            const QJsonObject stat = object.value(QStringLiteral("stat")).toObject();
            const qint64 view = static_cast<qint64>(stat.value(QStringLiteral("view")).toDouble());
            const qint64 follow = static_cast<qint64>(stat.value(QStringLiteral("follow")).toDouble());
            if (view > 0) descriptionParts.append(tr("播放 %1").arg(formatCount(view)));
            if (follow > 0) descriptionParts.append(tr("追番 %1").arg(formatCount(follow)));
            item.description = descriptionParts.join(QStringLiteral(" · "));

            if (item.title.isEmpty()) continue;
            nextItems.append(item);
            seen.insert(seasonId);
        }

        beginResetModel();
        m_items = nextItems;
        m_seen = seen;
        m_initialSignature = signatureFor(nextItems);
        endResetModel();
        m_cursor.clear();
        m_hasMore = false;
        if (m_items.isEmpty()) m_error = tr("暂无追番热搜内容");
        // Publish loading=false only after the model and pagination state are
        // committed. This prevents ListView reset signals from re-entering
        // loadMore() with a stale cursor.
        m_loading = false;
        storeCurrentSnapshot();
        qInfo() << "native pgc consistency: response committed"
                << "category" << m_category << "reset" << true
                << "items" << m_items.size()
                << "firstSeasonId" << firstSeasonId()
                << "initialSignature" << m_initialSignature
                << "cursor" << m_cursor << "hasMore" << m_hasMore
                << "generation" << generation;
        qInfo() << "native pgc: bangumi rank shown" << m_items.size();
        emit stateChanged();
    });
}

void PgcFeedModel::requestTab(bool reset, bool rotateContent) {
    if (m_loading) return;
    m_loading = true;
    m_error.clear();
    emit stateChanged();

    QUrl url(QStringLiteral("https://api.bilibili.com/pgc/page/pc/")
             + m_category + QStringLiteral("/tab"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("is_refresh"), rotateContent
                       ? QStringLiteral("1") : QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("cursor"), m_cursor);
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    AccountService *account = AccountService::instance();
    if (account && !account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", account->cookieHeader());

    const int generation = m_requestGeneration;
    const QString requestedCategory = m_category;
    const QString requestedCursor = m_cursor;
    qInfo() << "native pgc consistency: request started"
            << "category" << requestedCategory << "reset" << reset
            << "rotateContent" << rotateContent
            << "cursor" << requestedCursor << "generation" << generation;
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, reset, rotateContent, generation, requestedCategory, requestedCursor]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool current = generation == m_requestGeneration
                             && requestedCategory == m_category && m_reply == reply;
        reply->deleteLater();
        if (!current) {
            qInfo() << "native pgc consistency: stale response ignored"
                    << "category" << requestedCategory
                    << "generation" << generation
                    << "currentCategory" << m_category
                    << "currentGeneration" << m_requestGeneration;
            return;
        }
        m_reply.clear();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_loading = false;
            m_error = tr("番剧影视内容请求失败");
            emit stateChanged();
            return;
        }

        const QJsonObject dataObject = root.value(QStringLiteral("data")).toObject();
        QVector<Item> nextItems;
        const QJsonArray modules = dataObject.value(QStringLiteral("modules")).toArray();
        for (const QJsonValue &moduleValue : modules) {
            const QJsonObject module = moduleValue.toObject();
            const QString section = module.value(QStringLiteral("title")).toString();
            for (const QJsonValue &itemValue : module.value(QStringLiteral("items")).toArray()) {
                const QJsonObject object = itemValue.toObject();
                const QString seasonId = QString::number(static_cast<qint64>(
                    object.value(QStringLiteral("season_id")).toDouble()));
                if (seasonId.isEmpty() || seasonId == QStringLiteral("0") || m_seen.contains(seasonId)) continue;
                Item item;
                item.title = object.value(QStringLiteral("title")).toString();
                item.description = object.value(QStringLiteral("desc")).toString();
                item.cover = normalizedHttps(object.value(QStringLiteral("cover")).toString());
                item.seasonId = seasonId;
                item.section = section;
                item.badge = object.value(QStringLiteral("new_ep")).toObject()
                             .value(QStringLiteral("index_show")).toString();
                if (item.badge.isEmpty())
                    item.badge = object.value(QStringLiteral("bottom_right_badge")).toObject()
                                 .value(QStringLiteral("text")).toString();
                if (item.title.isEmpty()) continue;
                nextItems.append(item);
                m_seen.insert(seasonId);
            }
        }

        if (reset) {
            beginResetModel();
            m_items = nextItems;
            m_initialSignature = signatureFor(nextItems);
            endResetModel();
        } else if (!nextItems.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + nextItems.size() - 1);
            m_items += nextItems;
            endInsertRows();
        }
        m_cursor = dataObject.value(QStringLiteral("next_cursor")).toString();
        m_hasMore = dataObject.value(QStringLiteral("has_next")).toInt() != 0
                    && !m_cursor.isEmpty();
        if (m_items.isEmpty()) m_error = tr("暂无番剧影视内容");
        // Keep the loading latch through begin/endResetModel and pagination
        // publication so atYEnd cannot start a request with the previous
        // category's empty cursor.
        m_loading = false;
        storeCurrentSnapshot();
        qInfo() << "native pgc consistency: response committed"
                << "category" << m_category << "reset" << reset
                << "rotateContent" << rotateContent
                << "items" << m_items.size()
                << "firstSeasonId" << firstSeasonId()
                << "initialSignature" << m_initialSignature
                << "requestedCursor" << requestedCursor
                << "cursor" << m_cursor << "hasMore" << m_hasMore
                << "generation" << generation;
        qInfo() << "native pgc:" << m_category << "added" << nextItems.size()
                << "shown" << m_items.size() << "hasMore" << m_hasMore;
        emit stateChanged();
    });
}
