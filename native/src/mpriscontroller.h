#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <QtDBus/QDBusAbstractAdaptor>
#include <QtDBus/QDBusObjectPath>

class PlaybackSession;

class MprisController : public QObject {
    Q_OBJECT
public:
    explicit MprisController(PlaybackSession *session, QObject *parent = 0);
    ~MprisController();
    PlaybackSession *session() const { return m_session; }
    QVariantMap metadata() const;
    QDBusObjectPath trackId() const;
    QString playbackStatus() const;
    qlonglong position() const;
    bool canSeek() const;
    void seekTo(qlonglong microseconds);
signals:
    void raiseRequested();
    void seekCompleted(qlonglong position);
private slots:
    void publish();
    void positionChanged();
private:
    PlaybackSession *m_session;
    bool m_registered;
    QVariantMap m_lastProperties;
    qlonglong m_pendingSeek;
};

class MprisRootAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ canQuit CONSTANT)
    Q_PROPERTY(bool CanRaise READ canRaise CONSTANT)
    Q_PROPERTY(bool HasTrackList READ hasTrackList CONSTANT)
    Q_PROPERTY(QString Identity READ identity CONSTANT)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry CONSTANT)
    Q_PROPERTY(QStringList SupportedUriSchemes READ supportedUriSchemes CONSTANT)
    Q_PROPERTY(QStringList SupportedMimeTypes READ supportedMimeTypes CONSTANT)
public:
    explicit MprisRootAdaptor(MprisController *controller);
    bool canQuit() const { return true; }
    bool canRaise() const { return true; }
    bool hasTrackList() const { return false; }
    QString identity() const { return QStringLiteral("SiliSili"); }
    QString desktopEntry() const { return QStringLiteral("cn.silisili.native"); }
    QStringList supportedUriSchemes() const { return QStringList(); }
    QStringList supportedMimeTypes() const { return QStringList(); }
public slots:
    void Raise();
    void Quit();
private:
    MprisController *m_controller;
};

class MprisPlayerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus WRITE setLoopStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ minimumRate)
    Q_PROPERTY(double MaximumRate READ maximumRate)
    Q_PROPERTY(bool CanGoNext READ canGoNext CONSTANT)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious CONSTANT)
    Q_PROPERTY(bool CanPlay READ canPlay)
    Q_PROPERTY(bool CanPause READ canPause)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ canPlay)
public:
    explicit MprisPlayerAdaptor(MprisController *controller);
    QString playbackStatus() const;
    QString loopStatus() const { return QStringLiteral("None"); }
    void setLoopStatus(const QString &) {}
    double rate() const;
    void setRate(double value);
    bool shuffle() const { return false; }
    void setShuffle(bool) {}
    QVariantMap metadata() const;
    double volume() const;
    void setVolume(double value);
    qlonglong position() const;
    double minimumRate() const;
    double maximumRate() const;
    bool canGoNext() const { return false; }
    bool canGoPrevious() const { return false; }
    bool canPlay() const;
    bool canPause() const;
    bool canSeek() const;
public slots:
    void Play();
    void Pause();
    void PlayPause();
    void Stop();
    void Seek(qlonglong offset);
    void SetPosition(const QDBusObjectPath &track, qlonglong position);
    void Next() {}
    void Previous() {}
    void OpenUri(const QString &) {}
signals:
    void Seeked(qlonglong position);
private:
    MprisController *m_controller;
};
