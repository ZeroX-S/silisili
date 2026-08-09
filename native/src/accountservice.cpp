#include "accountservice.h"
#include "networkutils.h"

#include <QFile>
#include <QDir>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkCookie>
#include <QNetworkCookieJar>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

AccountService *AccountService::s_instance = 0;

namespace {
QString genericConfigRoot() {
    const QString generic = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (!generic.isEmpty()) return generic;
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
}

QString nativeConfigRoot() {
    // Sailjail/firejail grants this application a private config directory
    // named after its desktop/app id.  The previous development builds wrote
    // to ~/.config/silisili-native, which is outside that whitelist and can
    // make QR-login cookies vanish after restart.
    return genericConfigRoot() + QStringLiteral("/cn.silisili.native");
}

QString legacyNativeConfigRoot() {
    return genericConfigRoot() + QStringLiteral("/silisili-native");
}
}

AccountService::AccountService(QObject *parent)
    : QObject(parent), m_loading(false), m_loggedIn(false), m_qrLoading(false), m_qrActive(false),
      m_verifyPlaybackHistoryForTest(
          qgetenv("SILISILI_NATIVE_TEST_VERIFY_HISTORY") == QByteArrayLiteral("1")) {
    s_instance = this;
    loadSnapshot();
}

bool AccountService::reportPlaybackHistory(const QString &aid, const QString &bvid,
                                           const QString &cid, const QString &epId,
                                           bool pgc, int progress, int duration,
                                           const QString &reason) {
    if (aid.isEmpty() || cid.isEmpty() || m_cookieHeader.isEmpty()
            || m_userId.isEmpty() || m_csrfToken.isEmpty()) {
        qInfo() << "native playback history: report skipped"
                << "reason" << reason
                << "identityReady" << (!aid.isEmpty() && !cid.isEmpty())
                << "sessionReady" << (!m_cookieHeader.isEmpty()
                                         && !m_userId.isEmpty()
                                         && !m_csrfToken.isEmpty());
        return false;
    }

    const int boundedDuration = qMax(0, duration);
    const int boundedProgress = boundedDuration > 0
            ? qBound(0, progress, boundedDuration) : qMax(0, progress);
    QUrlQuery body;
    body.addQueryItem(QStringLiteral("mid"), m_userId);
    body.addQueryItem(QStringLiteral("csrf"), m_csrfToken);
    body.addQueryItem(QStringLiteral("aid"), aid);
    body.addQueryItem(QStringLiteral("cid"), cid);
    body.addQueryItem(QStringLiteral("progress"), QString::number(boundedProgress));
    body.addQueryItem(QStringLiteral("duration"), QString::number(boundedDuration));
    body.addQueryItem(QStringLiteral("type"), pgc ? QStringLiteral("4")
                                                  : QStringLiteral("3"));
    body.addQueryItem(QStringLiteral("dt"), QStringLiteral("9"));
    if (pgc && !epId.isEmpty()) body.addQueryItem(QStringLiteral("epid"), epId);

    QNetworkRequest request(QUrl(QStringLiteral(
        "https://api.bilibili.com/x/v2/history/report")));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", pgc && !epId.isEmpty()
                         ? QStringLiteral("https://www.bilibili.com/bangumi/play/ep%1")
                           .arg(epId).toUtf8()
                         : QByteArray("https://www.bilibili.com/"));
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Content-Type", "application/x-www-form-urlencoded");
    request.setRawHeader("Cookie", m_cookieHeader);
    QNetworkReply *reply = m_network.post(
        request, body.query(QUrl::FullyEncoded).toUtf8());
    NetworkUtils::setReplyTimeout(reply, 9000);
    qInfo() << "native playback history: report requested"
            << "bvid" << bvid << "cid" << cid
            << "progress" << boundedProgress
            << "duration" << boundedDuration
            << "type" << (pgc ? 4 : 3)
            << "reason" << reason;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, aid, bvid, cid, boundedProgress, reason]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        const int code = root.value(QStringLiteral("code")).toInt(-1);
        const bool accepted = networkError == QNetworkReply::NoError
                && parseError.error == QJsonParseError::NoError && code == 0;
        qInfo() << "native playback history: report result"
                << "accepted" << accepted
                << "code" << code
                << "network" << networkError
                << "aid" << aid << "cid" << cid
                << "progress" << boundedProgress
                << "reason" << reason;
        if (accepted && m_verifyPlaybackHistoryForTest && !bvid.isEmpty())
            QTimer::singleShot(700, this, [this, bvid, cid, boundedProgress]() {
                verifyPlaybackHistory(bvid, cid, boundedProgress, 1);
            });
    });
    return true;
}

