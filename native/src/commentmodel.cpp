#include "commentmodel.h"
#include "networkutils.h"

#include "accountservice.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrlQuery>

namespace {
QString replyId(const QJsonObject &object) {
    const QJsonValue stringValue = object.value(QStringLiteral("rpid_str"));
    if (stringValue.isString() && !stringValue.toString().isEmpty())
        return stringValue.toString();

    // Older API responses may only expose the numeric field. Keep this as a
    // compatibility fallback, but prefer rpid_str because current reply IDs
    // can exceed the exact integer range of JSON/QML doubles.
    const QJsonValue numericValue = object.value(QStringLiteral("rpid"));
    if (numericValue.isString()) return numericValue.toString();
    const qint64 numericId = static_cast<qint64>(numericValue.toDouble());
    return numericId > 0 ? QString::number(numericId) : QString();
}
}

CommentModel::CommentModel(QObject *parent)
    : QAbstractListModel(parent), m_loading(false), m_posting(false),
      m_actioning(false), m_hasMore(false),
      m_refreshPending(false), m_threadMode(false), m_next(0), m_totalCount(0),
      m_revision(0), m_type(1),
      m_simulateActions(qgetenv("SILISILI_NATIVE_TEST_COMMENT_ACTIONS")
                        == QByteArrayLiteral("simulate")) {}

int CommentModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant CommentModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case AuthorRole: return item.author;
    case AvatarRole: return item.avatar;
    case MessageRole: return item.message;
    case LikeRole: return item.likeCount;
    case ReplyRole: return item.replyCount;
    case TimeRole: return item.time;
    case RpidRole: return item.rpid;
    case PinnedRole: return item.pinned;
    case LikedRole: return item.liked;
    default: return QVariant();
    }
}

QHash<int, QByteArray> CommentModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[AuthorRole] = "author";
    roles[AvatarRole] = "avatar";
    roles[MessageRole] = "messageText";
    roles[LikeRole] = "likeCount";
    roles[ReplyRole] = "replyCount";
    roles[TimeRole] = "commentTime";
    roles[RpidRole] = "rpid";
    roles[PinnedRole] = "pinned";
    roles[LikedRole] = "liked";
    return roles;
}

QVariantMap CommentModel::get(int row) const {
    QVariantMap result;
    if (row < 0 || row >= m_items.size()) return result;
    const Item &item = m_items.at(row);
    result.insert(QStringLiteral("author"), item.author);
    result.insert(QStringLiteral("avatar"), item.avatar);
    result.insert(QStringLiteral("messageText"), item.message);
    result.insert(QStringLiteral("likeCount"), item.likeCount);
    result.insert(QStringLiteral("replyCount"), item.replyCount);
    result.insert(QStringLiteral("commentTime"), item.time);
    result.insert(QStringLiteral("rpid"), item.rpid);
    result.insert(QStringLiteral("pinned"), item.pinned);
    result.insert(QStringLiteral("liked"), item.liked);
    return result;
}

void CommentModel::load(const QString &aid) {
    loadResource(aid, 1);
}

void CommentModel::loadResource(const QString &oid, int type) {
    if (oid.isEmpty() || type <= 0 || m_loading) return;
    if (!m_threadMode && m_aid == oid && m_type == type && !m_items.isEmpty()) return;
    m_threadMode = false;
    m_rootRpid.clear();
    m_aid = oid;
    m_type = type;
    refresh();
}

void CommentModel::loadThread(const QString &aid, const QString &rootRpid) {
    loadThreadResource(aid, 1, rootRpid);
}

void CommentModel::loadThreadResource(const QString &oid, int type, const QString &rootRpid) {
    if (oid.isEmpty() || type <= 0 || rootRpid.isEmpty() || m_loading) return;
    if (m_threadMode && m_aid == oid && m_type == type
            && m_rootRpid == rootRpid && !m_items.isEmpty()) return;
    m_threadMode = true;
    m_aid = oid;
    m_type = type;
    m_rootRpid = rootRpid;
    refresh();
}

void CommentModel::refresh() {
    if (m_aid.isEmpty()) return;
    if (m_loading) {
        m_refreshPending = true;
        return;
    }
    m_refreshPending = false;
    m_next = m_threadMode ? 1 : 0;
    m_hasMore = true;
    requestPage(true);
}

void CommentModel::loadMore() {
    if (m_loading || !m_hasMore || m_aid.isEmpty() || !m_error.isEmpty()) return;
    requestPage(false);
}

