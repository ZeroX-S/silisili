#pragma once

#include <QObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QUrl>

class QJsonObject;
class QNetworkReply;

class AccountService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY changed)
    Q_PROPERTY(QString userName READ userName NOTIFY changed)
    Q_PROPERTY(QString avatar READ avatar NOTIFY changed)
    Q_PROPERTY(QString userId READ userId NOTIFY changed)
    Q_PROPERTY(QString levelText READ levelText NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
    Q_PROPERTY(bool qrLoading READ qrLoading NOTIFY changed)
    Q_PROPERTY(bool qrActive READ qrActive NOTIFY changed)
    Q_PROPERTY(QString qrUrl READ qrUrl NOTIFY changed)
    Q_PROPERTY(QString qrStatus READ qrStatus NOTIFY changed)
    Q_PROPERTY(bool wbiReady READ wbiReady NOTIFY changed)
public:
    explicit AccountService(QObject *parent = 0);
    static AccountService *instance();
    bool loading() const { return m_loading; } bool loggedIn() const { return m_loggedIn; }
    QString userName() const { return m_userName; } QString avatar() const { return m_avatar; }
    QString userId() const { return m_userId; } QString levelText() const { return m_levelText; }
    QString errorMessage() const { return m_errorMessage; }
    bool qrLoading() const { return m_qrLoading; }
    bool qrActive() const { return m_qrActive; }
    QString qrUrl() const { return m_qrUrl; }
    QString qrStatus() const { return m_qrStatus; }
    bool wbiReady() const { return !m_wbiMixinKey.isEmpty(); }
    QByteArray cookieHeader() const { return m_cookieHeader; }
    QString csrfToken() const { return m_csrfToken; }
    QUrl signedWbiUrl(const QUrl &url) const;
public slots:
    void refresh();
    bool reportPlaybackHistory(const QString &aid, const QString &bvid,
                               const QString &cid, const QString &epId,
                               bool pgc, int progress, int duration,
                               const QString &reason);
    void startQrLogin();
    void pollQrLogin();
    void cancelQrLogin();
    void logout();
signals:
    void changed();
    void qrLoginSucceeded();
private:
    void loadSnapshot();
    void loadCookies(const QJsonObject &cookies);
    void rebuildCookieHeader();
    void absorbReplyCookies(QNetworkReply *reply);
    bool saveNativeSession(bool loggedOut);
    void verifyPlaybackHistory(const QString &bvid, const QString &cid,
                               int minimumProgress, int attempt);
    static AccountService *s_instance;
    QNetworkAccessManager m_network;
    QMap<QString, QString> m_cookies;
    QByteArray m_cookieHeader;
    QString m_csrfToken;
    bool m_loading, m_loggedIn, m_qrLoading, m_qrActive;
    QString m_userName, m_avatar, m_userId, m_levelText, m_errorMessage;
    QString m_qrUrl, m_qrKey, m_qrStatus;
    QString m_wbiMixinKey;
    bool m_verifyPlaybackHistoryForTest;
};
