#include "playbackresolver.h"

#include "accountservice.h"
#include "networkutils.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QDebug>
#include <QHash>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QStringList>
#include <QTimer>
#include <QUrlQuery>

#include <algorithm>

namespace {
const int kDefaultQuality = 80;             // Restore the normal 1080P path.
const int kProgressiveFallbackQuality = 64; // Keep the old reliable 720P progressive path.
const int kCapabilityProbeQuality = 127;    // Ask for the complete account-visible DASH ladder.
const int kMaximumDirectSourceWidth = 4096;
const int kMaximumDirectSourceHeight = 2304;
const qint64 kMaximumDirectSourcePixels = 4096LL * 2304LL;

int normalizedQuality(int requestedQuality) {
    return requestedQuality > 0
            ? qMin(requestedQuality, kCapabilityProbeQuality) : kDefaultQuality;
}

QString dashMediaUrl(const QJsonObject &media) {
    QString url = media.value(QStringLiteral("base_url")).toString();
    if (url.isEmpty()) url = media.value(QStringLiteral("baseUrl")).toString();
    if (url.isEmpty()) url = media.value(QStringLiteral("url")).toString();
    return url;
}

int codecRank(int codecid) {
    // Prefer AVC/H.264 for the current Sailfish/mpv path, then HEVC, then AV1.
    if (codecid == 7) return 0;
    if (codecid == 12) return 1;
    if (codecid == 13) return 2;
    return 9;
}

bool isDirectRouteCodec(int codecid) {
    // The direct droidmedia path currently maps AVC and HEVC. Bilibili's 8K
    // representation is commonly AV1; handing that to libmpv software decode
    // on a phone can consume gigabytes before the first frame is presented.
    return codecid == 7 || codecid == 12;
}

int dashFramesPerSecond(const QJsonObject &video) {
    const QJsonValue value = video.value(QStringLiteral("frame_rate"));
    if (value.isDouble()) return qRound(value.toDouble());
    const QString text = value.toString().trimmed();
    if (text.isEmpty()) return 60; // Fail closed for an unknown UHD cadence.
    const QStringList parts = text.split(QLatin1Char('/'));
    bool numeratorOk = false;
    const double numerator = parts.value(0).toDouble(&numeratorOk);
    bool denominatorOk = true;
    const double denominator = parts.size() > 1
            ? parts.value(1).toDouble(&denominatorOk) : 1.0;
    if (!numeratorOk || !denominatorOk || denominator <= 0.0) return 60;
    return qMax(1, qRound(numerator / denominator));
}

bool isWithinDirectFrameBudget(const QJsonObject &video,
                               const DirectVideoCapabilities &capabilities) {
    const int width = video.value(QStringLiteral("width")).toInt();
    const int height = video.value(QStringLiteral("height")).toInt();
    if (width <= 0 || height <= 0) return false;
    const qint64 pixels = static_cast<qint64>(width) * static_cast<qint64>(height);
    const int longSide = qMax(width, height);
    const int shortSide = qMin(width, height);
    const bool insideApplicationBudget = longSide <= kMaximumDirectSourceWidth
            && shortSide <= kMaximumDirectSourceHeight
            && pixels <= kMaximumDirectSourcePixels;
    if (!insideApplicationBudget) return false;
    if (!capabilities.available()) {
        // A device without a positive OMX capability result may still use the
        // existing software fallback, but never feed it phone-hostile UHD.
        return longSide <= 1920 && shortSide <= 1080;
    }
    return capabilities.supports(video.value(QStringLiteral("codecid")).toInt(),
                                 width, height, dashFramesPerSecond(video));
}

bool isBetterVideo(const QJsonObject &candidate, const QJsonObject &best) {
    if (best.isEmpty()) return true;
    const int candidateQuality = candidate.value(QStringLiteral("id")).toInt();
    const int bestQuality = best.value(QStringLiteral("id")).toInt();
    if (candidateQuality != bestQuality) return candidateQuality > bestQuality;

    const int candidateRank = codecRank(candidate.value(QStringLiteral("codecid")).toInt());
    const int bestRank = codecRank(best.value(QStringLiteral("codecid")).toInt());
    if (candidateRank != bestRank) return candidateRank < bestRank;

    const int candidateHeight = candidate.value(QStringLiteral("height")).toInt();
    const int bestHeight = best.value(QStringLiteral("height")).toInt();
    if (candidateHeight != bestHeight) return candidateHeight > bestHeight;

    return candidate.value(QStringLiteral("bandwidth")).toInt()
            > best.value(QStringLiteral("bandwidth")).toInt();
}

QJsonObject chooseDashVideo(const QJsonArray &videos, int requestedQuality,
                            const DirectVideoCapabilities &capabilities,
                            int operationalMaximumQuality,
                            bool *ultraHdGuardApplied) {
    const int normalizedRequestedQuality = normalizedQuality(requestedQuality);
    const int desiredQuality = qMin(normalizedRequestedQuality,
                                    operationalMaximumQuality);
    QJsonObject best;
    int highestRejectedQuality = normalizedRequestedQuality > desiredQuality
            ? normalizedRequestedQuality : 0;

    for (const QJsonValue &value : videos) {
        const QJsonObject video = value.toObject();
        if (dashMediaUrl(video).isEmpty()) continue;
        const int quality = video.value(QStringLiteral("id")).toInt();
        if (quality <= 0 || quality > desiredQuality) continue;
        if (!isDirectRouteCodec(video.value(QStringLiteral("codecid")).toInt())
                || !isWithinDirectFrameBudget(video, capabilities)) {
            highestRejectedQuality = qMax(highestRejectedQuality, quality);
            continue;
        }
        if (isBetterVideo(video, best)) best = video;
    }
    if (ultraHdGuardApplied) {
        *ultraHdGuardApplied = highestRejectedQuality > 0
                && (best.isEmpty()
                    || highestRejectedQuality > best.value(QStringLiteral("id")).toInt());
    }
    // Never silently substitute a representation above the requested id.
    // A server can return only its current highest DASH item; choosing that
    // item made the 1080P row actually play 1080P60. The exact-qn request or
    // the progressive fallback below must decide the replacement instead.
    return best;
}

QJsonObject chooseDashAudio(const QJsonArray &audios) {
    const int preferredIds[] = {30280, 30232, 30216};
    for (int preferredId : preferredIds) {
        for (const QJsonValue &value : audios) {
            const QJsonObject audio = value.toObject();
            if (audio.value(QStringLiteral("id")).toInt() == preferredId
                    && !dashMediaUrl(audio).isEmpty()) {
                return audio;
            }
        }
    }
    QJsonObject best;
    for (const QJsonValue &value : audios) {
        const QJsonObject audio = value.toObject();
        if (dashMediaUrl(audio).isEmpty()) continue;
        if (best.isEmpty()
                || audio.value(QStringLiteral("bandwidth")).toInt()
                   > best.value(QStringLiteral("bandwidth")).toInt()) {
            best = audio;
        }
    }
    return best;
}

QHash<int, QString> qualityLabelsFromData(const QJsonObject &data, QVariantList *qualities) {
    QHash<int, QString> labelsById;
    const QJsonArray ids = data.value(QStringLiteral("accept_quality")).toArray();
    const QJsonArray labels = data.value(QStringLiteral("accept_description")).toArray();
    for (int index = 0; index < ids.size(); ++index) {
        QVariantMap item;
        const int id = ids.at(index).toInt();
        const QString label = index < labels.size() ? labels.at(index).toString() : QString::number(id);
        labelsById.insert(id, label);
        if (qualities && id > 0) {
            item.insert(QStringLiteral("id"), id);
            item.insert(QStringLiteral("label"), label);
            qualities->append(item);
        }
    }
    return labelsById;
}

QVariantList mergedQualityCatalog(const QVariantList &known,
                                  const QVariantList &discovered) {
    QHash<int, QString> labels;
    const QVariantList sources[] = {known, discovered};
    for (const QVariantList &source : sources) {
        for (const QVariant &value : source) {
            const QVariantMap item = value.toMap();
            const int id = item.value(QStringLiteral("id")).toInt();
            if (id <= 0) continue;
            labels.insert(id, item.value(QStringLiteral("label"),
                                         QString::number(id)).toString());
        }
    }

    QList<int> ids = labels.keys();
    std::sort(ids.begin(), ids.end(), std::greater<int>());
    QVariantList merged;
    for (int id : ids) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), id);
        item.insert(QStringLiteral("label"), labels.value(id));
        merged.append(item);
    }
    return merged;
}

