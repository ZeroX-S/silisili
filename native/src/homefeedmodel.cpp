#include "homefeedmodel.h"
#include "accountservice.h"
#include "networkutils.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QLocale>
#include <QDebug>
#include <QUrl>

HomeFeedModel::HomeFeedModel(AccountService *accountService, QObject *parent)
    : QAbstractListModel(parent), m_accountService(accountService), m_loading(false),
      m_hasMore(true), m_requestSerial(0), m_nextPage(1),
      m_feedKind(QStringLiteral("recommended")) {}

int HomeFeedModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_items.size();
}

QVariant HomeFeedModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return QVariant();
    const Item &item = m_items.at(index.row());
    switch (role) {
    case TitleRole: return item.title;
    case OwnerRole: return item.owner;
    case CoverRole: return item.cover;
    case BvidRole: return item.bvid;
    case CidRole: return item.cid;
    case PlayRole: return item.play;
    case DanmakuRole: return item.danmaku;
    case ReasonRole: return item.reason;
    default: return QVariant();
    }
}

QHash<int, QByteArray> HomeFeedModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[OwnerRole] = "owner";
    roles[CoverRole] = "cover";
    roles[BvidRole] = "bvid";
    roles[CidRole] = "cid";
    roles[PlayRole] = "playCount";
    roles[DanmakuRole] = "danmakuCount";
    roles[ReasonRole] = "recommendReason";
    return roles;
}

QString HomeFeedModel::feedTitle() const {
    return m_feedKind == QStringLiteral("popular") ? tr("热门视频") : tr("推荐视频");
}

QString HomeFeedModel::countText(qint64 value) {
    if (value >= 100000000) return QString::number(value / 100000000.0, 'f', 1) + QStringLiteral("亿");
    if (value >= 10000) return QString::number(value / 10000.0, 'f', 1) + QStringLiteral("万");
    return QLocale().toString(value);
}

void HomeFeedModel::setLoading(bool value) {
    if (m_loading == value) return;
    m_loading = value;
    emit loadingChanged();
}

void HomeFeedModel::setHasMore(bool value) {
    if (m_hasMore == value) return;
    m_hasMore = value;
    emit hasMoreChanged();
}

void HomeFeedModel::setErrorMessage(const QString &value) {
    if (m_errorMessage == value) return;
    m_errorMessage = value;
    emit errorMessageChanged();
}

void HomeFeedModel::refresh() {
    loadFeed(m_feedKind);
}

void HomeFeedModel::loadMore() {
    // Automatic pagination can be triggered by contentY, movement, count and
    // loading notifications in the same GUI-thread event turn.  Once a page
    // request has failed, do not let those signals immediately create another
    // offline request.  An explicit refresh clears the error in requestFeed().
    if (m_loading || !m_hasMore || !m_errorMessage.isEmpty()) return;
    requestFeed(false);
}

void HomeFeedModel::showRecommended() {
    loadFeed(QStringLiteral("recommended"));
}

void HomeFeedModel::showPopular() {
    loadFeed(QStringLiteral("popular"));
}

void HomeFeedModel::loadFeed(const QString &feedKind) {
    const QString nextKind = feedKind == QStringLiteral("popular")
            ? QStringLiteral("popular") : QStringLiteral("recommended");
    if (m_feedKind != nextKind) {
        m_feedKind = nextKind;
        emit feedChanged();
    }
    m_nextPage = 1;
    m_seenBvids.clear();
    setHasMore(true);
    requestFeed(true);
}

