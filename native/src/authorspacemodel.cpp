#include "authorspacemodel.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

AuthorSpaceModel::AuthorSpaceModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false), m_pendingRequests(0), m_generation(0),
      m_videoPage(0), m_videoHasMore(false), m_dynamicHasMore(false) {}

int AuthorSpaceModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_videos.size() + m_dynamics.size();
}

QVariant AuthorSpaceModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) return QVariant();
    const bool video = index.row() < m_videos.size();
    if (role == EntryRole)
        return video ? m_videos.at(index.row()) : m_dynamics.at(index.row() - m_videos.size());
    if (role == KindRole) return video ? QStringLiteral("video") : QStringLiteral("dynamic");
    if (role == SectionRole) return video ? tr("最新作品") : tr("最新动态");
    return QVariant();
}

QHash<int, QByteArray> AuthorSpaceModel::roleNames() const {
    return {{EntryRole, "entryData"}, {KindRole, "entryKind"}, {SectionRole, "sectionTitle"}};
}

QString AuthorSpaceModel::normalizedUrl(QString value) {
    if (value.startsWith(QStringLiteral("//"))) value.prepend(QStringLiteral("https:"));
    return value.replace(QStringLiteral("http://"), QStringLiteral("https://"));
}

QString AuthorSpaceModel::formatCount(qint64 value) {
    if (value >= 100000000) return QString::number(value / 100000000.0, 'f', 1) + tr("亿");
    if (value >= 10000) return QString::number(value / 10000.0, 'f', value >= 100000 ? 1 : 2) + tr("万");
    return QString::number(value);
}

QString AuthorSpaceModel::jsonId(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isDouble()) return QString::number(static_cast<qint64>(value.toDouble()));
    return QString();
}

void AuthorSpaceModel::parseMajor(const QJsonObject &major, QVariantMap *item) {
    if (!item || major.isEmpty()) return;

    const QJsonObject archive = major.value(QStringLiteral("archive")).toObject();
    if (!archive.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("视频"));
        item->insert(QStringLiteral("bvid"), archive.value(QStringLiteral("bvid")).toString());
        item->insert(QStringLiteral("title"), archive.value(QStringLiteral("title")).toString());
        item->insert(QStringLiteral("cover"), normalizedUrl(archive.value(QStringLiteral("cover")).toString()));
        if (item->value(QStringLiteral("text")).toString().isEmpty())
            item->insert(QStringLiteral("text"), archive.value(QStringLiteral("desc")).toString());
        return;
    }

    QStringList pictures;
    const QJsonObject draw = major.value(QStringLiteral("draw")).toObject();
    if (!draw.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("图文"));
        for (const QJsonValue &value : draw.value(QStringLiteral("items")).toArray()) {
            const QString url = normalizedUrl(value.toObject().value(QStringLiteral("src")).toString());
            if (!url.isEmpty() && pictures.size() < 9) pictures.append(url);
        }
        item->insert(QStringLiteral("imageUrls"), pictures);
        return;
    }

    const QJsonObject opus = major.value(QStringLiteral("opus")).toObject();
    if (!opus.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("图文"));
        item->insert(QStringLiteral("title"), opus.value(QStringLiteral("title")).toString());
        const QString summary = opus.value(QStringLiteral("summary")).toObject()
                                .value(QStringLiteral("text")).toString();
        if (item->value(QStringLiteral("text")).toString().isEmpty())
            item->insert(QStringLiteral("text"), summary);
        for (const QJsonValue &value : opus.value(QStringLiteral("pics")).toArray()) {
            const QJsonObject picture = value.toObject();
            QString url = picture.value(QStringLiteral("url")).toString();
            if (url.isEmpty()) url = picture.value(QStringLiteral("src")).toString();
            url = normalizedUrl(url);
            if (!url.isEmpty() && pictures.size() < 9) pictures.append(url);
        }
        item->insert(QStringLiteral("imageUrls"), pictures);
        return;
    }

    const QJsonObject article = major.value(QStringLiteral("article")).toObject();
    if (!article.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("专栏"));
        item->insert(QStringLiteral("title"), article.value(QStringLiteral("title")).toString());
        if (item->value(QStringLiteral("text")).toString().isEmpty())
            item->insert(QStringLiteral("text"), article.value(QStringLiteral("desc")).toString());
        for (const QJsonValue &value : article.value(QStringLiteral("covers")).toArray()) {
            QString url = value.isString() ? value.toString()
                                           : value.toObject().value(QStringLiteral("url")).toString();
            url = normalizedUrl(url);
            if (!url.isEmpty() && pictures.size() < 3) pictures.append(url);
        }
        item->insert(QStringLiteral("imageUrls"), pictures);
        return;
    }

    const QJsonObject pgc = major.value(QStringLiteral("pgc")).toObject();
    if (!pgc.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("番剧"));
        item->insert(QStringLiteral("title"), pgc.value(QStringLiteral("title")).toString());
        item->insert(QStringLiteral("cover"), normalizedUrl(pgc.value(QStringLiteral("cover")).toString()));
        return;
    }

    const QJsonObject common = major.value(QStringLiteral("common")).toObject();
    if (!common.isEmpty()) {
        item->insert(QStringLiteral("kindLabel"), tr("动态"));
        item->insert(QStringLiteral("title"), common.value(QStringLiteral("title")).toString());
        item->insert(QStringLiteral("cover"), normalizedUrl(common.value(QStringLiteral("cover")).toString()));
        if (item->value(QStringLiteral("text")).toString().isEmpty())
            item->insert(QStringLiteral("text"), common.value(QStringLiteral("desc")).toString());
    }
}