void AccountService::verifyPlaybackHistory(const QString &bvid, const QString &cid,
                                           int minimumProgress, int attempt) {
    QUrl url(QStringLiteral("https://api.bilibili.com/x/web-interface/history/cursor"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("ps"), QStringLiteral("20"));
    query.addQueryItem(QStringLiteral("max"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("view_at"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("business"), QString());
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    request.setRawHeader("Cookie", m_cookieHeader);
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 9000);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, bvid, cid, minimumProgress, attempt]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        int actualProgress = -2;
        bool found = false;
        const QJsonArray list = root.value(QStringLiteral("data")).toObject()
                .value(QStringLiteral("list")).toArray();
        for (const QJsonValue &value : list) {
            const QJsonObject object = value.toObject();
            const QJsonObject history = object.value(QStringLiteral("history")).toObject();
            if (history.value(QStringLiteral("bvid")).toString() != bvid) continue;
            const QJsonValue historyCidValue = history.value(QStringLiteral("cid"));
            const QString historyCid = historyCidValue.isString()
                    ? historyCidValue.toString()
                    : QString::number(static_cast<qint64>(historyCidValue.toDouble()));
            if (historyCid != QStringLiteral("0") && historyCid != cid) continue;
            found = true;
            actualProgress = object.value(QStringLiteral("progress")).toInt(-2);
            break;
        }
        const bool requestReady = networkError == QNetworkReply::NoError
                && parseError.error == QJsonParseError::NoError
                && root.value(QStringLiteral("code")).toInt(-1) == 0;
        const bool progressReady = actualProgress == -1
                || actualProgress >= qMax(0, minimumProgress - 2);
        const bool verified = requestReady && found && progressReady;
        qInfo() << "native playback history: verification"
                << "attempt" << attempt
                << "bvid" << bvid << "cid" << cid
                << "found" << found
                << "progress" << actualProgress
                << "minimum" << minimumProgress
                << "verified" << verified;
        if (!verified && attempt < 5) {
            QTimer::singleShot(900, this,
                               [this, bvid, cid, minimumProgress, attempt]() {
                verifyPlaybackHistory(bvid, cid, minimumProgress, attempt + 1);
            });
        }
    });
}

AccountService *AccountService::instance() { return s_instance; }

QUrl AccountService::signedWbiUrl(const QUrl &url) const {
    return NetworkUtils::signWbiUrl(url, m_wbiMixinKey);
}

