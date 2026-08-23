#include "appsettings.h"

#include <QDebug>
#include <QSettings>
#include <QtGlobal>

namespace {
const char kContentColumnsKey[] = "ui/contentColumns";
const char kContinueMiniPlayerKey[] = "playback/continueInAppMiniPlayer";
const char kFontSizeModeKey[] = "ui/fontSizeMode";

int normalizedColumns(int columns) {
    return columns == 2 ? 2 : 1;
}

int normalizedFontSizeMode(int mode) {
    return qBound(0, mode, 2);
}

double fontScaleForMode(int mode) {
    if (mode <= 0) return 0.92;
    if (mode >= 2) return 1.14;
    return 1.0;
}
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      m_contentColumns(normalizedColumns(
          QSettings().value(QString::fromLatin1(kContentColumnsKey), 2).toInt())),
      m_continueInAppMiniPlayer(
          QSettings().value(QString::fromLatin1(kContinueMiniPlayerKey), true).toBool()),
      m_fontSizeMode(normalizedFontSizeMode(
          QSettings().value(QString::fromLatin1(kFontSizeModeKey), 1).toInt())) {
    qInfo() << "native settings: presentation loaded"
            << "contentColumns" << m_contentColumns
            << "continueInAppMiniPlayer" << m_continueInAppMiniPlayer
            << "fontSizeMode" << m_fontSizeMode
            << "fontScale" << fontScaleForMode(m_fontSizeMode);
}

void AppSettings::setContentColumns(int columns) {
    const int normalized = normalizedColumns(columns);
    if (m_contentColumns == normalized) return;
    m_contentColumns = normalized;
    QSettings().setValue(QString::fromLatin1(kContentColumnsKey), normalized);
    qInfo() << "native settings: content columns changed" << normalized;
    emit contentColumnsChanged();
}

void AppSettings::setContinueInAppMiniPlayer(bool enabled) {
    if (m_continueInAppMiniPlayer == enabled) return;
    m_continueInAppMiniPlayer = enabled;
    QSettings().setValue(QString::fromLatin1(kContinueMiniPlayerKey), enabled);
    qInfo() << "native settings: in-app mini player changed" << enabled;
    emit continueInAppMiniPlayerChanged();
}

int AppSettings::scaledFontSize(int basePixelSize, int mode) const {
    return qMax(1, qRound(basePixelSize
                          * fontScaleForMode(normalizedFontSizeMode(mode))));
}

void AppSettings::setFontSizeMode(int mode) {
    const int normalized = normalizedFontSizeMode(mode);
    if (m_fontSizeMode == normalized) return;
    m_fontSizeMode = normalized;
    QSettings().setValue(QString::fromLatin1(kFontSizeModeKey), normalized);
    qInfo() << "native settings: font size mode changed"
            << normalized << "scale" << fontScaleForMode(normalized);
    emit fontSizeModeChanged();
}
