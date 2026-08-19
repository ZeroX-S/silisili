#include "appsettings.h"

#include <QDebug>
#include <QSettings>

namespace {
const char kContentColumnsKey[] = "ui/contentColumns";
const char kContinueMiniPlayerKey[] = "playback/continueInAppMiniPlayer";

int normalizedColumns(int columns) {
    return columns == 2 ? 2 : 1;
}
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      m_contentColumns(normalizedColumns(
          QSettings().value(QString::fromLatin1(kContentColumnsKey), 1).toInt())),
      m_continueInAppMiniPlayer(
          QSettings().value(QString::fromLatin1(kContinueMiniPlayerKey), true).toBool()) {
    qInfo() << "native settings: presentation loaded"
            << "contentColumns" << m_contentColumns
            << "continueInAppMiniPlayer" << m_continueInAppMiniPlayer;
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