void AccountService::loadSnapshot() {
    const QString configRoot = nativeConfigRoot();
    QFile nativeFile(configRoot + QStringLiteral("/account_session.json"));
    if (nativeFile.open(QIODevice::ReadOnly)) {
        QJsonParseError error;
        const QJsonObject root = QJsonDocument::fromJson(nativeFile.readAll(), &error).object();
        if (error.error == QJsonParseError::NoError) {
            if (!root.value(QStringLiteral("logged_out")).toBool(false))
                loadCookies(root.value(QStringLiteral("cookie")).toObject());
            qInfo() << "native account: loaded native session from" << nativeFile.fileName()
                    << "cookieCount" << m_cookies.size();
            return;
        }
        qWarning() << "native account: failed to parse native session"
                   << nativeFile.fileName() << error.errorString();
    }

    QFile legacyFile(legacyNativeConfigRoot() + QStringLiteral("/account_session.json"));
    if (legacyFile.open(QIODevice::ReadOnly)) {
        QJsonParseError error;
        const QJsonObject root = QJsonDocument::fromJson(legacyFile.readAll(), &error).object();
        if (error.error == QJsonParseError::NoError) {
            if (!root.value(QStringLiteral("logged_out")).toBool(false)) {
                loadCookies(root.value(QStringLiteral("cookie")).toObject());
                saveNativeSession(false);
            }
            qInfo() << "native account: imported legacy native session from"
                    << legacyFile.fileName() << "cookieCount" << m_cookies.size();
            return;
        }
        qWarning() << "native account: failed to parse legacy native session"
                   << legacyFile.fileName() << error.errorString();
    }

    QFile stableFile(configRoot + QStringLiteral("/stable_config_snapshot.json"));
    if (!stableFile.open(QIODevice::ReadOnly)) {
        stableFile.setFileName(legacyNativeConfigRoot() + QStringLiteral("/stable_config_snapshot.json"));
        if (!stableFile.open(QIODevice::ReadOnly)) return;
    }
    QJsonParseError error;
    const QJsonObject root = QJsonDocument::fromJson(stableFile.readAll(), &error).object();
    if (error.error == QJsonParseError::NoError) {
        loadCookies(root.value(QStringLiteral("cookie")).toObject());
        if (!m_cookies.isEmpty()) saveNativeSession(false);
        qInfo() << "native account: loaded migrated stable snapshot from"
                << stableFile.fileName() << "cookieCount" << m_cookies.size();
    } else {
        qWarning() << "native account: failed to parse migrated stable snapshot"
                   << stableFile.fileName() << error.errorString();
    }
}

void AccountService::loadCookies(const QJsonObject &cookies) {
    m_cookies.clear();
    for (auto it = cookies.begin(); it != cookies.end(); ++it) {
        if (it.value().isString() && !it.value().toString().isEmpty())
            m_cookies.insert(it.key(), it.value().toString());
    }
    rebuildCookieHeader();
}

void AccountService::rebuildCookieHeader() {
    QByteArrayList parts;
    for (auto it = m_cookies.constBegin(); it != m_cookies.constEnd(); ++it)
        parts.append(it.key().toUtf8() + '=' + it.value().toUtf8());
    m_cookieHeader = parts.join("; ");
    m_csrfToken = m_cookies.value(QStringLiteral("bili_jct"));
    // Authenticated content requests can start before /nav completes. Keep the
    // session's own public mid available immediately instead of leaving every
    // account model with an empty up_mid/vmid during that startup window.
    if (m_userId.isEmpty())
        m_userId = m_cookies.value(QStringLiteral("DedeUserID"));
}

void AccountService::absorbReplyCookies(QNetworkReply *reply) {
    const QList<QNetworkReply::RawHeaderPair> headers = reply->rawHeaderPairs();
    for (const QNetworkReply::RawHeaderPair &header : headers) {
        if (header.first.toLower() != QByteArrayLiteral("set-cookie")) continue;
        const QList<QNetworkCookie> cookies = QNetworkCookie::parseCookies(header.second);
        for (const QNetworkCookie &cookie : cookies) {
            if (!cookie.name().isEmpty() && !cookie.value().isEmpty())
                m_cookies.insert(QString::fromUtf8(cookie.name()), QString::fromUtf8(cookie.value()));
        }
    }
    const QList<QNetworkCookie> jarCookies = m_network.cookieJar()->cookiesForUrl(
        QUrl(QStringLiteral("https://passport.bilibili.com/")));
    for (const QNetworkCookie &cookie : jarCookies) {
        if (!cookie.name().isEmpty() && !cookie.value().isEmpty())
            m_cookies.insert(QString::fromUtf8(cookie.name()), QString::fromUtf8(cookie.value()));
    }
    rebuildCookieHeader();
}