QString fallbackQualityLabel(const QHash<int, QString> &labelsById, int quality, int height) {
    QString label = labelsById.value(quality);
    if (!label.isEmpty()) return label;
    if (height > 0) return QStringLiteral("%1P").arg(height);
    return QString::number(quality);
}
}

DirectVideoCapabilities::DirectVideoCapabilities()
    : avc30MaximumWidth(0), avc30MaximumHeight(0),
      avc60MaximumWidth(0), avc60MaximumHeight(0),
      hevc30MaximumWidth(0), hevc30MaximumHeight(0),
      hevc60MaximumWidth(0), hevc60MaximumHeight(0) {}

bool DirectVideoCapabilities::available() const {
    return (avc30MaximumWidth > 0 && avc30MaximumHeight > 0)
            || (avc60MaximumWidth > 0 && avc60MaximumHeight > 0)
            || (hevc30MaximumWidth > 0 && hevc30MaximumHeight > 0)
            || (hevc60MaximumWidth > 0 && hevc60MaximumHeight > 0);
}

bool DirectVideoCapabilities::supports(int codecId, int width, int height,
                                       int framesPerSecond) const {
    const bool highCadence = framesPerSecond > 30;
    const int maximumWidth = codecId == 7
            ? (highCadence ? avc60MaximumWidth : avc30MaximumWidth)
            : codecId == 12
              ? (highCadence ? hevc60MaximumWidth : hevc30MaximumWidth) : 0;
    const int maximumHeight = codecId == 7
            ? (highCadence ? avc60MaximumHeight : avc30MaximumHeight)
            : codecId == 12
              ? (highCadence ? hevc60MaximumHeight : hevc30MaximumHeight) : 0;
    if (maximumWidth <= 0 || maximumHeight <= 0) return false;
    const int longSide = qMax(width, height);
    const int shortSide = qMin(width, height);
    return longSide <= qMax(maximumWidth, maximumHeight)
            && shortSide <= qMin(maximumWidth, maximumHeight)
            && static_cast<qint64>(width) * static_cast<qint64>(height)
               <= static_cast<qint64>(maximumWidth) * maximumHeight;
}