void HomeFeedModel::requestFeed(bool reset) {
    const int requestSerial = ++m_requestSerial;
    if (m_activeReply) {
        QNetworkReply *obsolete = m_activeReply.data();
        m_activeReply.clear();
        obsolete->abort();
        qInfo() << "native home: obsolete request cancelled for refresh";
    }
    setLoading(true);
    setErrorMessage(QString());
    const int requestedPage = qMax(1, m_nextPage);
    const QString url = m_feedKind == QStringLiteral("popular")
            ? QStringLiteral("https://api.bilibili.com/x/web-interface/popular?pn=%1&ps=30").arg(requestedPage)
            : QStringLiteral("https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?fresh_idx=%1&ps=30&feed_version=V1&fresh_type=0&plat=1&x_num=3&y_num=10").arg(requestedPage);
    QUrl requestUrl(url);
    if (m_feedKind == QStringLiteral("recommended") && m_accountService
            && m_accountService->wbiReady())
        requestUrl = m_accountService->signedWbiUrl(requestUrl);
    QNetworkRequest request{requestUrl};
    request.setRawHeader("User-Agent", "silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    if (m_accountService && !m_accountService->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", m_accountService->cookieHeader());
    const QString requestedKind = m_feedKind;
    const bool requestedReset = reset;
    QNetworkReply *reply = m_network.get(request);
    m_activeReply = reply;
    NetworkUtils::setReplyTimeout(reply, 12000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestSerial, requestedKind, requestedReset, requestedPage]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const bool timedOut = NetworkUtils::replyTimedOut(reply);
        const bool networkChanged = NetworkUtils::replyNetworkChanged(reply);
        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (m_activeReply == reply) m_activeReply.clear();
        reply->deleteLater();
        if (requestSerial != m_requestSerial) return;
        if (networkError != QNetworkReply::NoError) {
            setErrorMessage(networkChanged ? tr("网络已切换，请下拉重试")
                            : timedOut ? tr("网络请求超时，请下拉重试")
                            : requestedReset ? tr("网络请求失败，请下拉重试")
                                             : tr("加载更多失败，请下拉刷新后重试"));
            // Publish the failure gate before loadingChanged(false).  The home
            // page observes loadingChanged and may synchronously call
            // loadMore() while it is still near the list end; reversing this
            // order caused a re-entrant offline request storm and a frozen UI.
            setLoading(false);
            qWarning() << "native home: request failed"
                       << "serial" << requestSerial
                       << "timeout" << timedOut
                       << "networkChanged" << networkChanged
                       << "error" << networkError;
            return;
        }
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
        const QJsonObject root = document.object();
        qWarning() << "home feed response" << requestedKind << payload.size()
                   << "bytes, HTTP" << statusCode
                   << "parse" << parseError.error << parseError.errorString()
                   << "offset" << parseError.offset << "code" << root.value("code");
        if (parseError.error != QJsonParseError::NoError || root.value("code").toInt(-1) != 0) {
            setErrorMessage(tr("内容解析失败，请稍后重试"));
            setLoading(false);
            return;
        }
        QVector<Item> next;
        const QJsonObject data = root.value("data").toObject();
        const QJsonArray list = data.value(requestedKind == QStringLiteral("popular")
                                            ? QStringLiteral("list") : QStringLiteral("item")).toArray();
        for (const QJsonValue &value : list) {
            const QJsonObject object = value.toObject();
            const QJsonObject owner = object.value("owner").toObject();
            const QJsonObject stat = object.value("stat").toObject();
            Item item;
            item.title = object.value("title").toString();
            item.owner = owner.value("name").toString();
            item.cover = object.value("pic").toString().replace("http://", "https://");
            item.bvid = object.value("bvid").toString();
            item.cid = QString::number(static_cast<qint64>(
                        object.value("cid").toDouble()));
            if (item.cid == QStringLiteral("0")) item.cid.clear();
            item.play = countText(static_cast<qint64>(stat.value("view").toDouble()));
            item.danmaku = countText(static_cast<qint64>(stat.value("danmaku").toDouble()));
            const QJsonValue reason = object.value("rcmd_reason");
            item.reason = reason.isObject() ? reason.toObject().value("content").toString()
                                            : reason.toString();
            if (!item.title.isEmpty() && !item.bvid.isEmpty()
                    && (requestedReset || !m_seenBvids.contains(item.bvid))) {
                next.append(item);
                m_seenBvids.insert(item.bvid);
            }
        }
        if (requestedReset) {
            beginResetModel();
            m_items = next;
            endResetModel();
        } else if (!next.isEmpty()) {
            const int first = m_items.size();
            beginInsertRows(QModelIndex(), first, first + next.size() - 1);
            m_items += next;
            endInsertRows();
        }
        m_nextPage = requestedPage + 1;
        const bool noMore = requestedKind == QStringLiteral("popular")
                ? data.value(QStringLiteral("no_more")).toBool(false)
                : false;
        setHasMore(!noMore && !next.isEmpty());
        qWarning() << "home feed parsed" << requestedKind
                   << "page" << requestedPage
                   << "added" << next.size()
                   << "shown" << m_items.size()
                   << "hasMore" << m_hasMore;
        if (m_items.isEmpty()) setErrorMessage(tr("暂时没有可显示的内容"));
        setLoading(false);
    });
}
