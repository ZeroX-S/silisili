#include "inboxmodel.h"

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

namespace {
QString normalizedUrl(QString url) {
    if (url.startsWith(QStringLiteral("//"))) url.prepend(QStringLiteral("https:"));
    return url.replace(QStringLiteral("http://"), QStringLiteral("https://"));
}

QString idString(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isDouble()) return QString::number(static_cast<qint64>(value.toDouble()));
    return QString();
}
}

InboxModel::InboxModel(AccountService *account, QObject *parent)
    : QAbstractListModel(parent), m_account(account), m_loading(false), m_hasMore(false),
      m_generation(0), m_category(QStringLiteral("reply")) {}

int InboxModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant InboxModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case AuthorRole: return item.author;
    case AvatarRole: return item.avatar;
    case TitleRole: return item.title;
    case TextRole: return item.text;
    case TimeRole: return item.time;
    case CategoryRole: return item.category;
    default: return QVariant();
    }
}

QHash<int, QByteArray> InboxModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[AuthorRole] = "author";
    roles[AvatarRole] = "avatar";
    roles[TitleRole] = "subject";
    roles[TextRole] = "messageText";
    roles[TimeRole] = "messageTime";
    roles[CategoryRole] = "categoryLabel";
    return roles;
}

QString InboxModel::feedTitle() const {
    if (m_category == QStringLiteral("at")) return tr("@ 我的");
    if (m_category == QStringLiteral("like")) return tr("收到的赞");
    return tr("回复我的");
}

void InboxModel::showReplies() {
    selectCategory(QStringLiteral("reply"));
}

void InboxModel::showMentions() {
    selectCategory(QStringLiteral("at"));
}

void InboxModel::showLikes() {
    selectCategory(QStringLiteral("like"));
}

void InboxModel::selectCategory(const QString &category) {
    if (category == m_category) return;
    m_category = category;
    refresh();
}

void InboxModel::refresh() {
    ++m_generation;
    if (m_activeReply) {
        QNetworkReply *obsolete = m_activeReply.data();
        m_activeReply.clear();
        obsolete->abort();
        qInfo() << "native inbox: obsolete request cancelled for refresh";
    }
    m_loading = false;
    m_cursorId.clear();
    m_cursorTime.clear();
    m_seen.clear();
    m_hasMore = true;
    request(true);
}

void InboxModel::loadMore() {
    if (!m_loading && m_hasMore) request(false);
}

