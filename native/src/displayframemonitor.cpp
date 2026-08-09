#include "displayframemonitor.h"

#include "playbacksession.h"

#include <QDebug>
#include <QGuiApplication>

DisplayFrameMonitor::DisplayFrameMonitor(PlaybackSession *session, QObject *parent)
    : QObject(parent), m_session(session), m_windowFrames(0), m_windowCount(0),
      m_belowFloorCount(0), m_minimumFps(0.0) {
    m_sampleTimer.setInterval(100);
    connect(&m_sampleTimer, &QTimer::timeout,
            this, &DisplayFrameMonitor::sampleWindow);
    m_sampleTimer.start();
}

bool DisplayFrameMonitor::qualifies() const {
    return m_session && m_session->playing() && qApp
            && qApp->applicationState() == Qt::ApplicationActive;
}

void DisplayFrameMonitor::resetQualification() {
    m_windowTimer.invalidate();
    m_qualificationTimer.invalidate();
    m_windowFrames = 0;
    m_windowCount = 0;
    m_belowFloorCount = 0;
    m_minimumFps = 0.0;
}

void DisplayFrameMonitor::frameSwapped() {
    if (!qualifies()) return;
    if (!m_windowTimer.isValid()) {
        m_windowTimer.start();
        m_qualificationTimer.start();
    }
    ++m_windowFrames;
}

void DisplayFrameMonitor::sampleWindow() {
    if (!qualifies()) {
        if (m_windowTimer.isValid()) resetQualification();
        return;
    }
    if (!m_windowTimer.isValid()) {
        // A frozen output must produce a 0 fps failed window instead of
        // silently avoiding qualification because no frameSwapped arrived.
        m_windowTimer.start();
        m_qualificationTimer.start();
        return;
    }

    const qint64 elapsed = m_windowTimer.elapsed();
    if (elapsed < 1000) return;
    const double fps = elapsed > 0
            ? (1000.0 * static_cast<double>(m_windowFrames) / elapsed) : 0.0;
    ++m_windowCount;
    if (m_minimumFps <= 0.0 || fps < m_minimumFps) m_minimumFps = fps;
    if (fps < 45.0) ++m_belowFloorCount;
    qInfo() << "native display: frame swap window"
            << "window" << m_windowCount
            << "fps" << fps
            << "minimum" << m_minimumFps
            << "below45" << m_belowFloorCount;
    m_windowFrames = 0;
    m_windowTimer.restart();

    if (m_qualificationTimer.elapsed() < 60000) return;
    const bool pass = m_belowFloorCount == 0 && m_windowCount >= 50;
    qInfo() << "native display: 60 second frame swap floor"
            << "result" << (pass ? "pass" : "fail")
            << "windows" << m_windowCount
            << "minimumFps" << m_minimumFps
            << "below45" << m_belowFloorCount;
    m_qualificationTimer.restart();
    m_windowCount = 0;
    m_belowFloorCount = 0;
    m_minimumFps = 0.0;
}
