#include "dynamicfeedmodel.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

DynamicFeedModel::DynamicFeedModel(AccountService *account, QObject *parent)
    : QAbstractListModel(parent), m_account(account), m_loading(false), m_hasMore(false),
      m_generation(0), m_section(QStringLiteral("all")) {}

int DynamicFeedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant DynamicFeedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case AuthorRole: return item.author;
    case AvatarRole: return item.avatar;
    case TextRole: return item.text;
    case TitleRole: return item.title;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case TimeRole: return item.time;
    case KindRole: return item.kind;
    case SourceRole: return item.source;
    case ImageUrlsRole: return item.imageUrls;
    case SeasonIdRole: return item.seasonId;
    case RoomIdRole: return item.roomId;
    case StatsRole: return item.stats;
    case DynamicIdRole: return item.dynamicId;
    case CommentOidRole: return item.commentOid;
    case CommentTypeRole: return item.commentType;
    default: return QVariant();
    }
}

QHash<int, QByteArray> DynamicFeedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[AuthorRole] = "author";
    roles[AvatarRole] = "avatar";
    roles[TextRole] = "bodyText";
    roles[TitleRole] = "mediaTitle";
    roles[CoverRole] = "mediaCover";
    roles[BvidRole] = "bvid";
    roles[TimeRole] = "publishTime";
    roles[KindRole] = "kindLabel";
    roles[SourceRole] = "sourceText";
    roles[ImageUrlsRole] = "imageUrls";
    roles[SeasonIdRole] = "seasonId";
    roles[RoomIdRole] = "roomId";
    roles[StatsRole] = "statsText";
    roles[DynamicIdRole] = "dynamicId";
    roles[CommentOidRole] = "commentOid";
    roles[CommentTypeRole] = "commentType";
    return roles;
}

QString DynamicFeedModel::normalizedUrl(const QString &url) {
    QString result = url;
    if (result.startsWith(QStringLiteral("//"))) result.prepend(QStringLiteral("https:"));
    return result.replace(QStringLiteral("http://"), QStringLiteral("https://"));
}

QString DynamicFeedModel::jsonId(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isDouble()) return QString::number(static_cast<qint64>(value.toDouble()));
    return QString();
}

void DynamicFeedModel::parseMajor(const QJsonObject &major, Item *item) {
    if (!item || major.isEmpty()) return;

    const QJsonObject archive = major.value(QStringLiteral("archive")).toObject();
    if (!archive.isEmpty()) {
        item->kind = tr("视频");
        item->bvid = archive.value(QStringLiteral("bvid")).toString();
        item->title = archive.value(QStringLiteral("title")).toString();
        item->cover = normalizedUrl(archive.value(QStringLiteral("cover")).toString());
        if (item->text.isEmpty()) item->text = archive.value(QStringLiteral("desc")).toString();
        return;
    }

    const QJsonObject draw = major.value(QStringLiteral("draw")).toObject();
    if (!draw.isEmpty()) {
        item->kind = tr("图文");
        for (const QJsonValue &value : draw.value(QStringLiteral("items")).toArray()) {
            const QString url = normalizedUrl(value.toObject().value(QStringLiteral("src")).toString());
            if (!url.isEmpty() && item->imageUrls.size() < 9) item->imageUrls.append(url);
        }
        return;
    }

    const QJsonObject opus = major.value(QStringLiteral("opus")).toObject();
    if (!opus.isEmpty()) {
        item->kind = tr("图文");
        const QJsonObject summary = opus.value(QStringLiteral("summary")).toObject();
        if (item->text.isEmpty()) item->text = summary.value(QStringLiteral("text")).toString();
        item->title = opus.value(QStringLiteral("title")).toString();
        for (const QJsonValue &value : opus.value(QStringLiteral("pics")).toArray()) {
            const QJsonObject picture = value.toObject();
            QString url = picture.value(QStringLiteral("url")).toString();
            if (url.isEmpty()) url = picture.value(QStringLiteral("src")).toString();
            url = normalizedUrl(url);
            if (!url.isEmpty() && item->imageUrls.size() < 9) item->imageUrls.append(url);
        }
        return;
    }

    const QJsonObject article = major.value(QStringLiteral("article")).toObject();
    if (!article.isEmpty()) {
        item->kind = tr("专栏");
        item->title = article.value(QStringLiteral("title")).toString();
        if (item->text.isEmpty()) item->text = article.value(QStringLiteral("desc")).toString();
        for (const QJsonValue &value : article.value(QStringLiteral("covers")).toArray()) {
            QString url = value.isString() ? value.toString()
                                           : value.toObject().value(QStringLiteral("url")).toString();
            url = normalizedUrl(url);
            if (!url.isEmpty() && item->imageUrls.size() < 3) item->imageUrls.append(url);
        }
        return;
    }

    const QJsonObject pgc = major.value(QStringLiteral("pgc")).toObject();
    if (!pgc.isEmpty()) {
        item->kind = tr("番剧");
        item->seasonId = jsonId(pgc.value(QStringLiteral("season_id")));
        item->title = pgc.value(QStringLiteral("title")).toString();
        item->cover = normalizedUrl(pgc.value(QStringLiteral("cover")).toString());
        return;
    }

    const QJsonObject liveRcmd = major.value(QStringLiteral("live_rcmd")).toObject();
    if (!liveRcmd.isEmpty()) {
        QJsonParseError parseError;
        const QJsonObject card = QJsonDocument::fromJson(
            liveRcmd.value(QStringLiteral("content")).toString().toUtf8(), &parseError).object();
        const QJsonObject live = card.value(QStringLiteral("live_play_info")).toObject();
        if (parseError.error == QJsonParseError::NoError && !live.isEmpty()) {
            item->kind = tr("直播");
            item->roomId = jsonId(live.value(QStringLiteral("room_id")));
            item->title = live.value(QStringLiteral("title")).toString();
            item->cover = normalizedUrl(live.value(QStringLiteral("cover")).toString());
            const QString area = live.value(QStringLiteral("parent_area_name")).toString()
                                 + QStringLiteral(" · ")
                                 + live.value(QStringLiteral("area_name")).toString();
            if (item->source.isEmpty()) item->source = area;
        }
        return;
    }

    const QJsonObject common = major.value(QStringLiteral("common")).toObject();
    if (!common.isEmpty()) {
        item->kind = tr("动态");
        item->title = common.value(QStringLiteral("title")).toString();
        item->cover = normalizedUrl(common.value(QStringLiteral("cover")).toString());
        if (item->text.isEmpty()) item->text = common.value(QStringLiteral("desc")).toString();
    }
}

