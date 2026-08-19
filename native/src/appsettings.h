#pragma once

#include <QObject>

class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int contentColumns READ contentColumns WRITE setContentColumns
               NOTIFY contentColumnsChanged)
    Q_PROPERTY(bool continueInAppMiniPlayer READ continueInAppMiniPlayer
               WRITE setContinueInAppMiniPlayer
               NOTIFY continueInAppMiniPlayerChanged)

public:
    explicit AppSettings(QObject *parent = 0);

    int contentColumns() const { return m_contentColumns; }
    bool continueInAppMiniPlayer() const { return m_continueInAppMiniPlayer; }

public slots:
    void setContentColumns(int columns);
    void setContinueInAppMiniPlayer(bool enabled);

signals:
    void contentColumnsChanged();
    void continueInAppMiniPlayerChanged();

private:
    int m_contentColumns;
    bool m_continueInAppMiniPlayer;
};
