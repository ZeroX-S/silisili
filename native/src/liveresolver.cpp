#include "liveresolver.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QUrlQuery>

#include <algorithm>
#include <functional>

namespace {
const int kAutomaticOriginalQuality = 10000;

struct LiveCandidate {
    LiveCandidate()
        : codecId(0), currentQuality(0), protocolRank(9), formatRank(9),
          codecRank(9), hardwareCapable(false) {}

    QJsonObject codec;
    QString protocol;
    QString format;
    QString codecName;
    int codecId;
    int currentQuality;
    int protocolRank;
    int formatRank;
    int codecRank;
    bool hardwareCapable;
};

int liveCodecId(const QString &name) {
    if (name == QStringLiteral("avc")) return 7;
    if (name == QStringLiteral("hevc")) return 12;
    return 0;
}

int protocolPreference(const QString &name) {
    if (name == QStringLiteral("http_stream")) return 0;
    if (name == QStringLiteral("http_hls")) return 1;
    return 2;
}

int formatPreference(const QString &name) {
    if (name == QStringLiteral("flv")) return 0;
    if (name == QStringLiteral("fmp4")) return 1;
    if (name == QStringLiteral("ts")) return 2;
    return 3;
}

bool codecHardwareCapable(int codecId,
                          const DirectVideoCapabilities &capabilities) {
    return capabilities.supports(codecId, 1920, 1080, 60)
            || capabilities.supports(codecId, 1920, 1080, 30)
            || capabilities.supports(codecId, 1280, 720, 60)
            || capabilities.supports(codecId, 1280, 720, 30);
}

int qualityPreferenceClass(int currentQuality, int requestedQuality) {
    if (currentQuality == requestedQuality) return 0;
    if (currentQuality > 0 && currentQuality < requestedQuality) return 1;
    if (currentQuality > requestedQuality) return 2;
    return 3;
}

bool betterLiveCandidate(const LiveCandidate &candidate,
                         const LiveCandidate &best,
                         int requestedQuality) {
    if (best.codec.isEmpty()) return true;
    const int candidateQualityClass = qualityPreferenceClass(
                candidate.currentQuality, requestedQuality);
    const int bestQualityClass = qualityPreferenceClass(
                best.currentQuality, requestedQuality);
    if (candidateQualityClass != bestQualityClass)
        return candidateQualityClass < bestQualityClass;
    if (candidate.currentQuality != best.currentQuality) {
        // For a server fallback below the requested qn, retain the closest
        // higher-quality response. Never prefer a response above an explicit
        // request merely because its numeric id is larger.
        return candidateQualityClass == 2
                ? candidate.currentQuality < best.currentQuality
                : candidate.currentQuality > best.currentQuality;
    }
    if (candidate.protocolRank != best.protocolRank)
        return candidate.protocolRank < best.protocolRank;
    if (candidate.formatRank != best.formatRank)
        return candidate.formatRank < best.formatRank;
    return candidate.codecRank < best.codecRank;
}

LiveCandidate chooseLiveCandidate(
        const QJsonArray &streams, int requestedQuality,
        const DirectVideoCapabilities &capabilities) {
    LiveCandidate best;
    const bool hasHardwareCapabilities = capabilities.available();
    for (int pass = 0; pass < (hasHardwareCapabilities ? 2 : 1); ++pass) {
        const bool requireHardware = hasHardwareCapabilities && pass == 0;
        for (const QJsonValue &streamValue : streams) {
            const QJsonObject stream = streamValue.toObject();
            const QString protocol = stream.value(
                        QStringLiteral("protocol_name")).toString();
            for (const QJsonValue &formatValue : stream.value(
                     QStringLiteral("format")).toArray()) {
                const QJsonObject formatObject = formatValue.toObject();
                const QString format = formatObject.value(
                            QStringLiteral("format_name")).toString();
                for (const QJsonValue &codecValue : formatObject.value(
                         QStringLiteral("codec")).toArray()) {
                    const QJsonObject codec = codecValue.toObject();
                    const QString codecName = codec.value(
                                QStringLiteral("codec_name")).toString();
                    const int codecId = liveCodecId(codecName);
                    if (!codecId || codec.value(QStringLiteral("url_info"))
                            .toArray().isEmpty())
                        continue;
                    const bool hardwareCapable = codecHardwareCapable(
                                codecId, capabilities);
                    if (requireHardware && !hardwareCapable) continue;

                    LiveCandidate candidate;
                    candidate.codec = codec;
                    candidate.protocol = protocol;
                    candidate.format = format;
                    candidate.codecName = codecName;
                    candidate.codecId = codecId;
                    candidate.currentQuality = codec.value(
                                QStringLiteral("current_qn")).toInt();
                    candidate.protocolRank = protocolPreference(protocol);
                    candidate.formatRank = formatPreference(format);
                    candidate.codecRank = codecName == QStringLiteral("avc")
                            ? 0 : 1;
                    candidate.hardwareCapable = hardwareCapable;
                    if (betterLiveCandidate(candidate, best,
                                            requestedQuality))
                        best = candidate;
                }
            }
        }
        if (!best.codec.isEmpty()) break;
    }
    return best;
}

QVariantList liveQualityCatalog(
        const QJsonArray &streams,
        const QHash<int, QString> &descriptions,
        const DirectVideoCapabilities &capabilities) {
    QSet<int> qualityIds;
    for (int pass = 0; pass < 2 && qualityIds.isEmpty(); ++pass) {
        const bool requirePreferredCodec = pass == 0;
        for (const QJsonValue &streamValue : streams) {
            const QJsonObject stream = streamValue.toObject();
            for (const QJsonValue &formatValue : stream.value(
                     QStringLiteral("format")).toArray()) {
                const QJsonObject format = formatValue.toObject();
                for (const QJsonValue &codecValue : format.value(
                         QStringLiteral("codec")).toArray()) {
                    const QJsonObject codec = codecValue.toObject();
                    const int codecId = liveCodecId(codec.value(
                                QStringLiteral("codec_name")).toString());
                    if (!codecId) continue;
                    if (codec.value(QStringLiteral("url_info"))
                            .toArray().isEmpty())
                        continue;
                    if (requirePreferredCodec) {
                        const bool preferred = capabilities.available()
                                ? codecHardwareCapable(codecId, capabilities)
                                : codecId == 7;
                        if (!preferred) continue;
                    }
                    for (const QJsonValue &qualityValue : codec.value(
                             QStringLiteral("accept_qn")).toArray()) {
                        const int quality = qualityValue.toInt();
                        if (quality > 0) qualityIds.insert(quality);
                    }
                }
            }
        }
    }
    QList<int> orderedIds = qualityIds.values();
    std::sort(orderedIds.begin(), orderedIds.end(), std::greater<int>());
    QVariantList qualities;
    for (int quality : orderedIds) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), quality);
        item.insert(QStringLiteral("label"), descriptions.value(
                        quality, QString::number(quality)));
        qualities.append(item);
    }
    return qualities;
}
}