PlaybackResolver::PlaybackResolver(
        AccountService *accountService,
        const DirectVideoCapabilities &directCapabilities, QObject *parent)
    : QObject(parent), m_accountService(accountService),
      m_directCapabilities(directCapabilities), m_loading(false), m_selectedQuality(0),
      m_operationalMaximumQuality(116),
      m_revision(0), m_requestSerial(0), m_waitingPrefetchSerial(0) {
    QSettings settings;
    const bool allowUnverifiedUltraHd =
            qgetenv("SILISILI_NATIVE_ALLOW_UNVERIFIED_ULTRAHD")
            == QByteArrayLiteral("1");
    const int safeDefaultQuality = allowUnverifiedUltraHd ? 127 : 116;
    if (qgetenv("SILISILI_NATIVE_TEST_RESET_OPERATIONAL_QUALITY")
            == QByteArrayLiteral("1")) {
        settings.remove(QStringLiteral("playback/operationalMaximumQualityV2"));
        settings.sync();
        qInfo() << "native player: operational quality ceiling reset for regression";
    }
    m_operationalMaximumQuality = qBound(
                64, settings.value(QStringLiteral(
                    "playback/operationalMaximumQualityV2"),
                    safeDefaultQuality).toInt(), 127);
    qInfo() << "native player: persisted operational quality ceiling"
            << m_operationalMaximumQuality
            << "safeDefault" << safeDefaultQuality
            << "unverifiedUltraHdOptIn" << allowUnverifiedUltraHd;
}

