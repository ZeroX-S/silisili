#include "networkutils.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QAtomicInt>
#include <QDebug>
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkConfiguration>
#include <QNetworkConfigurationManager>
#include <QNetworkReply>
#include <QRegExp>
#include <QTimer>
#include <QUrlQuery>

namespace {
QString fileKey(const QString &urlString) {
    const QString fileName = QUrl(urlString).fileName();
    const int dot = fileName.indexOf(QLatin1Char('.'));
    return dot > 0 ? fileName.left(dot) : fileName;
}

QByteArray encoded(const QString &value) {
    return QUrl::toPercentEncoding(value);
}

QNetworkConfigurationManager *configurationManager() {
    // The application creates network replies on the GUI thread. Keep one
    // process-wide bearer observer and intentionally let Qt own it until exit;
    // this avoids static QObject destruction after the event dispatcher.
    static QNetworkConfigurationManager *manager = new QNetworkConfigurationManager;
    return manager;
}

QString defaultConfigurationId() {
    const QNetworkConfiguration configuration =
            configurationManager()->defaultConfiguration();
    return configuration.isValid() ? configuration.identifier() : QString();
}

void abortForNetworkChange(QNetworkReply *reply, const QString &reason) {
    if (!reply || reply->isFinished()) return;
    reply->setProperty("silisiliNetworkChanged", true);
    reply->setProperty("silisiliNetworkChangeReason", reason);
    qWarning() << "native network: reply aborted for connectivity change"
               << "reason" << reason << "url" << reply->url();
    reply->abort();
}

QAtomicInt testNetworkReplyOrdinal(0);
}

void NetworkUtils::setReplyTimeout(QNetworkReply *reply, int timeoutMs) {
    if (!reply || timeoutMs <= 0) return;
    const QString startingConfiguration = defaultConfigurationId();
    reply->setProperty("silisiliNetworkConfiguration", startingConfiguration);

    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    QObject::connect(timer, &QTimer::timeout, reply, [reply]() {
        if (reply->isFinished()) return;
        reply->setProperty("silisiliTimedOut", true);
        reply->abort();
    });
    QObject::connect(reply, &QNetworkReply::finished, timer, &QTimer::stop);
    timer->start(timeoutMs);

    QNetworkConfigurationManager *configuration = configurationManager();
    QObject::connect(configuration, &QNetworkConfigurationManager::onlineStateChanged,
                     reply, [reply](bool online) {
        if (!online) abortForNetworkChange(reply, QStringLiteral("offline"));
    });
    QObject::connect(configuration, &QNetworkConfigurationManager::configurationChanged,
                     reply, [reply](const QNetworkConfiguration &) {
        if (!reply || reply->isFinished()) return;
        const QString starting = reply->property(
                    "silisiliNetworkConfiguration").toString();
        const QString current = defaultConfigurationId();
        if (!starting.isEmpty() && !current.isEmpty() && starting != current)
            abortForNetworkChange(reply, QStringLiteral("bearer-changed"));
    });

    QNetworkAccessManager *accessManager = reply->manager();
    if (accessManager) {
        QObject::connect(accessManager, &QNetworkAccessManager::networkAccessibleChanged,
                         reply, [reply](QNetworkAccessManager::NetworkAccessibility state) {
            if (state == QNetworkAccessManager::NotAccessible)
                abortForNetworkChange(reply, QStringLiteral("manager-offline"));
        });
    }

    // Deterministic, one-shot device regression hook. It is accepted only on
    // the dedicated test page, so production and ordinary developer launches
    // cannot accidentally inject a failed request.
    const bool networkRegression = QString::fromLocal8Bit(
                qgetenv("SILISILI_NATIVE_TEST_PAGE")).trimmed().toLower()
            == QStringLiteral("network-recovery");
    bool delayOk = false;
    const int testDelay = QString::fromLocal8Bit(
                qgetenv("SILISILI_NATIVE_TEST_NETWORK_CHANGE_MS")).trimmed()
            .toInt(&delayOk);
    const QString targetUrlFragment = QString::fromLocal8Bit(
                qgetenv("SILISILI_NATIVE_TEST_NETWORK_CHANGE_URL_CONTAINS"))
            .trimmed();
    bool targetReplyOk = false;
    const int configuredTargetReply = QString::fromLocal8Bit(
                qgetenv("SILISILI_NATIVE_TEST_NETWORK_CHANGE_REPLY")).trimmed()
            .toInt(&targetReplyOk);
    const int targetReply = targetReplyOk ? qMax(1, configuredTargetReply) : 1;
    const int replyOrdinal = networkRegression
            ? testNetworkReplyOrdinal.fetchAndAddOrdered(1) + 1 : 0;
    const bool targetMatches = targetUrlFragment.isEmpty()
            ? replyOrdinal == targetReply
            : reply->url().toString().contains(targetUrlFragment);
    if (networkRegression && delayOk && testDelay > 0
            && targetMatches) {
        const int boundedDelay = qBound(1, testDelay, 5000);
        qInfo() << "native network: test connectivity transition scheduled"
                << boundedDelay << "ms"
                << "replyOrdinal" << replyOrdinal
                << "urlContains" << targetUrlFragment << reply->url();
        QTimer::singleShot(boundedDelay, reply, [reply]() {
            abortForNetworkChange(reply, QStringLiteral("test-transition"));
        });
    }
}

bool NetworkUtils::replyTimedOut(const QNetworkReply *reply) {
    return reply && reply->property("silisiliTimedOut").toBool();
}

bool NetworkUtils::replyNetworkChanged(const QNetworkReply *reply) {
    return reply && reply->property("silisiliNetworkChanged").toBool();
}

QString NetworkUtils::wbiMixinKey(const QJsonObject &navData) {
    const QJsonObject wbi = navData.value(QStringLiteral("wbi_img")).toObject();
    const QString source = fileKey(wbi.value(QStringLiteral("img_url")).toString())
            + fileKey(wbi.value(QStringLiteral("sub_url")).toString());
    if (source.size() < 64) return QString();
    static const int table[] = {
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    };
    QString mixed;
    mixed.reserve(32);
    for (int index = 0; index < 32; ++index)
        mixed.append(source.at(table[index]));
    return mixed;
}

QUrl NetworkUtils::signWbiUrl(const QUrl &url, const QString &mixinKey) {
    if (mixinKey.isEmpty()) return url;
    QMap<QString, QString> sorted;
    const QList<QPair<QString, QString> > items = QUrlQuery(url).queryItems(QUrl::FullyDecoded);
    for (const QPair<QString, QString> &item : items) {
        QString value = item.second;
        value.remove(QRegExp(QStringLiteral("[!'()*]")));
        sorted.insert(item.first, value);
    }
    sorted.insert(QStringLiteral("wts"), QString::number(
                      QDateTime::currentMSecsSinceEpoch() / 1000));

    QByteArray queryBytes;
    for (auto it = sorted.constBegin(); it != sorted.constEnd(); ++it) {
        if (!queryBytes.isEmpty()) queryBytes.append('&');
        queryBytes.append(encoded(it.key()));
        queryBytes.append('=');
        queryBytes.append(encoded(it.value()));
    }
    const QByteArray digest = QCryptographicHash::hash(
                queryBytes + mixinKey.toUtf8(), QCryptographicHash::Md5).toHex();
    queryBytes.append("&w_rid=");
    queryBytes.append(digest);

    QUrl result(url);
    result.setQuery(QString::fromLatin1(queryBytes));
    return result;
}
