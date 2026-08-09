#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QTimer>

class PlaybackSession;

// Counts completed QQuickWindow swaps while foreground playback is active.
// This measures the Qt Quick presentation path, not decoder probe delivery.
class DisplayFrameMonitor : public QObject {
    Q_OBJECT

public:
    explicit DisplayFrameMonitor(PlaybackSession *session, QObject *parent = 0);

public slots:
    void frameSwapped();

private slots:
    void sampleWindow();

private:
    bool qualifies() const;
    void resetQualification();

    QPointer<PlaybackSession> m_session;
    QTimer m_sampleTimer;
    QElapsedTimer m_windowTimer;
    QElapsedTimer m_qualificationTimer;
    int m_windowFrames;
    int m_windowCount;
    int m_belowFloorCount;
    double m_minimumFps;
};