void CommentModel::requestPage(bool reset) {
    if (m_loading) return;
    m_loading = true;
    m_error.clear();
    emit stateChanged();

    const int requestedNext = m_next;
    QUrl url(m_threadMode
             ? QStringLiteral("https://api.bilibili.com/x/v2/reply/reply")
             : QStringLiteral("https://api.bilibili.com/x/v2/reply/main"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("type"), QString::number(m_type));
    query.addQueryItem(QStringLiteral("oid"), m_aid);
    if (m_threadMode) {
        query.addQueryItem(QStringLiteral("root"), m_rootRpid);
        query.addQueryItem(QStringLiteral("pn"), QString::number(requestedNext));
        query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
    } else {
        query.addQueryItem(QStringLiteral("mode"), QStringLiteral("3"));
        query.addQueryItem(QStringLiteral("next"), QString::number(requestedNext));
        query.addQueryItem(QStringLiteral("plat"), QStringLiteral("1"));
    }
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
    connect(reply, &QNetworkReply::finished, this, [this, reply, reset, requestedNext]() {
        const auto finish = [this]() {
            emit stateChanged();
            if (m_refreshPending) {
                m_refreshPending = false;
                QTimer::singleShot(0, this, SLOT(refresh()));
            }
        };
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_error = tr("评论请求失败");
            finish();
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_error = tr("评论解析失败");
            finish();
            return;
        }

        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        const QJsonObject cursor = data.value(QStringLiteral("cursor")).toObject();
        QVector<Item> nextItems;
        if (reset) m_seenRpids.clear();
        if (!m_threadMode && reset)
            appendReplies(data.value(QStringLiteral("top_replies")).toArray(), true, &nextItems);
        appendReplies(data.value(QStringLiteral("replies")).toArray(), false, &nextItems);

        if (reset) {
            beginResetModel();
            m_items = nextItems;
            endResetModel();
            ++m_revision;
        } else if (!nextItems.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + nextItems.size() - 1);
            m_items += nextItems;
            endInsertRows();
            ++m_revision;
        }

        bool ended = true;
        if (m_threadMode) {
            const QJsonObject page = data.value(QStringLiteral("page")).toObject();
            const int pageSize = qMax(1, page.value(QStringLiteral("size")).toInt(20));
            const int pageNumber = page.value(QStringLiteral("num")).toInt(requestedNext);
            m_totalCount = page.value(QStringLiteral("count")).toInt(m_items.size());
            ended = nextItems.isEmpty() || pageNumber * pageSize >= m_totalCount;
            m_next = pageNumber + 1;
            m_hasMore = !ended;
        } else {
            const int nextCursor = cursor.value(QStringLiteral("next")).toInt(requestedNext);
            ended = cursor.value(QStringLiteral("is_end")).toBool(true);
            m_totalCount = cursor.value(QStringLiteral("all_count")).toInt(m_items.size());
            m_hasMore = !ended && nextCursor != requestedNext;
            m_next = nextCursor;
        }
        qInfo() << (m_threadMode ? "native comment replies: page" : "native comments: page")
                << requestedNext << "type" << m_type << "added" << nextItems.size()
                << "shown" << m_items.size() << "total" << m_totalCount
                << "next" << m_next << "end" << ended;
        if (m_items.isEmpty()) m_error = m_threadMode ? tr("暂无回复") : tr("暂无评论");
        finish();
    });
}

void CommentModel::appendReplies(const QJsonArray &replies, bool pinnedValue, QVector<Item> *items) {
    for (const QJsonValue &value : replies) {
        const QJsonObject object = value.toObject();
        const QString rpid = replyId(object);
        if (!rpid.isEmpty() && m_seenRpids.contains(rpid)) continue;
        const QJsonObject member = object.value(QStringLiteral("member")).toObject();
        const QJsonObject content = object.value(QStringLiteral("content")).toObject();
        Item item;
        item.author = member.value(QStringLiteral("uname")).toString();
        item.avatar = member.value(QStringLiteral("avatar")).toString().replace(QStringLiteral("http://"), QStringLiteral("https://"));
        item.message = content.value(QStringLiteral("message")).toString();
        item.likeCount = qMax(0, object.value(QStringLiteral("like")).toInt());
        item.replyCount = qMax(0, object.value(QStringLiteral("rcount")).toInt());
        item.rpid = rpid;
        item.pinned = pinnedValue;
        item.liked = object.value(QStringLiteral("action")).toInt() == 1;
        const qint64 timestamp = static_cast<qint64>(object.value(QStringLiteral("ctime")).toDouble());
        if (timestamp > 0)
            item.time = QDateTime::fromMSecsSinceEpoch(timestamp * 1000).toString(QStringLiteral("MM-dd hh:mm"));
        if (item.author.isEmpty()) continue;
        items->append(item);
        if (!rpid.isEmpty()) m_seenRpids.insert(rpid);
    }
}

