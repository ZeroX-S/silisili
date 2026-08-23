#pragma once

#include <QObject>
#include <QString>

class SystemControls : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY changed)
    Q_PROPERTY(bool volumeAvailable READ volumeAvailable NOTIFY changed)
    Q_PROPERTY(double brightnessPercent READ brightnessPercent NOTIFY changed)
    Q_PROPERTY(double volumePercent READ volumePercent NOTIFY changed)

public:
    explicit SystemControls(QObject *parent = 0);
    ~SystemControls();

    bool brightnessAvailable() const {
        return m_brightnessUsesMce
                || (!m_brightnessPath.isEmpty() && m_brightnessMaximum > 0);
    }
    bool volumeAvailable() const { return m_volumeAvailable; }
    double brightnessPercent();
    double volumePercent();

public slots:
    void beginPlaybackSession();
    void restorePlaybackSession(const QString &reason = QStringLiteral("playback-exit"));
    bool setBrightnessPercent(double percent);
    bool setVolumePercent(double percent);
    void refresh();

signals:
    void changed();

private:
    void discoverBrightnessPath();
    void discoverVolume();
    int readBrightnessValue() const;
    bool writeBrightnessValue(int value);
    double queryMceBrightnessPercent(bool *ok = 0) const;
    bool writeMceBrightnessPercent(double percent);
    QStringList activeSinkInputIndexes() const;
    double queryActiveSinkInputVolumePercent(bool *ok = 0) const;
    bool ensurePulseStreamRestore();
    bool readPulseStreamRestoreVolume(double *percent);
    bool writePulseStreamRestoreVolume(double percent);
    double queryVolumePercent(bool *ok = 0) const;
    bool writeVolumePercent(double percent);
    QString runMceTool(const QStringList &arguments, bool *ok = 0) const;
    QString runPactl(const QStringList &arguments, bool *ok = 0) const;

    QString m_brightnessPath;
    int m_brightnessMaximum;
    bool m_brightnessUsesMce;
    bool m_volumeAvailable;
    QString m_pulsePeerConnectionName;
    QString m_streamRestoreEntryPath;
    bool m_sessionActive;
    bool m_savedBrightnessValid;
    bool m_savedVolumeValid;
    int m_savedBrightnessValue;
    double m_savedVolumePercent;
    double m_cachedBrightnessPercent;
    double m_cachedVolumePercent;
};
