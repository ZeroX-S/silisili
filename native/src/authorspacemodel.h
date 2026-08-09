#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QJsonObject>
#include <QSet>
#include <QUrl>
#include <QVariantList>

class AuthorSpaceModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString mid READ mid NOTIFY changed)
    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(QString avatar READ avatar NOTIFY changed)
    Q_PROPERTY(QString signature READ signature NOTIFY changed)
    Q_PROPERTY(QString followerText READ followerText NOTIFY changed)
    Q_PROPERTY(QVariantList videos READ videos NOTIFY changed)
    Q_PROPERTY(QVariantList dynamics READ dynamics NOTIFY changed)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)

public:
    explicit AuthorSpaceModel(QObject *parent = 0);
    bool loading() const { return m_loading; }
    QString mid() const { return m_mid; }
    QString name() const { return m_name; }
    QString avatar() const { return m_avatar; }
    QString signature() const { return m_signature; }
    QString followerText() const { return m_followerText; }
    QVariantList videos() const { return m_videos; }
    QVariantList dynamics() const { return m_dynamics; }
    bool hasMore() const { return m_videoHasMore || m_dynamicHasMore; }
    QString errorMessage() const { return m_errorMessage; }

public slots:
    void load(const QString &mid);
    void loadMore();

signals:
    void changed();

private:
    QNetworkRequest requestFor(const QUrl &url) const;
    void finishRequest(int generation);
    void requestProfile(int generation);
    void requestVideos(int generation, int page);
    void sendVideoRequest(int generation, int page, const QUrl &url);
    void requestDynamics(int generation, const QString &offset);
    static QString normalizedUrl(QString value);
    static QString formatCount(qint64 value);
    static QString jsonId(const QJsonValue &value);
    static void parseMajor(const QJsonObject &major, QVariantMap *item);
    static void parseOriginal(const QJsonObject &original, QVariantMap *item);

    QNetworkAccessManager m_network;
    bool m_loading;
    int m_pendingRequests;
    int m_generation;
    int m_videoPage;
    bool m_videoHasMore;
    bool m_dynamicHasMore;
    QString m_dynamicOffset;
    QSet<QString> m_seenVideos;
    QSet<QString> m_seenDynamics;
    QString m_mid;
    QString m_name;
    QString m_avatar;
    QString m_signature;
    QString m_followerText;
    QVariantList m_videos;
    QVariantList m_dynamics;
    QString m_errorMessage;
};
