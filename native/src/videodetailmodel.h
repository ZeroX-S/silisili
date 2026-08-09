#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QVariantList>

class VideoDetailModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString bvid READ bvid NOTIFY changed)
    Q_PROPERTY(QString aid READ aid NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString owner READ owner NOTIFY changed)
    Q_PROPERTY(QString ownerMid READ ownerMid NOTIFY changed)
    Q_PROPERTY(QString cover READ cover NOTIFY changed)
    Q_PROPERTY(QString description READ description NOTIFY changed)
    Q_PROPERTY(QString stats READ stats NOTIFY changed)
    Q_PROPERTY(QVariantList pages READ pages NOTIFY changed)
    Q_PROPERTY(QString firstCid READ firstCid NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)
public:
    explicit VideoDetailModel(QObject *parent = 0);
    bool loading() const { return m_loading; } QString bvid() const { return m_bvid; }
    QString aid() const { return m_aid; }
    QString title() const { return m_title; } QString owner() const { return m_owner; }
    QString ownerMid() const { return m_ownerMid; }
    QString cover() const { return m_cover; } QString description() const { return m_description; }
    QString stats() const { return m_stats; } QVariantList pages() const { return m_pages; }
    QString firstCid() const { return m_firstCid; }
    QString errorMessage() const { return m_errorMessage; }
public slots:
    void load(const QString &bvid);
signals:
    void changed();
private:
    QNetworkAccessManager m_network; bool m_loading;
    QString m_bvid, m_aid, m_title, m_owner, m_ownerMid, m_cover, m_description, m_stats, m_errorMessage, m_firstCid;
    QVariantList m_pages;
};