bool AccountService::saveNativeSession(bool loggedOut) {
    const QString configRoot = nativeConfigRoot();
    if (!QDir().mkpath(configRoot)) {
        qWarning() << "native account: cannot create session directory" << configRoot;
        return false;
    }
    QJsonObject cookies;
    for (auto it = m_cookies.constBegin(); it != m_cookies.constEnd(); ++it)
        cookies.insert(it.key(), it.value());
    QJsonObject root;
    root.insert(QStringLiteral("schema"), 1);
    root.insert(QStringLiteral("logged_out"), loggedOut);
    root.insert(QStringLiteral("cookie"), cookies);
    QSaveFile file(configRoot + QStringLiteral("/account_session.json"));
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "native account: cannot open session for write" << file.fileName()
                   << file.errorString();
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!file.commit()) {
        qWarning() << "native account: cannot commit session" << file.fileName()
                   << file.errorString();
        return false;
    }
    QFile::setPermissions(file.fileName(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    qInfo() << "native account: saved native session to" << file.fileName()
            << "loggedOut" << loggedOut << "cookieCount" << m_cookies.size();
    return true;
}

void AccountService::refresh() {
    if (m_loading) return; m_loading = true; m_errorMessage.clear(); emit changed();
    QNetworkRequest request(QUrl(QStringLiteral("https://api.bilibili.com/x/web-interface/nav")));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS"); request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity"); if (!m_cookieHeader.isEmpty()) request.setRawHeader("Cookie", m_cookieHeader);
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 10000);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = reply->readAll(); const auto networkError = reply->error(); reply->deleteLater(); m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_errorMessage = NetworkUtils::replyTimedOut(reply)
                    ? tr("账户状态请求超时，请重试") : tr("账户状态请求失败");
            emit changed(); return;
        }
        QJsonParseError error; const QJsonObject root = QJsonDocument::fromJson(payload, &error).object();
        if (error.error != QJsonParseError::NoError) {
            m_loggedIn = false;
            m_userName.clear();
            m_avatar.clear();
            m_userId.clear();
            m_levelText.clear();
            m_errorMessage = tr("账户状态暂时不可用，请稍后刷新");
            qWarning() << "native account: nav json parse failed"
                       << error.errorString() << payload.left(160);
            emit changed();
            return;
        }
        const int code = root.value(QStringLiteral("code")).toInt(-1);
        if (code != 0) {
            m_loggedIn = false;
            m_userName.clear();
            m_avatar.clear();
            m_userId.clear();
            m_levelText.clear();
            const QString message = root.value(QStringLiteral("message")).toString();
            m_errorMessage = (code == -101 || code == 61000)
                    ? tr("当前登录已失效，可重新扫码登录")
                    : (message.isEmpty() ? tr("账户状态暂时不可用") : message);
            qWarning() << "native account: nav returned code" << code
                       << "message" << message;
            emit changed();
            return;
        }
        const QJsonObject data = root.value("data").toObject();
        const QString mixinKey = NetworkUtils::wbiMixinKey(data);
        if (!mixinKey.isEmpty()) m_wbiMixinKey = mixinKey;
        m_loggedIn = data.value("isLogin").toBool(false);
        m_userName = data.value("uname").toString(); m_avatar = data.value("face").toString().replace("http://", "https://");
        m_userId = QString::number(static_cast<qint64>(data.value("mid").toDouble()));
        m_levelText = tr("等级 %1").arg(data.value("level_info").toObject().value("current_level").toInt());
        qInfo() << "native account: nav parsed loggedIn" << m_loggedIn
                << "cookieCount" << m_cookies.size()
                << "wbiReady" << !m_wbiMixinKey.isEmpty();
        emit changed();
    });
}

