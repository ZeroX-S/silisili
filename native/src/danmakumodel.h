#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVector>

class DanmakuModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(qreal opacity READ opacity WRITE setOpacity NOTIFY changed)
    Q_PROPERTY(qreal fontScale READ fontScale WRITE setFontScale NOTIFY changed)
    Q_PROPERTY(qreal speed READ speed WRITE setSpeed NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)

public:
    explicit DanmakuModel(QObject *parent = 0);
    bool loading() const { return m_loading; }
    bool enabled() const { return m_enabled; }
    int count() const { return m_items.size(); }
    qreal opacity() const { return m_opacity; }
    qreal fontScale() const { return m_fontScale; }
    qreal speed() const { return m_speed; }
    QString errorMessage() const { return m_errorMessage; }

public slots:
    void load(const QString &cid);
    void seek(double position);
    QVariantList takeUntil(double position, int maximum = 24);
    void setEnabled(bool enabled);
    void setOpacity(qreal opacity);
    void setFontScale(qreal scale);
    void setSpeed(qreal speed);

signals:
    void changed();

private:
    struct Item {
        double time;
        int mode;
        int size;
        QString color;
        QString text;
    };

    void requestSegment(int segmentIndex);
    void loadLegacyXml();
    bool parseSegment(const QByteArray &payload, QVector<Item> *items) const;
    void mergeItems(const QVector<Item> &items);

    QNetworkAccessManager m_network;
    QVector<Item> m_items;
    bool m_loading;
    bool m_enabled;
    int m_cursor;
    qreal m_opacity;
    qreal m_fontScale;
    qreal m_speed;
    int m_revision;
    int m_highestSegment;
    QSet<int> m_requestedSegments;
    QString m_cid;
    QString m_errorMessage;
};