void CommentModel::postComment(const QString &message) {
    submitComment(message, QString(), QString(), QString());
}

void CommentModel::postReply(const QString &message, const QString &parentRpid,
                             const QString &rootRpid, const QString &replyAuthor) {
    submitComment(message, parentRpid, rootRpid, replyAuthor);
}

void CommentModel::submitComment(const QString &message, const QString &parentRpid,
                                 const QString &rootRpid, const QString &replyAuthor) {
    const QString trimmed = message.trimmed();
    if (trimmed.isEmpty() || m_posting || m_aid.isEmpty()) return;
    const bool replying = !parentRpid.isEmpty() && !rootRpid.isEmpty();
    AccountService *account = AccountService::instance();
    if (!account || account->cookieHeader().isEmpty() || account->csrfToken().isEmpty()) {
        m_error = tr("登录后才能发表评论");
        emit stateChanged();
        return;
    }

    m_posting = true;
    m_error.clear();
    emit stateChanged();
    QNetworkRequest request(QUrl(QStringLiteral("https://api.bilibili.com/x/v2/reply/add")));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Cookie", account->cookieHeader());
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    QUrlQuery body;
    body.addQueryItem(QStringLiteral("type"), QString::number(m_type));
    body.addQueryItem(QStringLiteral("oid"), m_aid);
    QString submittedMessage = trimmed;
    if (replying && parentRpid != rootRpid && !replyAuthor.trimmed().isEmpty())
        submittedMessage = tr("回复 @%1：%2").arg(replyAuthor.trimmed(), trimmed);
    body.addQueryItem(QStringLiteral("message"), submittedMessage);
    body.addQueryItem(QStringLiteral("csrf"), account->csrfToken());
    body.addQueryItem(QStringLiteral("plat"), QStringLiteral("1"));
    if (replying) {
        body.addQueryItem(QStringLiteral("parent"), parentRpid);
        body.addQueryItem(QStringLiteral("root"), rootRpid);
    }
    qInfo() << "native comment action: submit requested"
            << "kind" << (replying ? "reply" : "comment")
            << "oid" << m_aid << "type" << m_type
            << "parent" << parentRpid << "root" << rootRpid
            << "simulated" << m_simulateActions;
    if (m_simulateActions) {
        QTimer::singleShot(80, this, [this, replying, rootRpid]() {
            m_posting = false;
            m_error.clear();
            const QString syntheticRpid = QStringLiteral("900000000000000001");
            int updatedReplyCount = -1;
            if (replying) {
                const int rootRow = rowForRpid(rootRpid);
                if (rootRow >= 0) {
                    Item &rootItem = m_items[rootRow];
                    ++rootItem.replyCount;
                    updatedReplyCount = rootItem.replyCount;
                    emit dataChanged(index(rootRow), index(rootRow),
                                     QVector<int>() << ReplyRole);
                    ++m_revision;
                }
                qInfo() << "native comment action: submit result"
                        << "kind" << "reply" << "accepted" << true
                        << "root" << rootRpid << "newRpid" << syntheticRpid
                        << "rootReplyCount" << updatedReplyCount
                        << "simulated" << true;
                emit replyPosted(rootRpid, syntheticRpid);
            } else {
                qInfo() << "native comment action: submit result"
                        << "kind" << "comment" << "accepted" << true
                        << "simulated" << true;
                emit commentPosted();
            }
            emit stateChanged();
        });
        return;
    }
    QNetworkReply *reply = m_network.post(request, body.query(QUrl::FullyEncoded).toUtf8());
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, replying, rootRpid]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        m_posting = false;
        emit stateChanged();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        const int code = root.value(QStringLiteral("code")).toInt(-1);
        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        const int successAction = data.value(QStringLiteral("success_action")).toInt(0);
        if (networkError != QNetworkReply::NoError
                || parseError.error != QJsonParseError::NoError
                || code != 0 || successAction != 0) {
            const QString message = root.value(QStringLiteral("message")).toString();
            m_error = message.isEmpty()
                    ? (replying ? tr("回复发表失败") : tr("评论发表失败")) : message;
            qWarning() << "native comment action: submit result"
                       << "kind" << (replying ? "reply" : "comment")
                       << "accepted" << false << "code" << code
                       << "successAction" << successAction
                       << "network" << networkError;
            emit stateChanged();
            return;
        }
        const QJsonObject addedReply = data.value(QStringLiteral("reply")).toObject();
        const QString newRpid = replyId(addedReply);
        qInfo() << "native comment action: submit result"
                << "kind" << (replying ? "reply" : "comment")
                << "accepted" << true << "code" << code
                << "root" << rootRpid << "newRpid" << newRpid
                << "simulated" << false;
        if (replying)
            emit replyPosted(rootRpid, newRpid);
        else
            emit commentPosted();
        refresh();
    });
}

