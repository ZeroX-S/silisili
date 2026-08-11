#pragma once

#include "playbackresolver.h"

#include <QNetworkAccessManager>
#include <QPointer>
#include <QObject>
#include <QVariantList>

class QNetworkReply;

class AccountService;

class LiveResolver : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString sourceUrl READ sourceUrl NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
    Q_PROPERTY(QVariantList qualities READ qualities NOTIFY changed)
    Q_PROPERTY(int selectedQuality READ selectedQuality NOTIFY changed)
    Q_PROPERTY(QString selectedQualityLabel READ selectedQualityLabel NOTIFY changed)
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    explicit LiveResolver(AccountService *accountService,
                          const DirectVideoCapabilities &directCapabilities,
                          QObject *parent = 0);

    bool loading() const { return m_loading; }
    QString sourceUrl() const { return m_sourceUrl; }
    QString errorMessage() const { return m_errorMessage; }
    QVariantList qualities() const { return m_qualities; }
    int selectedQuality() const { return m_selectedQuality; }
    QString selectedQualityLabel() const { return m_selectedQualityLabel; }
    int revision() const { return m_revision; }

public slots:
    // quality <= 0 requests the account-visible original stream. Explicit
    // server qn values remain exact user selections.
    void resolve(const QString &roomId, int quality = 0);
    void cancel();

signals:
    void changed();

private:
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    AccountService *m_accountService;
    DirectVideoCapabilities m_directCapabilities;
    bool m_loading;
    QString m_sourceUrl;
    QString m_errorMessage;
    QVariantList m_qualities;
    int m_selectedQuality;
    QString m_selectedQualityLabel;
    int m_revision;
    int m_requestSerial;
};