LiveResolver::LiveResolver(
        AccountService *accountService,
        const DirectVideoCapabilities &directCapabilities, QObject *parent)
    : QObject(parent), m_accountService(accountService),
      m_directCapabilities(directCapabilities), m_loading(false),
      m_selectedQuality(0), m_revision(0), m_requestSerial(0) {}

void LiveResolver::cancel() {
    ++m_requestSerial;
    if (m_reply) {
        disconnect(m_reply, 0, this, 0);
        m_reply->abort();
        m_reply->deleteLater();
        m_reply.clear();
    }
    m_loading = false;
    m_sourceUrl.clear();
    m_errorMessage.clear();
    m_qualities.clear();
    m_selectedQuality = 0;
    m_selectedQualityLabel.clear();
    emit changed();
}

void LiveResolver::resolve(const QString &roomId, int quality) {
    if (roomId.isEmpty()) return;
    if (m_reply) {
        disconnect(m_reply, 0, this, 0);
        m_reply->abort();
        m_reply->deleteLater();
        m_reply.clear();
    }
    const int requestSerial = ++m_requestSerial;
    const bool automaticOriginal = quality <= 0;
    const int wireQuality = automaticOriginal
            ? kAutomaticOriginalQuality : quality;
    m_loading = true;
    m_sourceUrl.clear();
    m_errorMessage.clear();
    emit changed();

    QUrl url(QStringLiteral("https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("room_id"), roomId);
    query.addQueryItem(QStringLiteral("no_playurl"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("mask"), QStringLiteral("1"));
    query.addQueryItem(QStringLiteral("qn"), QString::number(wireQuality));
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

    qInfo() << "native live: source request started"
            << "roomId" << roomId
            << "requestedQuality" << quality
            << "wireQuality" << wireQuality
            << "automaticOriginal" << automaticOriginal
            << "capabilityAwareCodecSelection" << true;

    QNetworkReply *reply = m_network.get(request);
    NetworkUtils::setReplyTimeout(reply, 12000);
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, requestSerial, quality, wireQuality,
             automaticOriginal]() {
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

        const QJsonArray streams = playUrl.value(QStringLiteral("stream")).toArray();
        const LiveCandidate selected = chooseLiveCandidate(
                    streams, wireQuality, m_directCapabilities);

        const QJsonArray urlInfo = selected.codec.value(
                    QStringLiteral("url_info")).toArray();
        if (selected.codec.isEmpty() || urlInfo.isEmpty()) {
            m_errorMessage = tr("当前地区没有可播放的直播地址");
            emit changed();
            return;
        }

        const QJsonObject endpoint = urlInfo.first().toObject();
        m_sourceUrl = endpoint.value(QStringLiteral("host")).toString()
                    + selected.codec.value(QStringLiteral("base_url")).toString()
                    + endpoint.value(QStringLiteral("extra")).toString();
        m_selectedQuality = selected.currentQuality;
        m_selectedQualityLabel = descriptions.value(m_selectedQuality, QString::number(m_selectedQuality));
        m_qualities = liveQualityCatalog(streams, descriptions,
                                         m_directCapabilities);
        ++m_revision;
        qInfo() << "native live: source resolved, quality" << m_selectedQuality
                << "label" << m_selectedQualityLabel
                << "requestedQuality" << quality
                << "wireQuality" << wireQuality
                << "automaticOriginal" << automaticOriginal
                << "exactServerQuality"
                << (m_selectedQuality == wireQuality)
                << "protocol" << selected.protocol
                << "format" << selected.format
                << "codec" << selected.codecName
                << "hardwareCapable" << selected.hardwareCapable
                << "compatibilityFallback"
                << (m_directCapabilities.available()
                    && !selected.hardwareCapable)
                << "choices" << m_qualities.size();
        emit changed();
    });
}
