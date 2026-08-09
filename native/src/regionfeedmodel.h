#pragma once
#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QVector>

class QNetworkReply;

class RegionFeedModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)
public:
    enum Role {
        TitleRole = Qt::UserRole + 1,
        OwnerRole,
        CoverRole,
        BvidRole,
        PlayRole,
        DanmakuRole
    };
    explicit RegionFeedModel(QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int,QByteArray> roleNames() const override;
    bool loading() const { return m_loading; }
    QString title() const { return m_title; }
    QString errorMessage() const { return m_errorMessage; }

public slots:
    void load(int regionId, const QString &title);

signals:
    void stateChanged();

private:
    struct Item { QString title, owner, cover, bvid, play, danmaku; };
    QNetworkAccessManager m_network;
    QVector<Item> m_items;
    QPointer<QNetworkReply> m_reply;
    bool m_loading;
    int m_generation;
    QString m_title;
    QString m_errorMessage;
};
