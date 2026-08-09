#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QRegion>
#include <QString>
#include <QTimer>

class PlaybackSession;
class MpvVideoItem;
class QQuickView;

class SystemPipController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString backgroundPlaybackMode READ backgroundPlaybackMode
               WRITE setBackgroundPlaybackMode NOTIFY backgroundPlaybackModeChanged)
    Q_PROPERTY(bool available READ available NOTIFY availabilityChanged)
    Q_PROPERTY(bool visible READ visible NOTIFY visibilityChanged)
    Q_PROPERTY(int overlayX READ overlayX NOTIFY overlayGeometryChanged)
    Q_PROPERTY(int overlayY READ overlayY NOTIFY overlayGeometryChanged)
    Q_PROPERTY(int overlayWidth READ overlayWidth NOTIFY overlayGeometryChanged)
    Q_PROPERTY(int overlayHeight READ overlayHeight NOTIFY overlayGeometryChanged)
    Q_PROPERTY(int orientationAngle READ orientationAngle NOTIFY orientationAngleChanged)

public:
    SystemPipController(QQuickView *mainView, PlaybackSession *session,
                        MpvVideoItem *videoItem,
                        QObject *parent = 0);
    ~SystemPipController() override;

    QString backgroundPlaybackMode() const { return m_backgroundPlaybackMode; }
    bool available() const { return m_available; }
    bool visible() const;
    int overlayX() const { return m_overlayRect.x(); }
    int overlayY() const { return m_overlayRect.y(); }
    int overlayWidth() const { return m_contentSize.width(); }
    int overlayHeight() const { return m_contentSize.height(); }
    int orientationAngle() const { return m_orientationAngle; }

    Q_INVOKABLE void setInputRect(qreal x, qreal y, qreal width, qreal height);
    Q_INVOKABLE void commitOverlayPosition(qreal x, qreal y,
                                            qreal width, qreal height);
    Q_INVOKABLE void setSensorOrientation(int angle);
    Q_INVOKABLE void setBackgroundPlaybackMode(const QString &mode);
    Q_INVOKABLE void restoreApplication();

signals:
    void backgroundPlaybackModeChanged();
    void availabilityChanged();
    void visibilityChanged();
    void overlayGeometryChanged();
    void orientationAngleChanged();

private slots:
    void applicationStateChanged(Qt::ApplicationState state);
    void tklockModeChanged(const QString &mode);
    void displayStatusChanged(const QString &status);
    void probeForegroundState();
    void updateVisibility();
    void sampleFrameSwaps();
    void requestPresentationFrame();
    void overlayFrameSwapped();

private:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void refreshDeviceState();
    void updateOverlayGeometry();
    void configureLipstickSurface();
    void applyInputRegion();
    void saveWindowPosition();
    QSize orientedBoundsSize() const;

    QPointer<QQuickView> m_mainView;
    QQuickView *m_view;
    PlaybackSession *m_session;
    MpvVideoItem *m_videoItem;
    QRegion m_inputRegion;
    QRect m_overlayRect;
    QSize m_contentSize;
    QTimer m_swapSampleTimer;
    QTimer m_presentationTimer;
    QTimer m_visibilityDelayTimer;
    QTimer m_foregroundProbeTimer;
    QTimer m_restoreGuardTimer;
    QElapsedTimer m_swapWindow;
    QElapsedTimer m_backgroundTransitionElapsed;
    int m_swapFrames;
    int m_remapAttempts;
    int m_orientationAngle;
    int m_forcedTestOrientation;
    bool m_available;
    bool m_deviceUnlocked;
    bool m_displayOn;
    bool m_applicationForeground;
    bool m_foregroundProbePending;
    bool m_restoreInProgress;
    QString m_backgroundPlaybackMode;
};
