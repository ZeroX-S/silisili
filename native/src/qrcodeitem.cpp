#include "qrcodeitem.h"

#include <qrcodegen.hpp>

#include <QByteArray>
#include <QDebug>
#include <QPainter>
#include <QtMath>

#include <exception>

namespace {
const int kQuietZoneModules = 4;
}

QrCodeItem::QrCodeItem(QQuickItem *parent)
    : QQuickPaintedItem(parent), m_moduleCount(0) {
    setAntialiasing(false);
    setOpaquePainting(true);
}

void QrCodeItem::setSourceText(const QString &sourceText) {
    if (m_sourceText == sourceText) return;
    m_sourceText = sourceText;
    emit sourceTextChanged();
    rebuild();
}

bool QrCodeItem::encode(const QString &sourceText, QVector<quint8> *modules,
                        int *moduleCount, QString *error) {
    modules->clear();
    *moduleCount = 0;
    error->clear();
    if (sourceText.isEmpty()) {
        *error = QStringLiteral("No data");
        return false;
    }

    try {
        const QByteArray payload = sourceText.toUtf8();
        const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(
                    payload.constData(), qrcodegen::QrCode::Ecc::MEDIUM);
        const int size = qr.getSize();
        if (size <= 0) {
            *error = QStringLiteral("QR encoder returned an empty symbol");
            return false;
        }
        modules->resize(size * size);
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x)
                (*modules)[y * size + x] = qr.getModule(x, y) ? 1 : 0;
        }
        *moduleCount = size;
        return true;
    } catch (const std::exception &exception) {
        *error = QString::fromLocal8Bit(exception.what());
    } catch (...) {
        *error = QStringLiteral("Unknown QR encoding error");
    }
    return false;
}

void QrCodeItem::rebuild() {
    const bool ready = encode(m_sourceText, &m_modules, &m_moduleCount, &m_error);
    int darkModules = 0;
    for (quint8 module : m_modules)
        darkModules += module ? 1 : 0;
    if (ready) {
        qInfo() << "native account: built-in QR payload encoded"
                << "sourceLength" << m_sourceText.size()
                << "modules" << m_moduleCount
                << "darkModules" << darkModules;
    } else if (!m_sourceText.isEmpty()) {
        qWarning() << "native account: built-in QR payload rejected"
                   << "sourceLength" << m_sourceText.size()
                   << "error" << m_error;
    }
    emit renderStateChanged();
    update();
}

void QrCodeItem::paint(QPainter *painter) {
    painter->setRenderHint(QPainter::Antialiasing, false);
    painter->fillRect(boundingRect(), Qt::white);
    if (!valid()) return;

    const int symbolModules = m_moduleCount + 2 * kQuietZoneModules;
    const int cellPixels = qFloor(qMin(width(), height()) / symbolModules);
    if (cellPixels < 1) return;
    const int symbolPixels = symbolModules * cellPixels;
    const int originX = qFloor((width() - symbolPixels) / 2.0)
            + kQuietZoneModules * cellPixels;
    const int originY = qFloor((height() - symbolPixels) / 2.0)
            + kQuietZoneModules * cellPixels;

    painter->setPen(Qt::NoPen);
    painter->setBrush(Qt::black);
    for (int y = 0; y < m_moduleCount; ++y) {
        for (int x = 0; x < m_moduleCount; ++x) {
            if (!m_modules.at(y * m_moduleCount + x)) continue;
            painter->drawRect(originX + x * cellPixels,
                              originY + y * cellPixels,
                              cellPixels, cellPixels);
        }
    }
}

bool QrCodeItem::selfTest(int *moduleCount) {
    QVector<quint8> modules;
    int size = 0;
    QString error;
    const bool ready = encode(
                QStringLiteral("https://passport.bilibili.com/silisili-qr-self-test"),
                &modules, &size, &error);
    if (moduleCount) *moduleCount = size;
    return ready && size >= 21 && modules.size() == size * size
            && modules.at(0) && modules.at(6) && modules.at(6 * size)
            && modules.at(6 * size + 6);
}