void InboxModel::request(bool reset) {
    if (m_loading) return;
    if (!m_account->loggedIn()) {
        m_errorMessage = tr("登录后才能查看消息");
        emit stateChanged();
        return;
    }

    m_loading = true;
    m_errorMessage.clear();
    emit stateChanged();

    QUrl url(QStringLiteral("https://api.bilibili.com/x/msgfeed/") + m_category);
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("platform"), QStringLiteral("web"));
    query.addQueryItem(QStringLiteral("build"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("mobi_app"), QStringLiteral("web"));
    if (!reset && !m_cursorId.isEmpty()) {
        query.addQueryItem(QStringLiteral("id"), m_cursorId);
        query.addQueryItem(m_category == QStringLiteral("reply") ? QStringLiteral("reply_time")
                           : m_category == QStringLiteral("at") ? QStringLiteral("at_time")
                                                                  : QStringLiteral("like_time"),
                           m_cursorTime);
    }
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://message.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Cookie", m_account->cookieHeader());

    const int requestGeneration = m_generation;
    const QString requestCategory = m_category;
    QNetworkReply *reply = m_network.get(request);
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, reset, requestGeneration, requestCategory]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        const bool networkChanged = NetworkUtils::replyNetworkChanged(reply);
        if (m_activeReply == reply) m_activeReply.clear();
        reply->deleteLater();
        if (requestGeneration != m_generation || requestCategory != m_category) {
            qInfo() << "native inbox: stale reply ignored" << requestCategory
                    << "generation" << requestGeneration << "current" << m_generation;
            return;
        }
        m_loading = false;

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (networkError != QNetworkReply::NoError || parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_errorMessage = networkChanged ? tr("网络已切换，请下拉重试")
                             : timedOut ? tr("消息请求超时，请下拉重试")
                                        : tr("消息请求失败或登录已过期");
            qWarning() << "native inbox: request failed" << requestCategory
                       << "timeout" << timedOut
                       << "networkChanged" << networkChanged
                       << "error" << networkError;
            emit stateChanged();
            return;
        }

        const QJsonObject dataObject = root.value(QStringLiteral("data")).toObject();
        QVector<Item> nextItems;
        for (const QJsonValue &value : dataObject.value(QStringLiteral("items")).toArray()) {
            const QJsonObject object = value.toObject();
            const QJsonObject itemObject = object.value(QStringLiteral("item")).toObject();
            QJsonObject user = object.value(QStringLiteral("user")).toObject();
            QJsonArray users = object.value(QStringLiteral("users")).toArray();
            if (user.isEmpty() && !users.isEmpty()) user = users.first().toObject();

            Item item;
            item.author = user.value(QStringLiteral("nickname")).toString();
            if (item.author.isEmpty()) item.author = user.value(QStringLiteral("name")).toString();
            if (users.size() > 1) item.author = tr("%1 等 %2 人").arg(item.author).arg(users.size());
            item.avatar = normalizedUrl(user.value(QStringLiteral("avatar")).toString());
            if (item.avatar.isEmpty()) item.avatar = normalizedUrl(user.value(QStringLiteral("face")).toString());
            item.title = itemObject.value(QStringLiteral("title")).toString();
            item.text = itemObject.value(QStringLiteral("source_content")).toString();
            if (item.text.isEmpty()) item.text = itemObject.value(QStringLiteral("desc")).toString();
            if (item.text.isEmpty()) item.text = itemObject.value(QStringLiteral("target_reply_content")).toString();

            QString timestampName;
            if (requestCategory == QStringLiteral("at")) {
                item.category = tr("@ 了你");
                timestampName = QStringLiteral("at_time");
            } else if (requestCategory == QStringLiteral("like")) {
                item.category = tr("赞了你的内容");
                timestampName = QStringLiteral("like_time");
            } else {
                item.category = tr("回复了你");
                timestampName = QStringLiteral("reply_time");
            }
            if (item.text.isEmpty()) item.text = item.category;

            const qint64 timestamp = static_cast<qint64>(object.value(timestampName).toDouble());
            if (timestamp > 0)
                item.time = QDateTime::fromMSecsSinceEpoch(timestamp * 1000).toString(QStringLiteral("MM-dd hh:mm"));

            QString key = idString(object.value(QStringLiteral("id")));
            if (key.isEmpty()) key = QString::number(timestamp) + item.author + item.title + item.text;
            if (m_seen.contains(key)) continue;
            m_seen.insert(key);
            if (!item.author.isEmpty()) nextItems.append(item);
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

        const QJsonObject cursor = dataObject.value(QStringLiteral("cursor")).toObject();
        m_cursorId = idString(cursor.value(QStringLiteral("id")));
        m_cursorTime = idString(cursor.value(QStringLiteral("time")));
        const QJsonValue isEndValue = cursor.value(QStringLiteral("is_end"));
        const bool isEnd = isEndValue.isBool() ? isEndValue.toBool() : isEndValue.toInt() != 0;
        m_hasMore = !isEnd && !m_cursorId.isEmpty();
        if (m_items.isEmpty()) m_errorMessage = tr("当前分类暂无消息");
        qInfo() << "native inbox:" << requestCategory << "added" << nextItems.size()
                << "shown" << m_items.size() << "hasMore" << m_hasMore;
        emit stateChanged();
    });
}