void AuthorSpaceModel::parseOriginal(const QJsonObject &original, QVariantMap *item) {
    if (!item || original.isEmpty()) return;
    const QJsonObject modules = original.value(QStringLiteral("modules")).toObject();
    const QJsonObject author = modules.value(QStringLiteral("module_author")).toObject();
    const QJsonObject dynamic = modules.value(QStringLiteral("module_dynamic")).toObject();
    const QString originalAuthor = author.value(QStringLiteral("name")).toString();
    const QString originalText = dynamic.value(QStringLiteral("desc")).toObject()
                                 .value(QStringLiteral("text")).toString();
    QString source = originalAuthor.isEmpty() ? tr("原动态")
                                              : tr("转发自 @%1").arg(originalAuthor);
    if (!originalText.isEmpty()) source += QStringLiteral("：") + originalText;
    item->insert(QStringLiteral("source"), source);
    parseMajor(dynamic.value(QStringLiteral("major")).toObject(), item);
    item->insert(QStringLiteral("kindLabel"), tr("转发"));
}

QNetworkRequest AuthorSpaceModel::requestFor(const QUrl &url) const {
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://space.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    AccountService *account = AccountService::instance();
    if (account && !account->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", account->cookieHeader());
    return request;
}

void AuthorSpaceModel::finishRequest(int generation) {
    if (generation != m_generation) return;
    if (m_pendingRequests > 0) --m_pendingRequests;
    if (m_pendingRequests == 0) {
        m_loading = false;
        qInfo() << "native author space: ready"
                << "mid" << m_mid
                << "profile" << !m_name.isEmpty()
                << "avatarUrl" << !m_avatar.isEmpty()
                << "videos" << m_videos.size()
                << "dynamics" << m_dynamics.size()
                << "videoHasMore" << m_videoHasMore
                << "dynamicHasMore" << m_dynamicHasMore
                << "error" << m_errorMessage;
    }
    emit changed();
}

void AuthorSpaceModel::load(const QString &mid) {
    const QString nextMid = mid.trimmed();
    if (nextMid.isEmpty()) return;
    ++m_generation;
    const int generation = m_generation;
    m_mid = nextMid;
    m_name.clear();
    m_avatar.clear();
    m_signature.clear();
    m_followerText.clear();
    beginResetModel();
    m_videos.clear();
    m_dynamics.clear();
    m_seenVideos.clear();
    m_seenDynamics.clear();
    m_videoPage = 0;
    m_videoHasMore = true;
    m_dynamicHasMore = true;
    m_dynamicOffset.clear();
    endResetModel();
    m_errorMessage.clear();
    m_loading = true;
    m_pendingRequests = 3;
    emit changed();

    requestProfile(generation);
    requestVideos(generation, 1);
    requestDynamics(generation, QString());
}

void AuthorSpaceModel::loadMore() {
    if (m_loading || m_mid.isEmpty() || !hasMore()) return;
    const int generation = m_generation;
    const bool requestMoreVideos = m_videoHasMore;
    const bool requestMoreDynamics = m_dynamicHasMore && !m_dynamicOffset.isEmpty();
    m_pendingRequests = (requestMoreVideos ? 1 : 0) + (requestMoreDynamics ? 1 : 0);
    if (m_pendingRequests == 0) {
        m_videoHasMore = false;
        m_dynamicHasMore = false;
        emit changed();
        return;
    }
    m_loading = true;
    emit changed();
    if (requestMoreVideos) requestVideos(generation, m_videoPage + 1);
    if (requestMoreDynamics) requestDynamics(generation, m_dynamicOffset);
}

void AuthorSpaceModel::requestProfile(int generation) {
    const QString requestedMid = m_mid;

    // The former /x/space/acc/info endpoint now returns -401 for otherwise
    // public profiles on the device.  /x/web-interface/card returns the same
    // public identity fields without forcing a second WBI/auth round trip.
    QUrl infoUrl(QStringLiteral("https://api.bilibili.com/x/web-interface/card"));
    QUrlQuery infoQuery;
    infoQuery.addQueryItem(QStringLiteral("mid"), requestedMid);
    infoUrl.setQuery(infoQuery);
    QNetworkReply *info = m_network.get(requestFor(infoUrl));
    NetworkUtils::setReplyTimeout(info, 10000);
    connect(info, &QNetworkReply::finished, this, [this, info, generation]() {
        const QByteArray body = info->readAll();
        const bool ok = info->error() == QNetworkReply::NoError;
        info->deleteLater();
        if (generation == m_generation) {
            const QJsonObject root = QJsonDocument::fromJson(body).object();
            const QJsonObject data = root.value(QStringLiteral("data")).toObject();
            const QJsonObject card = data.value(QStringLiteral("card")).toObject();
            if (ok && root.value(QStringLiteral("code")).toInt(-1) == 0 && !card.isEmpty()) {
                m_name = card.value(QStringLiteral("name")).toString();
                m_avatar = normalizedUrl(card.value(QStringLiteral("face")).toString());
                m_signature = card.value(QStringLiteral("sign")).toString();
            } else {
                m_errorMessage = tr("UP 主空间资料暂时不可用");
                qWarning() << "native author space profile: request failed"
                           << "timeout" << NetworkUtils::replyTimedOut(info)
                           << "network" << !ok
                           << "code" << root.value(QStringLiteral("code")).toInt(-1);
            }
        }
        finishRequest(generation);
    });
}

void AuthorSpaceModel::requestVideos(int generation, int page) {
    QUrl videoUrl(QStringLiteral("https://api.bilibili.com/x/space/wbi/arc/search"));
    QUrlQuery videoQuery;
    videoQuery.addQueryItem(QStringLiteral("mid"), m_mid);
    videoQuery.addQueryItem(QStringLiteral("pn"), QString::number(page));
    videoQuery.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
    videoQuery.addQueryItem(QStringLiteral("order"), QStringLiteral("pubdate"));
    videoUrl.setQuery(videoQuery);
    AccountService *account = AccountService::instance();
    if (account && account->wbiReady()) {
        sendVideoRequest(generation, page, account->signedWbiUrl(videoUrl));
        return;
    }

    // Space video search now rejects unsigned requests with -352. Bootstrap
    // the public WBI key when the account-nav request has not completed yet,
    // then send the real request without leaving this page loading forever.
    QNetworkReply *nav = m_network.get(requestFor(QUrl(QStringLiteral(
        "https://api.bilibili.com/x/web-interface/nav"))));
    NetworkUtils::setReplyTimeout(nav, 10000);
    connect(nav, &QNetworkReply::finished, this,
            [this, nav, generation, page, videoUrl]() {
        const QByteArray body = nav->readAll();
        const bool timedOut = NetworkUtils::replyTimedOut(nav);
        const bool ok = nav->error() == QNetworkReply::NoError;
        nav->deleteLater();
        if (generation != m_generation) return;
        const QJsonObject root = QJsonDocument::fromJson(body).object();
        const QString mixin = NetworkUtils::wbiMixinKey(
                    root.value(QStringLiteral("data")).toObject());
        if (!ok || root.value(QStringLiteral("code")).toInt(-1) != 0
                || mixin.isEmpty()) {
            m_videoHasMore = false;
            if (m_errorMessage.isEmpty())
                m_errorMessage = timedOut ? tr("空间视频签名请求超时")
                                          : tr("空间视频签名暂时不可用");
            qWarning() << "native author space videos: WBI bootstrap failed"
                       << "network" << !ok << "timeout" << timedOut
                       << "code" << root.value(QStringLiteral("code")).toInt(-1);
            finishRequest(generation);
            return;
        }
        sendVideoRequest(generation, page,
                         NetworkUtils::signWbiUrl(videoUrl, mixin));
    });
}

void AuthorSpaceModel::sendVideoRequest(int generation, int page, const QUrl &videoUrl) {
    QNetworkReply *videos = m_network.get(requestFor(videoUrl));
    NetworkUtils::setReplyTimeout(videos, 12000);
    connect(videos, &QNetworkReply::finished, this, [this, videos, generation, page]() {
        const QByteArray body = videos->readAll();
        const bool timedOut = NetworkUtils::replyTimedOut(videos);
        const bool ok = videos->error() == QNetworkReply::NoError;
        videos->deleteLater();
        if (generation == m_generation) {
            const QJsonObject root = QJsonDocument::fromJson(body).object();
            const QJsonObject data = root.value(QStringLiteral("data")).toObject();
            const QJsonArray list = data
                                    .value(QStringLiteral("list")).toObject()
                                    .value(QStringLiteral("vlist")).toArray();
            if (ok && root.value(QStringLiteral("code")).toInt(-1) == 0) {
                int added = 0;
                QVariantList nextVideos;
                for (const QJsonValue &value : list) {
                    const QJsonObject object = value.toObject();
                    const QString bvid = object.value(QStringLiteral("bvid")).toString();
                    if (bvid.isEmpty() || m_seenVideos.contains(bvid)) continue;
                    QVariantMap item;
                    item.insert(QStringLiteral("bvid"), bvid);
                    item.insert(QStringLiteral("title"), object.value(QStringLiteral("title")).toString());
                    item.insert(QStringLiteral("cover"), normalizedUrl(object.value(QStringLiteral("pic")).toString()));
                    item.insert(QStringLiteral("duration"), object.value(QStringLiteral("length")).toString());
                    item.insert(QStringLiteral("stats"), tr("播放 %1")
                                .arg(formatCount(static_cast<qint64>(object.value(QStringLiteral("play")).toDouble()))));
                    nextVideos.append(item);
                    m_seenVideos.insert(bvid);
                    ++added;
                }
                if (!nextVideos.isEmpty()) {
                    const int first = m_videos.size();
                    beginInsertRows(QModelIndex(), first, first + nextVideos.size() - 1);
                    m_videos += nextVideos;
                    endInsertRows();
                }
                m_videoPage = page;
                const int total = data.value(QStringLiteral("page")).toObject()
                                  .value(QStringLiteral("count")).toInt();
                m_videoHasMore = added > 0 && (total > 0 ? page * 20 < total : list.size() >= 20);
                qInfo() << "native author space videos: page" << page
                        << "added" << added << "shown" << m_videos.size()
                        << "hasMore" << m_videoHasMore;
            } else {
                m_videoHasMore = false;
                if (m_errorMessage.isEmpty())
                    m_errorMessage = timedOut ? tr("空间视频请求超时，请重试")
                                              : tr("空间视频加载失败");
                qWarning() << "native author space videos: request failed"
                           << "page" << page << "timeout" << timedOut
                           << "network" << !ok
                           << "code" << root.value(QStringLiteral("code")).toInt(-1);
            }
        }
        finishRequest(generation);
    });
}

void AuthorSpaceModel::requestDynamics(int generation, const QString &offset) {
    QUrl dynamicUrl(QStringLiteral("https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space"));
    QUrlQuery dynamicQuery;
    dynamicQuery.addQueryItem(QStringLiteral("host_mid"), m_mid);
    if (!offset.isEmpty()) dynamicQuery.addQueryItem(QStringLiteral("offset"), offset);
    dynamicUrl.setQuery(dynamicQuery);
    QNetworkReply *dynamics = m_network.get(requestFor(dynamicUrl));
    NetworkUtils::setReplyTimeout(dynamics, 12000);
    connect(dynamics, &QNetworkReply::finished, this, [this, dynamics, generation]() {
        const QByteArray body = dynamics->readAll();
        const bool timedOut = NetworkUtils::replyTimedOut(dynamics);
        const bool ok = dynamics->error() == QNetworkReply::NoError;
        dynamics->deleteLater();
        if (generation == m_generation) {
            const QJsonObject root = QJsonDocument::fromJson(body).object();
            const QJsonObject data = root.value(QStringLiteral("data")).toObject();
            const QJsonArray items = data.value(QStringLiteral("items")).toArray();
            if (ok && root.value(QStringLiteral("code")).toInt(-1) == 0) {
                int added = 0;
                int forwarded = 0;
                int commentable = 0;
                QVariantList nextDynamics;
                for (const QJsonValue &value : items) {
                    const QJsonObject object = value.toObject();
                    QString dynamicId = jsonId(object.value(QStringLiteral("id_str")));
                    if (dynamicId.isEmpty()) dynamicId = jsonId(object.value(QStringLiteral("id")));
                    if (!dynamicId.isEmpty() && m_seenDynamics.contains(dynamicId)) continue;
                    const QJsonObject modules = object.value(QStringLiteral("modules")).toObject();
                    const QJsonObject dynamic = modules.value(QStringLiteral("module_dynamic")).toObject();
                    const QJsonObject major = dynamic.value(QStringLiteral("major")).toObject();
                    QVariantMap item;
                    item.insert(QStringLiteral("dynamicId"), dynamicId);
                    item.insert(QStringLiteral("text"), dynamic.value(QStringLiteral("desc")).toObject()
                                .value(QStringLiteral("text")).toString());
                    item.insert(QStringLiteral("time"), modules.value(QStringLiteral("module_author")).toObject()
                                .value(QStringLiteral("pub_time")).toString());
                    const QJsonObject basic = object.value(QStringLiteral("basic")).toObject();
                    item.insert(QStringLiteral("commentOid"), jsonId(basic.value(QStringLiteral("comment_id_str"))));
                    item.insert(QStringLiteral("commentType"), basic.value(QStringLiteral("comment_type")).toInt(17));
                    parseMajor(major, &item);
                    const bool isForward = object.value(QStringLiteral("type")).toString()
                            == QStringLiteral("DYNAMIC_TYPE_FORWARD");
                    if (isForward)
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
                    item.insert(QStringLiteral("stats"), stats.join(QStringLiteral("  ·  ")));
                    if (item.value(QStringLiteral("text")).toString().isEmpty()
                            && item.value(QStringLiteral("title")).toString().isEmpty()
                            && item.value(QStringLiteral("imageUrls")).toStringList().isEmpty())
                        item.insert(QStringLiteral("text"), tr("发布了一条动态"));
                    nextDynamics.append(item);
                    if (!dynamicId.isEmpty()) m_seenDynamics.insert(dynamicId);
                    ++added;
                    if (isForward && !item.value(QStringLiteral("source")).toString().isEmpty())
                        ++forwarded;
                    if (!item.value(QStringLiteral("commentOid")).toString().isEmpty())
                        ++commentable;
                }
                if (!nextDynamics.isEmpty()) {
                    const int first = rowCount();
                    beginInsertRows(QModelIndex(), first, first + nextDynamics.size() - 1);
                    m_dynamics += nextDynamics;
                    endInsertRows();
                }
                const QString oldOffset = m_dynamicOffset;
                m_dynamicOffset = data.value(QStringLiteral("offset")).toString();
                const QJsonValue hasMore = data.value(QStringLiteral("has_more"));
                m_dynamicHasMore = hasMore.isBool() ? hasMore.toBool() : hasMore.toInt() != 0;
                if (m_dynamicOffset.isEmpty() || m_dynamicOffset == oldOffset) m_dynamicHasMore = false;
                qInfo() << "native author space dynamics: added" << added
                        << "shown" << m_dynamics.size()
                        << "forwarded" << forwarded
                        << "commentable" << commentable
                        << "hasMore" << m_dynamicHasMore
                        << "offset" << !m_dynamicOffset.isEmpty();
            } else {
                m_dynamicHasMore = false;
                if (m_errorMessage.isEmpty())
                    m_errorMessage = timedOut ? tr("空间动态请求超时，请重试")
                                              : tr("空间动态加载失败");
                qWarning() << "native author space dynamics: request failed"
                           << "timeout" << timedOut << "network" << !ok
                           << "code" << root.value(QStringLiteral("code")).toInt(-1);
            }
        }
        finishRequest(generation);
    });
}
