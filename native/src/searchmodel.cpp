#include "searchmodel.h"
#include "accountservice.h"
#include "networkutils.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegExp>
#include <QDebug>
#include <QUrl>
#include <QUrlQuery>
#include <QSettings>

SearchModel::SearchModel(AccountService *accountService, QObject *parent)
    : QAbstractListModel(parent), m_accountService(accountService), m_loading(false), m_page(0),
      m_hasMore(false), m_requestSerial(0) {
    QSettings settings; m_history = settings.value(QStringLiteral("search/history")).toStringList();
}

int SearchModel::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_items.size(); }

QVariant SearchModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case OwnerRole: return item.owner;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case PlayRole: return item.play;
    case DurationRole: return item.duration;
    default: return QVariant();
    }
}

QHash<int, QByteArray> SearchModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title"; roles[OwnerRole] = "owner"; roles[CoverRole] = "cover";
    roles[BvidRole] = "bvid"; roles[PlayRole] = "playCount"; roles[DurationRole] = "duration";
    return roles;
}

void SearchModel::setLoading(bool value) { if (m_loading != value) { m_loading = value; emit loadingChanged(); } }
void SearchModel::setErrorMessage(const QString &value) { if (m_errorMessage != value) { m_errorMessage = value; emit errorMessageChanged(); } }

void SearchModel::search(const QString &query) {
    const QString trimmed = query.trimmed();
    if (trimmed.isEmpty()) return;
    if (m_loading && m_query == trimmed) return;
    if (m_activeReply) m_activeReply->abort();
    if (m_query != trimmed) { m_query = trimmed; emit queryChanged(); }
    m_history.removeAll(trimmed); m_history.prepend(trimmed); while (m_history.size() > 12) m_history.removeLast();
    QSettings().setValue(QStringLiteral("search/history"), m_history); emit historyChanged();
    m_page = 0; m_hasMore = true; requestPage(true);
}

void SearchModel::loadMore() { if (!m_loading && m_hasMore && !m_query.isEmpty()) requestPage(false); }
void SearchModel::clearHistory() { m_history.clear(); QSettings().remove(QStringLiteral("search/history")); emit historyChanged(); }

void SearchModel::requestPage(bool reset) {
    const quint64 requestSerial = ++m_requestSerial;
    setLoading(true); setErrorMessage(QString());
    const int requestedPage = m_page + 1;
    QUrl url(QStringLiteral("https://api.bilibili.com/x/web-interface/search/type"));
    QUrlQuery params; params.addQueryItem(QStringLiteral("search_type"), QStringLiteral("video"));
    params.addQueryItem(QStringLiteral("keyword"), m_query); params.addQueryItem(QStringLiteral("page"), QString::number(requestedPage));
    url.setQuery(params);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://search.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    const bool authenticated = m_accountService && !m_accountService->cookieHeader().isEmpty();
    if (authenticated) request.setRawHeader("Cookie", m_accountService->cookieHeader());
    qInfo() << "native search: request" << "page" << requestedPage
            << "authenticated" << authenticated;
    QNetworkReply *reply = m_network.get(request);
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, reset, requestedPage, authenticated, requestSerial]() {
        const QByteArray payload = reply->readAll();
        const auto networkError = reply->error();
        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString errorString = reply->errorString();
        reply->deleteLater();
        if (requestSerial != m_requestSerial) return;
        if (m_activeReply == reply) m_activeReply.clear();
        setLoading(false);
        if (networkError != QNetworkReply::NoError) {
            qWarning() << "native search: request failed" << "page" << requestedPage
                       << "authenticated" << authenticated << "HTTP" << statusCode
                       << "error" << networkError << errorString;
            if (statusCode == 412)
                setErrorMessage(tr("搜索请求受到限制，请确认登录状态后重试"));
            else
                setErrorMessage(tr("搜索请求失败：%1").arg(errorString));
            return;
        }
        QJsonParseError error; const QJsonObject root = QJsonDocument::fromJson(payload, &error).object();
        if (error.error != QJsonParseError::NoError || root.value("code").toDouble(-1) != 0) { setErrorMessage(tr("搜索结果解析失败")); return; }
        QVector<Item> next; const QJsonArray results = root.value("data").toObject().value("result").toArray();
        for (const QJsonValue &value : results) {
            const QJsonObject object = value.toObject(); Item item;
            item.title = object.value("title").toString(); item.title.remove(QRegExp(QStringLiteral("<[^>]+>")));
            item.owner = object.value("author").toString(); item.cover = object.value("pic").toString();
            if (item.cover.startsWith("//")) item.cover.prepend("https:"); else item.cover.replace("http://", "https://");
            item.bvid = object.value("bvid").toString(); item.play = QString::number(static_cast<qint64>(object.value("play").toDouble()));
            item.duration = object.value("duration").toString(); if (!item.title.isEmpty() && !item.bvid.isEmpty()) next.append(item);
        }
        qInfo() << "native search: results ready" << "page" << requestedPage
                << "authenticated" << authenticated << "items" << next.size()
                << "firstBvid" << (next.isEmpty() ? QString() : next.first().bvid);
        if (reset) { beginResetModel(); m_items = next; endResetModel(); }
        else if (!next.isEmpty()) { const int start=m_items.size(); beginInsertRows(QModelIndex(),start,start+next.size()-1); m_items += next; endInsertRows(); }
        ++m_page; m_hasMore = !next.isEmpty(); emit loadingChanged();
        if (m_items.isEmpty()) setErrorMessage(tr("没有找到相关视频"));
    });
}
