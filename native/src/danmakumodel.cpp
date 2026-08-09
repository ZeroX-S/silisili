#include "danmakumodel.h"

#include <QDebug>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QVariantMap>
#include <QXmlStreamReader>
#include <algorithm>

namespace {

bool readVarint(const QByteArray &data, int *offset, quint64 *value) {
    quint64 result = 0;
    int shift = 0;
    while (*offset < data.size() && shift <= 63) {
        const quint8 byte = static_cast<quint8>(data.at((*offset)++));
        result |= static_cast<quint64>(byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) {
            *value = result;
            return true;
        }
        shift += 7;
    }
    return false;
}

bool skipField(const QByteArray &data, int *offset, int wireType) {
    quint64 length = 0;
    switch (wireType) {
    case 0:
        return readVarint(data, offset, &length);
    case 1:
        *offset += 8;
        break;
    case 2:
        if (!readVarint(data, offset, &length) || length > static_cast<quint64>(data.size() - *offset))
            return false;
        *offset += static_cast<int>(length);
        break;
    case 5:
        *offset += 4;
        break;
    default:
        return false;
    }
    return *offset <= data.size();
}

} // namespace

DanmakuModel::DanmakuModel(QObject *parent)
    : QObject(parent), m_loading(false), m_enabled(true), m_cursor(0),
      m_opacity(0.9), m_fontScale(1.0), m_speed(1.0), m_revision(0),
      m_highestSegment(0) {}

void DanmakuModel::load(const QString &cid) {
    if (cid.isEmpty() || (m_cid == cid && (m_loading || !m_items.isEmpty()))) return;
    m_cid = cid;
    ++m_revision;
    m_loading = false;
    m_cursor = 0;
    m_highestSegment = 0;
    m_items.clear();
    m_requestedSegments.clear();
    m_errorMessage.clear();
    emit changed();
    requestSegment(1);
}

void DanmakuModel::requestSegment(int segmentIndex) {
    if (m_cid.isEmpty() || m_loading || segmentIndex < 1 || m_requestedSegments.contains(segmentIndex))
        return;

    const int revision = m_revision;
    m_requestedSegments.insert(segmentIndex);
    m_loading = true;
    emit changed();

    QUrl url(QStringLiteral("https://api.bilibili.com/x/v2/dm/web/seg.so"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("type"), QStringLiteral("1"));
    query.addQueryItem(QStringLiteral("oid"), m_cid);
    query.addQueryItem(QStringLiteral("segment_index"), QString::number(segmentIndex));
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept", "application/octet-stream");
    request.setRawHeader("Accept-Encoding", "identity");

    qInfo() << "native danmaku: requesting cid" << m_cid << "segment" << segmentIndex;
    QNetworkReply *reply = m_network.get(request);
    QTimer::singleShot(12000, reply, [reply]() {
        if (reply->isRunning()) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, revision, segmentIndex]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const QString networkMessage = reply->errorString();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();
        if (revision != m_revision) return;
        m_loading = false;

        QVector<Item> parsed;
        if (networkError != QNetworkReply::NoError || !parseSegment(payload, &parsed)) {
            m_requestedSegments.remove(segmentIndex);
            qWarning() << "native danmaku: segment failed" << segmentIndex << "HTTP" << httpStatus
                       << networkError << networkMessage << "bytes" << payload.size();
            if (segmentIndex == 1) {
                loadLegacyXml();
                return;
            }
            m_errorMessage = tr("弹幕分段请求失败");
            emit changed();
            return;
        }

        m_highestSegment = qMax(m_highestSegment, segmentIndex);
        mergeItems(parsed);
        m_errorMessage.clear();
        qInfo() << "native danmaku: loaded segment" << segmentIndex << "items" << parsed.size()
                << "total" << m_items.size() << "for cid" << m_cid;
        emit changed();
    });
}

void DanmakuModel::loadLegacyXml() {
    const int revision = m_revision;
    m_loading = true;
    emit changed();

    QNetworkRequest request(QUrl(QStringLiteral("https://comment.bilibili.com/%1.xml").arg(m_cid)));
    request.setRawHeader("User-Agent", "Mozilla/5.0 silisili-native/1.1 SailfishOS");
    request.setRawHeader("Referer", "https://www.bilibili.com/");
    request.setRawHeader("Accept-Encoding", "identity");
    QNetworkReply *reply = m_network.get(request);
    QTimer::singleShot(12000, reply, [reply]() {
        if (reply->isRunning()) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, revision]() {
        const QByteArray payload = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const QString networkMessage = reply->errorString();
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();
        if (revision != m_revision) return;
        m_loading = false;
        if (networkError != QNetworkReply::NoError) {
            m_errorMessage = tr("弹幕请求失败");
            qWarning() << "native danmaku: XML fallback failed HTTP" << httpStatus
                       << networkError << networkMessage;
            emit changed();
            return;
        }

        QVector<Item> parsed;
        QXmlStreamReader xml(payload);
        while (!xml.atEnd()) {
            xml.readNext();
            if (!xml.isStartElement() || xml.name() != QStringLiteral("d")) continue;
            const QStringList fields = xml.attributes().value(QStringLiteral("p")).toString().split(',');
            if (fields.size() < 4) {
                xml.skipCurrentElement();
                continue;
            }
            Item item;
            item.time = fields.at(0).toDouble();
            item.mode = fields.at(1).toInt();
            item.size = fields.at(2).toInt();
            const int color = fields.at(3).toInt();
            item.color = QStringLiteral("#%1").arg(color, 6, 16, QLatin1Char('0'));
            item.text = xml.readElementText(QXmlStreamReader::SkipChildElements).trimmed();
            if (!item.text.isEmpty() && item.mode >= 1 && item.mode <= 5)
                parsed.append(item);
        }
        if (xml.hasError()) {
            m_errorMessage = tr("弹幕解析失败");
            emit changed();
            return;
        }
        std::sort(parsed.begin(), parsed.end(), [](const Item &left, const Item &right) {
            return left.time < right.time;
        });
        mergeItems(parsed);
        m_cursor = 0;
        qInfo() << "native danmaku: XML fallback loaded" << m_items.size()
                << "items for cid" << m_cid;
        emit changed();
    });
}

