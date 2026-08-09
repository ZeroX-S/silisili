#pragma once

#include <QNetworkAccessManager>
#include <QQmlNetworkAccessManagerFactory>

class BilibiliImageNetworkAccessManager : public QNetworkAccessManager {
    Q_OBJECT

public:
    explicit BilibiliImageNetworkAccessManager(QObject *parent = 0);

protected:
    QNetworkReply *createRequest(Operation operation, const QNetworkRequest &request,
                                 QIODevice *outgoingData = 0) override;
};

class BilibiliImageNetworkFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override;
};