int CommentModel::rowForRpid(const QString &rpid) const {
    for (int row = 0; row < m_items.size(); ++row) {
        if (m_items.at(row).rpid == rpid) return row;
    }
    return -1;
}

void CommentModel::setItemLike(int row, bool liked, int likeCount) {
    if (row < 0 || row >= m_items.size()) return;
    Item &item = m_items[row];
    item.liked = liked;
    item.likeCount = qMax(0, likeCount);
    emit dataChanged(index(row), index(row), QVector<int>() << LikeRole << LikedRole);
    ++m_revision;
    emit stateChanged();
}

void CommentModel::toggleLike(int row) {
    if (row < 0 || row >= m_items.size()) return;
    const Item &item = m_items.at(row);
    toggleLikeRpid(item.rpid, item.liked, item.likeCount);
}

void CommentModel::toggleLikeRpid(const QString &rpid, bool currentlyLiked,
                                  int likeCount) {
    if (rpid.isEmpty() || m_actioning || m_aid.isEmpty()) return;
    AccountService *account = AccountService::instance();
    if (!account || account->cookieHeader().isEmpty() || account->csrfToken().isEmpty()) {
        m_error = tr("登录后才能点赞评论");
        emit stateChanged();
        return;
    }

    const bool requestedLiked = !currentlyLiked;
    const int previousLikeCount = qMax(0, likeCount);
    const int requestedLikeCount = qMax(0, previousLikeCount
                                        + (requestedLiked ? 1 : -1));
    const int row = rowForRpid(rpid);
    m_actioning = true;
    m_error.clear();
    if (row >= 0) setItemLike(row, requestedLiked, requestedLikeCount);
    emit commentLikeChanged(rpid, requestedLiked, requestedLikeCount);
    emit stateChanged();
    qInfo() << "native comment action: like requested"
            << "oid" << m_aid << "type" << m_type << "rpid" << rpid
            << "liked" << requestedLiked << "likeCount" << requestedLikeCount
            << "simulated" << m_simulateActions;

    const auto finish = [this, rpid, currentlyLiked, previousLikeCount,
                         requestedLiked, requestedLikeCount](bool accepted,
                                                            int code,
                                                            QNetworkReply::NetworkError networkError,
                                                            const QString &message,
                                                            bool simulated) {
        m_actioning = false;
        const int currentRow = rowForRpid(rpid);
        if (accepted) {
            if (currentRow >= 0)
                setItemLike(currentRow, requestedLiked, requestedLikeCount);
        } else {
            if (currentRow >= 0)
                setItemLike(currentRow, currentlyLiked, previousLikeCount);
            emit commentLikeChanged(rpid, currentlyLiked, previousLikeCount);
            m_error = message.isEmpty() ? tr("评论点赞操作失败") : message;
        }
        qInfo() << "native comment action: like result"
                << "accepted" << accepted << "code" << code
                << "network" << networkError << "rpid" << rpid
                << "liked" << (accepted ? requestedLiked : currentlyLiked)
                << "likeCount" << (accepted ? requestedLikeCount : previousLikeCount)
                << "simulated" << simulated;
        emit stateChanged();
    };

    if (m_simulateActions) {
        QTimer::singleShot(80, this, [finish]() {
            finish(true, 0, QNetworkReply::NoError, QString(), true);
        });
        return;
    }

    QNetworkRequest request(QUrl(QStringLiteral(
        "https://api.bilibili.com/x/v2/reply/action")));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Cookie", account->cookieHeader());
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    QUrlQuery body;
    body.addQueryItem(QStringLiteral("oid"), m_aid);
    body.addQueryItem(QStringLiteral("rpid"), rpid);
    body.addQueryItem(QStringLiteral("action"), requestedLiked
                      ? QStringLiteral("1") : QStringLiteral("0"));
    body.addQueryItem(QStringLiteral("csrf"), account->csrfToken());
    body.addQueryItem(QStringLiteral("type"), QString::number(m_type));
    body.addQueryItem(QStringLiteral("ordering"), QStringLiteral("heat"));
    QNetworkReply *reply = m_network.post(
        request, body.query(QUrl::FullyEncoded).toUtf8());
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [reply, finish]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        const int code = root.value(QStringLiteral("code")).toInt(-1);
        const bool accepted = networkError == QNetworkReply::NoError
                && parseError.error == QJsonParseError::NoError && code == 0;
        finish(accepted, code, networkError,
               root.value(QStringLiteral("message")).toString(), false);
    });
}