void PlaybackResolver::setOperationalMaximumQuality(int quality,
                                                     const QString &reason) {
    const int boundedQuality = qBound(64, quality, 127);
    if (boundedQuality >= m_operationalMaximumQuality) return;
    m_operationalMaximumQuality = boundedQuality;
    QSettings settings;
    settings.setValue(QStringLiteral("playback/operationalMaximumQualityV2"),
                      m_operationalMaximumQuality);
    settings.sync();
    qWarning() << "native player: operational quality ceiling lowered"
               << "maximumQuality" << m_operationalMaximumQuality
               << "reason" << reason << "persisted" << true;
}

QByteArray PlaybackResolver::cookieHeader() const {
    return m_accountService ? m_accountService->cookieHeader() : QByteArray();
}

QString PlaybackResolver::requestKey(bool pgc, const QString &aid, const QString &bvid,
                                     const QString &cid, const QString &epId, int quality,
                                     bool highQualityAttempt) const {
    return QStringLiteral("%1|%2|%3|%4|%5|%6|%7")
            .arg(pgc ? QStringLiteral("pgc") : QStringLiteral("video"), aid, bvid, cid, epId)
            .arg(quality)
            .arg(highQualityAttempt ? 1 : 0);
}

QNetworkRequest PlaybackResolver::playurlRequest(bool pgc, const QString &aid,
                                                 const QString &bvid, const QString &cid,
                                                 const QString &epId, int quality,
                                                 bool highQualityAttempt) const {
    QUrl url(pgc ? QStringLiteral("https://api.bilibili.com/pgc/player/web/playurl")
                 : highQualityAttempt
                   ? QStringLiteral("https://api.bilibili.com/x/player/wbi/playurl")
                   : QStringLiteral("https://api.bilibili.com/x/player/playurl"));
    QUrlQuery query;
    if (!bvid.isEmpty()) query.addQueryItem(QStringLiteral("bvid"), bvid);
    if (pgc && !aid.isEmpty()) query.addQueryItem(QStringLiteral("avid"), aid);
    if (pgc && !epId.isEmpty()) query.addQueryItem(QStringLiteral("ep_id"), epId);
    query.addQueryItem(QStringLiteral("cid"), cid);
    // Media requests always use the user's exact qn. A separate asynchronous
    // capability probe requests 127 only to discover the entitled menu; its
    // media URLs are never published into the playback session.
    const int wireQuality = quality;
    query.addQueryItem(QStringLiteral("qn"), QString::number(wireQuality));
    query.addQueryItem(QStringLiteral("fnval"), highQualityAttempt
                       ? QStringLiteral("4048") : QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("fnver"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("fourk"), highQualityAttempt
                       ? QStringLiteral("1") : QStringLiteral("0"));
    if (highQualityAttempt && pgc) {
        query.addQueryItem(QStringLiteral("gaia_source"), QString());
        query.addQueryItem(QStringLiteral("from_client"), QStringLiteral("PC_APP"));
        query.addQueryItem(QStringLiteral("is_main_page"), QStringLiteral("false"));
        query.addQueryItem(QStringLiteral("need_fragment"), QStringLiteral("false"));
        query.addQueryItem(QStringLiteral("isGaiaAvoided"), QStringLiteral("false"));
        query.addQueryItem(QStringLiteral("voice_balance"), QStringLiteral("1"));
        query.addQueryItem(QStringLiteral("drm_tech_type"), QStringLiteral("3"));
    } else if (highQualityAttempt) {
        query.addQueryItem(QStringLiteral("gaia_source"), QStringLiteral("view-card"));
        query.addQueryItem(QStringLiteral("from_client"), QStringLiteral("BROWSER"));
        query.addQueryItem(QStringLiteral("is_main_page"), QStringLiteral("false"));
        query.addQueryItem(QStringLiteral("need_fragment"), QStringLiteral("false"));
        query.addQueryItem(QStringLiteral("isGaiaAvoided"), QStringLiteral("true"));
        query.addQueryItem(QStringLiteral("voice_balance"), QStringLiteral("1"));
        query.addQueryItem(QStringLiteral("web_location"), QStringLiteral("1315873"));
    }
    url.setQuery(query);
    if (!pgc && highQualityAttempt && m_accountService
            && m_accountService->wbiReady())
        url = m_accountService->signedWbiUrl(url);

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    const QByteArray referer = pgc && !epId.isEmpty()
        ? QStringLiteral("https://www.bilibili.com/bangumi/play/ep%1").arg(epId).toUtf8()
        : QByteArray("https://www.bilibili.com/");
    request.setRawHeader("Referer", referer);
    request.setRawHeader("Accept-Encoding", "identity");
    if (m_accountService && !m_accountService->cookieHeader().isEmpty())
        request.setRawHeader("Cookie", m_accountService->cookieHeader());
    return request;
}

void PlaybackResolver::prefetchVideo(const QString &bvid, const QString &cid, int quality) {
    if (bvid.isEmpty() || cid.isEmpty()) return;
    const int requestedQuality = normalizedQuality(quality);
    // Every advertised profile is selected through exact-qn DASH. The old
    // 64-and-below progressive branch could answer a 720P selection with a
    // real quality id of 16. Progressive remains only the bounded fallback
    // reached explicitly from publishResponse() after a DASH failure.
    const bool highQualityAttempt = true;
    const QString key = requestKey(false, QString(), bvid, cid, QString(),
                                   requestedQuality, highQualityAttempt);
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const auto cached = m_prefetchedResponses.constFind(key);
    if (cached != m_prefetchedResponses.constEnd()
            && now - cached.value().storedAtMs < 5 * 60 * 1000) {
        emit videoPrefetched(bvid, cid, requestedQuality, true);
        return;
    }
    if (m_prefetchReplies.contains(key) && m_prefetchReplies.value(key)) return;

    QNetworkReply *reply = m_network.get(playurlRequest(false, QString(), bvid, cid,
                                                       QString(), requestedQuality,
                                                       highQualityAttempt));
    m_prefetchReplies.insert(key, reply);
    NetworkUtils::setReplyTimeout(reply, 9000);
    qInfo() << "native player: visible-card playurl prefetch started"
            << bvid << cid << "quality" << requestedQuality;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, key, bvid, cid, requestedQuality, highQualityAttempt]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        m_prefetchReplies.remove(key);

        bool ready = false;
        if (networkError == QNetworkReply::NoError) {
            QJsonParseError parseError;
            const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
            ready = parseError.error == QJsonParseError::NoError
                    && root.value(QStringLiteral("code")).toInt(-1) == 0;
            if (ready) {
                CachedResponse response;
                response.payload = payload;
                response.storedAtMs = QDateTime::currentMSecsSinceEpoch();
                m_prefetchedResponses.insert(key, response);
            }
        }
        qInfo() << "native player: visible-card playurl prefetch finished"
                << bvid << cid << "quality" << requestedQuality
                << "ready" << ready << "bytes" << payload.size();
        emit videoPrefetched(bvid, cid, requestedQuality, ready);

        if (m_waitingPrefetchKey != key) return;
        const quint64 serial = m_waitingPrefetchSerial;
        m_waitingPrefetchKey.clear();
        m_waitingPrefetchSerial = 0;
        if (ready) {
            publishResponse(false, QString(), bvid, cid, QString(), requestedQuality,
                            highQualityAttempt, serial, payload,
                            QNetworkReply::NoError, true);
        } else if (serial == m_requestSerial) {
            resolveInternal(false, QString(), bvid, cid, QString(), requestedQuality,
                            highQualityAttempt);
        }
    });
}