void DynamicFeedModel::parseOriginal(const QJsonObject &original, Item *item) {
    if (!item || original.isEmpty()) return;
    const QJsonObject modules = original.value(QStringLiteral("modules")).toObject();
    const QJsonObject author = modules.value(QStringLiteral("module_author")).toObject();
    const QJsonObject dynamic = modules.value(QStringLiteral("module_dynamic")).toObject();
    const QString originalAuthor = author.value(QStringLiteral("name")).toString();
    const QString originalText = dynamic.value(QStringLiteral("desc")).toObject()
                                 .value(QStringLiteral("text")).toString();
    item->source = originalAuthor.isEmpty() ? tr("原动态") : tr("转发自 @%1").arg(originalAuthor);
    if (!originalText.isEmpty()) item->source += QStringLiteral("：") + originalText;
    parseMajor(dynamic.value(QStringLiteral("major")).toObject(), item);
    item->kind = tr("转发");
}

void DynamicFeedModel::setSection(const QString &section) {
    const QString normalized = section == QStringLiteral("video")
            || section == QStringLiteral("nonvideo") ? section : QStringLiteral("all");
    if (m_section == normalized) return;
    // The model is shared by the two dynamics pages. Invalidate any reply
    // still completing for the previous section before the new page refreshes.
    // Otherwise a late video reply can append into the non-video model.
    ++m_generation;
    if (m_activeReply) {
        QNetworkReply *obsolete = m_activeReply.data();
        m_activeReply.clear();
        obsolete->abort();
    }
    m_section = normalized;
    m_loading = false;
    m_hasMore = true;
    m_offset.clear();
    m_seen.clear();
    m_errorMessage.clear();
    if (!m_items.isEmpty()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
    }
    emit stateChanged();
}

void DynamicFeedModel::refresh() {
    ++m_generation;
    if (m_activeReply) {
        QNetworkReply *obsolete = m_activeReply.data();
        m_activeReply.clear();
        obsolete->abort();
        qInfo() << "native dynamic: obsolete request cancelled for refresh";
    }
    m_loading = false;
    m_offset.clear();
    m_seen.clear();
    m_hasMore = true;
    m_errorMessage.clear();
    if (!m_items.isEmpty()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
    }
    request(true);
}

void DynamicFeedModel::loadMore() {
    if (!m_loading && m_hasMore) request(false);
}

