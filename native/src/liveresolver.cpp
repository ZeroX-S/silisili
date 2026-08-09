#include "liveresolver.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

LiveResolver::LiveResolver(AccountService *accountService, QObject *parent)
    : QObject(parent), m_accountService(accountService), m_loading(false),
      m_selectedQuality(0), m_revision(0), m_requestSerial(0) {}

void LiveResolver::resolve(const QString &roomId, int quality) {
    if (roomId.isEmpty()) return;
    if (m_reply) {
        disconnect(m_reply, 0, this, 0);
        m_reply->abort();
        m_reply->deleteLater();
        m_reply.clear();
    }
    const int requestSerial = ++m_requestSerial;
    m_loading = true;
    m_sourceUrl.clear();
    m_errorMessage.clear();
    emit changed();

    QUrl url(QStringLiteral("https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("room_id"), roomId);
    query.addQueryItem(QStringLiteral("no_playurl"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("mask"), QStringLiteral("1"));
    query.addQueryItem(QStringLiteral("qn"), QString::number(quality));
    query.addQueryItem(QStringLiteral("platform"), QStringLiteral("web"));
    query.addQueryItem(QStringLiteral("protocol"), QStringLiteral("0,1"));
    query.addQueryItem(QStringLiteral("format"), QStringLiteral("0,1,2"));
    query.addQueryItem(QStringLiteral("codec"), QStringLiteral("0,1,2"));
    query.addQueryItem(QStringLiteral("dolby"), QStringLiteral("5"));
    query.addQueryItem(QStringLiteral("ptype"), QStringLiteral("8"));
    query.addQueryItem(QStringLiteral("panorama"), QStringLiteral("1"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", QByteArray("https://live.bilibili.com/") + roomId.toUtf8());
    request.setRawHeader("Accept-Encoding", "identity");
    if (m_accountService && !m_accountService->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", m_accountService->cookieHeader());

    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestSerial]() {
        if (requestSerial != m_requestSerial) {
            reply->deleteLater();
            return;
        }
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        if (m_reply == reply) m_reply.clear();
        m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_errorMessage = tr("直播地址请求失败");
            emit changed();
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            m_errorMessage = tr("直播地址解析失败");
            emit changed();
            return;
        }

        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        if (data.value(QStringLiteral("is_locked")).toBool()) {
            m_errorMessage = tr("这个直播间已被封禁");
            emit changed();
            return;
        }
        if (data.value(QStringLiteral("live_status")).toInt() != 1) {
            m_errorMessage = tr("主播当前未开播");
            emit changed();
            return;
        }

        const QJsonObject playUrl = data.value(QStringLiteral("playurl_info")).toObject()
                                        .value(QStringLiteral("playurl")).toObject();
        QHash<int, QString> descriptions;
        for (const QJsonValue &value : playUrl.value(QStringLiteral("g_qn_desc")).toArray()) {
            const QJsonObject item = value.toObject();
            descriptions.insert(item.value(QStringLiteral("qn")).toInt(),
                                item.value(QStringLiteral("desc")).toString());
        }

        QJsonObject selectedCodec;
        const QJsonArray streams = playUrl.value(QStringLiteral("stream")).toArray();
        for (int pass = 0; pass < 2 && selectedCodec.isEmpty(); ++pass) {
            for (const QJsonValue &streamValue : streams) {
                const QJsonObject stream = streamValue.toObject();
                if (pass == 0 && stream.value(QStringLiteral("protocol_name")).toString() != QStringLiteral("http_stream"))
                    continue;
                for (const QJsonValue &formatValue : stream.value(QStringLiteral("format")).toArray()) {
                    const QJsonObject format = formatValue.toObject();
                    if (pass == 0 && format.value(QStringLiteral("format_name")).toString() != QStringLiteral("flv"))
                        continue;
                    for (const QJsonValue &codecValue : format.value(QStringLiteral("codec")).toArray()) {
                        const QJsonObject codec = codecValue.toObject();
                        if (codec.value(QStringLiteral("codec_name")).toString() == QStringLiteral("avc") &&
                            !codec.value(QStringLiteral("url_info")).toArray().isEmpty()) {
                            selectedCodec = codec;
                            break;
                        }
                    }
                    if (!selectedCodec.isEmpty()) break;
                }
                if (!selectedCodec.isEmpty()) break;
            }
        }

        const QJsonArray urlInfo = selectedCodec.value(QStringLiteral("url_info")).toArray();
        if (selectedCodec.isEmpty() || urlInfo.isEmpty()) {
            m_errorMessage = tr("当前地区没有可播放的直播地址");
            emit changed();
            return;
        }

        const QJsonObject endpoint = urlInfo.first().toObject();
        m_sourceUrl = endpoint.value(QStringLiteral("host")).toString()
                    + selectedCodec.value(QStringLiteral("base_url")).toString()
                    + endpoint.value(QStringLiteral("extra")).toString();
        m_selectedQuality = selectedCodec.value(QStringLiteral("current_qn")).toInt();
        m_selectedQualityLabel = descriptions.value(m_selectedQuality, QString::number(m_selectedQuality));
        m_qualities.clear();
        for (const QJsonValue &value : selectedCodec.value(QStringLiteral("accept_qn")).toArray()) {
            const int id = value.toInt();
            QVariantMap item;
            item.insert(QStringLiteral("id"), id);
            item.insert(QStringLiteral("label"), descriptions.value(id, QString::number(id)));
            m_qualities.append(item);
        }
        ++m_revision;
        qInfo() << "native live: source resolved, quality" << m_selectedQuality
                << "choices" << m_qualities.size();
        emit changed();
    });
}