void PlaybackResolver::resolve(const QString &bvid, const QString &cid, int quality) {
    const int requestedQuality = normalizedQuality(quality);
    resolveInternal(false, QString(), bvid, cid, QString(), requestedQuality, true);
}

void PlaybackResolver::resolvePgc(const QString &aid, const QString &bvid,
                                  const QString &cid, const QString &epId, int quality) {
    const int requestedQuality = normalizedQuality(quality);
    resolveInternal(true, aid, bvid, cid, epId, requestedQuality, true);
}

void PlaybackResolver::resolveInternal(bool pgc, const QString &aid, const QString &bvid,
                                       const QString &cid, const QString &epId, int quality,
                                       bool highQualityAttempt) {
    if (cid.isEmpty() || (!pgc && bvid.isEmpty())
            || (pgc && aid.isEmpty() && bvid.isEmpty())) return;

    const QString catalogKey = QStringLiteral("%1|%2|%3|%4|%5")
            .arg(pgc ? QStringLiteral("pgc") : QStringLiteral("video"),
                 aid, bvid, cid, epId);
    if (m_qualityCatalogKey != catalogKey) {
        if (m_catalogReply) m_catalogReply->abort();
        m_qualityCatalogKey = catalogKey;
        m_qualities.clear();
        qInfo() << "native player: quality catalog reset for source"
                << catalogKey;
        probeQualityCatalog(pgc, aid, bvid, cid, epId, catalogKey);
    }

    // Page transitions and episode taps may replace a request before its
    // response arrives.  Always let the newest selection win: aborting the
    // previous reply saves radio/JSON work, while the serial also protects us
    // against a queued finished() signal from publishing stale media URLs.
    const quint64 requestSerial = ++m_requestSerial;
    if (m_activeReply) m_activeReply->abort();

    m_loading = true;
    m_sourceUrl.clear();
    m_audioUrl.clear();
    m_errorMessage.clear();
    emit changed();

    const QString key = requestKey(pgc, aid, bvid, cid, epId, quality,
                                   highQualityAttempt);
    const auto cached = m_prefetchedResponses.constFind(key);
    if (cached != m_prefetchedResponses.constEnd()
            && QDateTime::currentMSecsSinceEpoch() - cached.value().storedAtMs
               < 5 * 60 * 1000) {
        const QByteArray payload = cached.value().payload;
        qInfo() << "native player: prefetched playurl cache hit"
                << bvid << cid << "quality" << quality;
        QTimer::singleShot(0, this,
                           [this, pgc, aid, bvid, cid, epId, quality,
                            highQualityAttempt, requestSerial, payload]() {
            publishResponse(pgc, aid, bvid, cid, epId, quality,
                            highQualityAttempt, requestSerial, payload,
                            QNetworkReply::NoError, true);
        });
        return;
    }
    if (!pgc && m_prefetchReplies.contains(key) && m_prefetchReplies.value(key)) {
        m_waitingPrefetchKey = key;
        m_waitingPrefetchSerial = requestSerial;
        qInfo() << "native player: joining visible-card playurl prefetch"
                << bvid << cid << "quality" << quality;
        return;
    }

    QNetworkReply *reply = m_network.get(playurlRequest(pgc, aid, bvid, cid,
                                                       epId, quality,
                                                       highQualityAttempt));
    NetworkUtils::setReplyTimeout(reply, 9000);
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, pgc, aid, bvid, cid, epId, quality, highQualityAttempt, requestSerial]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        if (m_activeReply == reply) m_activeReply.clear();
        publishResponse(pgc, aid, bvid, cid, epId, quality, highQualityAttempt,
                        requestSerial, payload, networkError, false);
    });
}