void AccountService::startQrLogin() {
    if (m_qrLoading) return;
    m_qrLoading = true;
    m_qrActive = false;
    m_qrUrl.clear();
    m_qrKey.clear();
    m_qrStatus = tr("正在生成二维码…");
    emit changed();

    QNetworkRequest request(QUrl(QStringLiteral(
        "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 10000);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        absorbReplyCookies(reply);
        reply->deleteLater();
        m_qrLoading = false;
        QJsonParseError error;
        const QJsonObject root = QJsonDocument::fromJson(payload, &error).object();
        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        if (networkError != QNetworkReply::NoError || error.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_qrStatus = tr("二维码生成失败，请重试");
            emit changed();
            return;
        }
        m_qrUrl = data.value(QStringLiteral("url")).toString();
        m_qrKey = data.value(QStringLiteral("qrcode_key")).toString();
        m_qrActive = !m_qrUrl.isEmpty() && !m_qrKey.isEmpty();
        m_qrStatus = m_qrActive ? tr("请使用哔哩哔哩客户端扫码") : tr("二维码数据不完整");
        emit changed();
    });
}

void AccountService::pollQrLogin() {
    if (!m_qrActive || m_qrLoading || m_qrKey.isEmpty()) return;
    m_qrLoading = true;
    emit changed();
    QUrl url(QStringLiteral("https://passport.bilibili.com/x/passport-login/web/qrcode/poll"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("qrcode_key"), m_qrKey);
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    if (!m_cookieHeader.isEmpty()) request.setRawHeader("Cookie", m_cookieHeader);
    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 10000);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        absorbReplyCookies(reply);
        reply->deleteLater();
        m_qrLoading = false;
        QJsonParseError error;
        const QJsonObject root = QJsonDocument::fromJson(payload, &error).object();
        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        if (networkError != QNetworkReply::NoError || error.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_qrStatus = tr("登录状态请求失败");
            emit changed();
            return;
        }

        const int code = data.value(QStringLiteral("code")).toInt(-1);
        if (code == 0) {
            const QUrl successUrl(data.value(QStringLiteral("url")).toString());
            const QUrlQuery successQuery(successUrl);
            const QList<QPair<QString, QString> > items = successQuery.queryItems(QUrl::FullyEncoded);
            for (const QPair<QString, QString> &item : items) {
                if ((item.first == QStringLiteral("SESSDATA")
                        || item.first == QStringLiteral("bili_jct")
                        || item.first == QStringLiteral("DedeUserID")
                        || item.first == QStringLiteral("DedeUserID__ckMd5")
                        || item.first == QStringLiteral("sid"))
                        && !item.second.isEmpty())
                    m_cookies.insert(item.first, item.second);
            }
            rebuildCookieHeader();
            if (!saveNativeSession(false)) {
                m_qrStatus = tr("登录成功，但保存原生会话失败");
                emit changed();
                return;
            }
            m_qrActive = false;
            m_qrStatus = tr("登录成功");
            emit changed();
            emit qrLoginSucceeded();
            refresh();
            return;
        }
        if (code == 86101) {
            m_qrStatus = tr("等待扫码");
        } else if (code == 86090) {
            m_qrStatus = tr("已扫码，请在手机上确认");
        } else if (code == 86038) {
            m_qrActive = false;
            m_qrStatus = tr("二维码已过期，请刷新");
        } else {
            const QString message = data.value(QStringLiteral("message")).toString();
            m_qrStatus = message.isEmpty() ? tr("等待登录确认") : message;
        }
        emit changed();
    });
}

void AccountService::cancelQrLogin() {
    m_qrActive = false;
    m_qrUrl.clear();
    m_qrKey.clear();
    m_qrStatus.clear();
    emit changed();
}

void AccountService::logout() {
    cancelQrLogin();
    m_cookies.clear();
    rebuildCookieHeader();
    m_loggedIn = false;
    m_userName.clear();
    m_avatar.clear();
    m_userId.clear();
    m_levelText.clear();
    m_errorMessage = saveNativeSession(true) ? QString() : tr("原生会话清除失败");
    emit changed();
}