void DynamicFeedModel::request(bool reset) {
    if (m_loading) return;
    if (!m_account || m_account->cookieHeader().isEmpty()) {
        m_errorMessage = tr("登录后才能查看动态");
        emit stateChanged();
        return;
    }

    m_loading = true;
    m_errorMessage.clear();
    emit stateChanged();

    const int requestGeneration = m_generation;
    const QString requestSection = m_section;

    QUrl url(QStringLiteral("https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all"));
    QUrlQuery query;
    if (requestSection == QStringLiteral("video"))
        query.addQueryItem(QStringLiteral("type"), QStringLiteral("video"));
    if (!reset && !m_offset.isEmpty())
        query.addQueryItem(QStringLiteral("offset"), m_offset);
    if (!query.isEmpty())
        url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://t.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Cookie", m_account->cookieHeader());

    QNetworkReply *reply = m_network.get(request);
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, reset, requestGeneration, requestSection]() {
        const QByteArray payload = reply->readAll();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        const bool networkChanged = NetworkUtils::replyNetworkChanged(reply);
        const QNetworkReply::NetworkError networkError = reply->error();
        if (m_activeReply == reply) m_activeReply.clear();
        reply->deleteLater();
        if (requestGeneration != m_generation || requestSection != m_section) {
            qInfo() << "native dynamic: stale reply ignored section" << requestSection
                    << "generation" << requestGeneration << "current" << m_generation;
            return;
        }
        m_loading = false;

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            const int code = root.value(QStringLiteral("code")).toInt(-1);
            m_errorMessage = networkChanged ? tr("网络已切换，请下拉重试")
                             : timedOut ? tr("动态请求超时，请下拉重试")
                                        : tr("动态请求失败或登录已过期");
            qWarning() << "native dynamic: request failed section" << requestSection
                       << "timeout" << timedOut << "networkChanged" << networkChanged
                       << "network" << networkError
                       << "code" << code;
            emit stateChanged();
            return;
        }

        const QJsonObject dataObject = root.value(QStringLiteral("data")).toObject();
        QVector<Item> nextItems;
        for (const QJsonValue &value : dataObject.value(QStringLiteral("items")).toArray()) {
            const QJsonObject object = value.toObject();
            Item item;
            const QString dynamicType = object.value(QStringLiteral("type")).toString();
            if (requestSection == QStringLiteral("nonvideo")
                    && dynamicType == QStringLiteral("DYNAMIC_TYPE_AV")) continue;
            if (requestSection == QStringLiteral("video")
                    && dynamicType != QStringLiteral("DYNAMIC_TYPE_AV")) continue;
            item.dynamicId = jsonId(object.value(QStringLiteral("id_str")));
            if (item.dynamicId.isEmpty()) item.dynamicId = jsonId(object.value(QStringLiteral("id")));
            if (!item.dynamicId.isEmpty() && m_seen.contains(item.dynamicId)) continue;

            const QJsonObject modules = object.value(QStringLiteral("modules")).toObject();
            const QJsonObject author = modules.value(QStringLiteral("module_author")).toObject();
            const QJsonObject dynamic = modules.value(QStringLiteral("module_dynamic")).toObject();
            item.author = author.value(QStringLiteral("name")).toString();
            item.avatar = normalizedUrl(author.value(QStringLiteral("face")).toString());
            item.time = author.value(QStringLiteral("pub_time")).toString();
            item.text = dynamic.value(QStringLiteral("desc")).toObject()
                        .value(QStringLiteral("text")).toString();
            const QJsonObject basic = object.value(QStringLiteral("basic")).toObject();
            item.commentOid = jsonId(basic.value(QStringLiteral("comment_id_str")));
            item.commentType = basic.value(QStringLiteral("comment_type")).toInt(17);
            parseMajor(dynamic.value(QStringLiteral("major")).toObject(), &item);

            if (dynamicType == QStringLiteral("DYNAMIC_TYPE_FORWARD"))
                parseOriginal(object.value(QStringLiteral("orig")).toObject(), &item);

            const QJsonObject stat = modules.value(QStringLiteral("module_stat")).toObject();
            QStringList stats;
            const int forwardCount = stat.value(QStringLiteral("forward")).toObject()
                                     .value(QStringLiteral("count")).toInt();
            const int commentCount = stat.value(QStringLiteral("comment")).toObject()
                                     .value(QStringLiteral("count")).toInt();
            const int likeCount = stat.value(QStringLiteral("like")).toObject()
                                  .value(QStringLiteral("count")).toInt();
            if (forwardCount > 0) stats.append(tr("转发 %1").arg(forwardCount));
            if (commentCount > 0) stats.append(tr("评论 %1").arg(commentCount));
            if (likeCount > 0) stats.append(tr("赞 %1").arg(likeCount));
            item.stats = stats.join(QStringLiteral("  ·  "));

            if (item.kind.isEmpty()) item.kind = tr("动态");
            if (item.author.isEmpty()) continue;
            if (item.text.isEmpty() && item.title.isEmpty() && item.imageUrls.isEmpty())
                item.text = tr("发布了一条动态");
            nextItems.append(item);
            if (!item.dynamicId.isEmpty()) m_seen.insert(item.dynamicId);
        }

        if (reset) {
            beginResetModel();
            m_items = nextItems;
            endResetModel();
        } else if (!nextItems.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + nextItems.size() - 1);
            m_items += nextItems;
            endInsertRows();
        }

        m_offset = dataObject.value(QStringLiteral("offset")).toString();
        const QJsonValue hasMoreValue = dataObject.value(QStringLiteral("has_more"));
        m_hasMore = hasMoreValue.isBool() ? hasMoreValue.toBool() : hasMoreValue.toInt() != 0;
        if (m_offset.isEmpty()) m_hasMore = false;
        if (m_items.isEmpty()) m_errorMessage = tr("暂时没有可显示的动态");
        qInfo() << "native dynamic: section" << requestSection
                << "added" << nextItems.size() << "shown" << m_items.size()
                << "hasMore" << m_hasMore << "offset" << !m_offset.isEmpty();
        emit stateChanged();
    });
}
