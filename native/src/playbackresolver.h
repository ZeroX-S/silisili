#pragma once

#include <QNetworkAccessManager>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QVariantList>

class AccountService;
class QNetworkReply;
class QNetworkRequest;

class PlaybackResolver : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString sourceUrl READ sourceUrl NOTIFY changed)
    Q_PROPERTY(QString audioUrl READ audioUrl NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
    Q_PROPERTY(QVariantList qualities READ qualities NOTIFY changed)
    Q_PROPERTY(int selectedQuality READ selectedQuality NOTIFY changed)
    Q_PROPERTY(QString selectedQualityLabel READ selectedQualityLabel NOTIFY changed)
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    explicit PlaybackResolver(AccountService *accountService, QObject *parent = 0);

    bool loading() const { return m_loading; }
    QString sourceUrl() const { return m_sourceUrl; }
    QString audioUrl() const { return m_audioUrl; }
    QString errorMessage() const { return m_errorMessage; }
    QVariantList qualities() const { return m_qualities; }
    int selectedQuality() const { return m_selectedQuality; }
    QString selectedQualityLabel() const { return m_selectedQualityLabel; }
    int revision() const { return m_revision; }
    QByteArray cookieHeader() const;

public slots:
    void prefetchVideo(const QString &bvid, const QString &cid, int quality = 80);
    void resolve(const QString &bvid, const QString &cid, int quality = 80);
    void resolvePgc(const QString &aid, const QString &bvid, const QString &cid,
                    const QString &epId, int quality = 80);

signals:
    void changed();
    void videoPrefetched(const QString &bvid, const QString &cid, int quality,
                         bool ready);

private:
    struct CachedResponse {
        QByteArray payload;
        qint64 storedAtMs;
    };

    QString requestKey(bool pgc, const QString &aid, const QString &bvid,
                       const QString &cid, const QString &epId, int quality,
                       bool highQualityAttempt) const;
    QNetworkRequest playurlRequest(bool pgc, const QString &aid, const QString &bvid,
                                   const QString &cid, const QString &epId, int quality,
                                   bool highQualityAttempt) const;
    void publishResponse(bool pgc, const QString &aid, const QString &bvid,
                         const QString &cid, const QString &epId, int quality,
                         bool highQualityAttempt, quint64 requestSerial,
                         const QByteArray &payload, int networkError,
                         bool fromPrefetch);
    void resolveInternal(bool pgc, const QString &aid, const QString &bvid,
                         const QString &cid, const QString &epId, int quality,
                         bool highQualityAttempt);
    void probeQualityCatalog(bool pgc, const QString &aid, const QString &bvid,
                             const QString &cid, const QString &epId,
                             const QString &catalogKey);

    QNetworkAccessManager m_network;
    AccountService *m_accountService;
    bool m_loading;
    QString m_sourceUrl;
    QString m_audioUrl;
    QString m_errorMessage;
    QVariantList m_qualities;
    QString m_qualityCatalogKey;
    int m_selectedQuality;
    QString m_selectedQualityLabel;
    int m_revision;
    quint64 m_requestSerial;
    QPointer<QNetworkReply> m_activeReply;
    QPointer<QNetworkReply> m_catalogReply;
    QHash<QString, CachedResponse> m_prefetchedResponses;
    QHash<QString, QPointer<QNetworkReply> > m_prefetchReplies;
    QString m_waitingPrefetchKey;
    quint64 m_waitingPrefetchSerial;
};