void PlaybackResolver::probeQualityCatalog(bool pgc, const QString &aid,
                                           const QString &bvid, const QString &cid,
                                           const QString &epId,
                                           const QString &catalogKey) {
    QNetworkReply *reply = m_network.get(playurlRequest(
                pgc, aid, bvid, cid, epId, kCapabilityProbeQuality, true));
    m_catalogReply = reply;
    NetworkUtils::setReplyTimeout(reply, 9000);
    qInfo() << "native player: quality capability probe started"
            << "qn" << kCapabilityProbeQuality << "source" << catalogKey;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, pgc, catalogKey]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        reply->deleteLater();
        if (m_catalogReply == reply) m_catalogReply.clear();
        if (m_qualityCatalogKey != catalogKey) return;
        if (networkError != QNetworkReply::NoError) {
            qWarning() << "native player: quality capability probe failed"
                       << "networkError" << networkError
                       << "source" << catalogKey;
            return;
        }

        QJsonParseError parseError;
        const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
        if (parseError.error != QJsonParseError::NoError
                || root.value(QStringLiteral("code")).toInt(-1) != 0) {
            qWarning() << "native player: quality capability probe rejected"
                       << "code" << root.value(QStringLiteral("code")).toInt(-1)
                       << "source" << catalogKey;
            return;
        }

        const QJsonObject data = root.value(pgc ? QStringLiteral("result")
                                                : QStringLiteral("data")).toObject();
        QVariantList discovered;
        qualityLabelsFromData(data, &discovered);
        const int previousCount = m_qualities.size();
        m_qualities = mergedQualityCatalog(m_qualities, discovered);
        qInfo() << "native player: quality capability probe completed"
                << "qn" << kCapabilityProbeQuality
                << "discovered" << discovered.size()
                << "previousChoices" << previousCount
                << "retainedChoices" << m_qualities.size()
                << "mediaPublished" << false
                << "source" << catalogKey;
        emit changed();
    });
}