bool DanmakuModel::parseSegment(const QByteArray &payload, QVector<Item> *items) const {
    int offset = 0;
    while (offset < payload.size()) {
        quint64 key = 0;
        if (!readVarint(payload, &offset, &key)) return false;
        const int field = static_cast<int>(key >> 3);
        const int wireType = static_cast<int>(key & 7);
        if (field != 1 || wireType != 2) {
            if (!skipField(payload, &offset, wireType)) return false;
            continue;
        }

        quint64 length = 0;
        if (!readVarint(payload, &offset, &length)
                || length > static_cast<quint64>(payload.size() - offset))
            return false;
        const QByteArray message = payload.mid(offset, static_cast<int>(length));
        offset += static_cast<int>(length);

        Item item = { 0.0, 1, 25, QStringLiteral("#ffffff"), QString() };
        int messageOffset = 0;
        while (messageOffset < message.size()) {
            quint64 itemKey = 0;
            if (!readVarint(message, &messageOffset, &itemKey)) return false;
            const int itemField = static_cast<int>(itemKey >> 3);
            const int itemWireType = static_cast<int>(itemKey & 7);
            if ((itemField >= 2 && itemField <= 5) && itemWireType == 0) {
                quint64 value = 0;
                if (!readVarint(message, &messageOffset, &value)) return false;
                if (itemField == 2) item.time = static_cast<double>(value) / 1000.0;
                else if (itemField == 3) item.mode = static_cast<int>(value);
                else if (itemField == 4) item.size = static_cast<int>(value);
                else item.color = QStringLiteral("#%1").arg(static_cast<qulonglong>(value), 6, 16,
                                                            QLatin1Char('0'));
            } else if (itemField == 7 && itemWireType == 2) {
                quint64 textLength = 0;
                if (!readVarint(message, &messageOffset, &textLength)
                        || textLength > static_cast<quint64>(message.size() - messageOffset))
                    return false;
                item.text = QString::fromUtf8(message.constData() + messageOffset,
                                              static_cast<int>(textLength)).trimmed();
                messageOffset += static_cast<int>(textLength);
            } else if (!skipField(message, &messageOffset, itemWireType)) {
                return false;
            }
        }
        if (!item.text.isEmpty() && item.mode >= 1 && item.mode <= 5)
            items->append(item);
    }
    return true;
}

void DanmakuModel::mergeItems(const QVector<Item> &items) {
    m_items += items;
    std::sort(m_items.begin(), m_items.end(), [](const Item &left, const Item &right) {
        return left.time < right.time;
    });
}

void DanmakuModel::seek(double position) {
    int low = 0;
    int high = m_items.size();
    while (low < high) {
        const int middle = low + (high - low) / 2;
        if (m_items.at(middle).time < position) low = middle + 1;
        else high = middle;
    }
    m_cursor = low;
}

QVariantList DanmakuModel::takeUntil(double position, int maximum) {
    QVariantList result;
    if (!m_enabled || maximum <= 0) return result;
    if (!m_loading && m_highestSegment > 0
            && position + 45.0 >= static_cast<double>(m_highestSegment * 360))
        requestSegment(m_highestSegment + 1);
    while (m_cursor < m_items.size() && m_items.at(m_cursor).time <= position) {
        const Item &item = m_items.at(m_cursor++);
        if (result.size() >= maximum) continue;
        QVariantMap value;
        value.insert(QStringLiteral("text"), item.text);
        value.insert(QStringLiteral("mode"), item.mode);
        value.insert(QStringLiteral("size"), item.size);
        value.insert(QStringLiteral("color"), item.color);
        result.append(value);
    }
    return result;
}

void DanmakuModel::setEnabled(bool enabledValue) {
    if (m_enabled == enabledValue) return;
    m_enabled = enabledValue;
    emit changed();
}
void DanmakuModel::setOpacity(qreal opacityValue) {
    opacityValue = qBound<qreal>(0.2, opacityValue, 1.0);
    if (qAbs(m_opacity - opacityValue) < 0.01) return;
    m_opacity = opacityValue;
    emit changed();
}
void DanmakuModel::setFontScale(qreal scale) {
    scale = qBound<qreal>(0.6, scale, 1.8);
    if (qAbs(m_fontScale - scale) < 0.01) return;
    m_fontScale = scale;
    emit changed();
}
void DanmakuModel::setSpeed(qreal speedValue) {
    speedValue = qBound<qreal>(0.5, speedValue, 2.0);
    if (qAbs(m_speed - speedValue) < 0.01) return;
    m_speed = speedValue;
    emit changed();
}
