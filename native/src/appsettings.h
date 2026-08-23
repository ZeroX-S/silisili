#pragma once

#include <QObject>

class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int contentColumns READ contentColumns WRITE setContentColumns
               NOTIFY contentColumnsChanged)
    Q_PROPERTY(bool continueInAppMiniPlayer READ continueInAppMiniPlayer
               WRITE setContinueInAppMiniPlayer
               NOTIFY continueInAppMiniPlayerChanged)
    Q_PROPERTY(int fontSizeMode READ fontSizeMode WRITE setFontSizeMode
               NOTIFY fontSizeModeChanged)

public:
    explicit AppSettings(QObject *parent = 0);

    int contentColumns() const { return m_contentColumns; }
    bool continueInAppMiniPlayer() const { return m_continueInAppMiniPlayer; }
    int fontSizeMode() const { return m_fontSizeMode; }
    Q_INVOKABLE int scaledFontSize(int basePixelSize, int mode) const;

public slots:
    void setContentColumns(int columns);
    void setContinueInAppMiniPlayer(bool enabled);
    void setFontSizeMode(int mode);

signals:
    void contentColumnsChanged();
    void continueInAppMiniPlayerChanged();
    void fontSizeModeChanged();

private:
    int m_contentColumns;
    bool m_continueInAppMiniPlayer;
    int m_fontSizeMode;
};