void PlaybackResolver::publishResponse(bool pgc, const QString &aid,
                                       const QString &bvid, const QString &cid,
                                       const QString &epId, int quality,
                                       bool highQualityAttempt, quint64 requestSerial,
                                       const QByteArray &payload, int networkError,
                                       bool fromPrefetch) {
    if (requestSerial != m_requestSerial) return;
    m_loading = false;

    if (networkError != QNetworkReply::NoError) {
        if (highQualityAttempt) {
            qWarning() << "native player: high-quality playurl request failed; retrying 720P progressive";
            resolveInternal(pgc, aid, bvid, cid, epId, kProgressiveFallbackQuality, false);
            return;
        }
        m_errorMessage = tr("播放地址请求失败");
        emit changed();
        return;
    }

    QJsonParseError parseError;
    const QJsonObject root = QJsonDocument::fromJson(payload, &parseError).object();
    if (parseError.error != QJsonParseError::NoError
            || root.value(QStringLiteral("code")).toInt(-1) != 0) {
        if (highQualityAttempt) {
            qWarning() << "native player: high-quality playurl parse/code failed; retrying 720P progressive"
                       << "code" << root.value(QStringLiteral("code")).toInt(-1)
                       << "message" << root.value(QStringLiteral("message")).toString();
            resolveInternal(pgc, aid, bvid, cid, epId, kProgressiveFallbackQuality, false);
            return;
        }
        m_errorMessage = tr("播放地址解析失败");
        emit changed();
        return;
    }

    const QJsonObject data = root.value(pgc ? QStringLiteral("result")
                                            : QStringLiteral("data")).toObject();
    QVariantList discoveredQualities;
    const QHash<int, QString> labelsById = qualityLabelsFromData(
                data, &discoveredQualities);
    m_qualities = mergedQualityCatalog(m_qualities, discoveredQualities);
    qInfo() << "native player: quality catalog updated"
            << "requested" << quality
            << "discovered" << discoveredQualities.size()
            << "retainedChoices" << m_qualities.size();

    const QJsonObject dash = data.value(QStringLiteral("dash")).toObject();
    bool ultraHdGuardApplied = false;
    const QJsonObject dashVideo = chooseDashVideo(
                dash.value(QStringLiteral("video")).toArray(), quality,
                m_directCapabilities,
                m_operationalMaximumQuality,
                &ultraHdGuardApplied);
    if (highQualityAttempt && !dashVideo.isEmpty()) {
        const int dashQuality = dashVideo.value(QStringLiteral("id")).toInt();
        const int dashHeight = dashVideo.value(QStringLiteral("height")).toInt();
        const QJsonObject dashAudio = chooseDashAudio(
                    dash.value(QStringLiteral("audio")).toArray());
        if (!dashAudio.isEmpty()) {
            m_sourceUrl = dashMediaUrl(dashVideo);
            m_audioUrl = dashMediaUrl(dashAudio);
            m_selectedQuality = dashQuality;
            m_selectedQualityLabel = fallbackQualityLabel(labelsById, dashQuality, dashHeight);
            ++m_revision;
            qInfo() << "native player: DASH source resolved, quality" << m_selectedQuality
                    << "label" << m_selectedQualityLabel
                    << "video" << dashVideo.value(QStringLiteral("width")).toInt()
                    << "x" << dashHeight
                    << "codec" << dashVideo.value(QStringLiteral("codecid")).toInt()
                    << "audio" << dashAudio.value(QStringLiteral("id")).toInt()
                    << "choices" << m_qualities.size()
                    << "prefetched" << fromPrefetch;
            if (ultraHdGuardApplied) {
                qWarning() << "native player: unsafe ultra-HD representation avoided"
                           << "requested" << quality
                           << "selected" << dashQuality
                           << "selectedGeometry"
                           << dashVideo.value(QStringLiteral("width")).toInt()
                           << "x" << dashHeight
                           << "maximumGeometry" << kMaximumDirectSourceWidth
                           << "x" << kMaximumDirectSourceHeight
                           << "deviceAvc30Maximum"
                           << m_directCapabilities.avc30MaximumWidth << "x"
                           << m_directCapabilities.avc30MaximumHeight
                           << "deviceAvc60Maximum"
                           << m_directCapabilities.avc60MaximumWidth << "x"
                           << m_directCapabilities.avc60MaximumHeight
                           << "deviceHevc30Maximum"
                           << m_directCapabilities.hevc30MaximumWidth << "x"
                           << m_directCapabilities.hevc30MaximumHeight
                           << "deviceHevc60Maximum"
                           << m_directCapabilities.hevc60MaximumWidth << "x"
                           << m_directCapabilities.hevc60MaximumHeight
                           << "operationalMaximumQuality"
                           << m_operationalMaximumQuality
                           << "softwareFallback" << false;
            }
            emit changed();
            return;
        }

        qInfo() << "native player: DASH response has no audio; retrying 720P progressive"
                << "requested" << quality
                << "bestDashQuality" << dashQuality
                << "bestDashHeight" << dashHeight
                << "choices" << m_qualities.size();
        resolveInternal(pgc, aid, bvid, cid, epId, kProgressiveFallbackQuality, false);
        return;
    }

    const QJsonArray durl = data.value(QStringLiteral("durl")).toArray();
    QStringList urls;
    for (const QJsonValue &value : durl) {
        const QString mediaUrl = value.toObject().value(QStringLiteral("url")).toString();
        if (!mediaUrl.isEmpty()) urls.append(mediaUrl);
    }
    if (urls.isEmpty()) {
        if (highQualityAttempt) {
            qInfo() << "native player: high-quality response had no playable DASH/progressive media;"
                    << "retrying 720P progressive";
            resolveInternal(pgc, aid, bvid, cid, epId, kProgressiveFallbackQuality, false);
            return;
        }
        m_errorMessage = tr("没有可播放的媒体地址");
        emit changed();
        return;
    }

    if (urls.size() == 1) {
        m_sourceUrl = urls.first();
    } else {
        QStringList escaped;
        for (const QString &mediaUrl : urls)
            escaped.append(QStringLiteral("%%%1%%%2").arg(mediaUrl.toUtf8().size()).arg(mediaUrl));
        m_sourceUrl = QStringLiteral("edl://") + escaped.join(QStringLiteral(";"));
    }

    m_selectedQuality = data.value(QStringLiteral("quality")).toInt();
    m_selectedQualityLabel = fallbackQualityLabel(labelsById, m_selectedQuality, 0);
    ++m_revision;
    qInfo() << "native player: source resolved, quality" << m_selectedQuality
            << "choices" << m_qualities.size() << "segments" << urls.size()
            << "prefetched" << fromPrefetch;
    emit changed();
}
