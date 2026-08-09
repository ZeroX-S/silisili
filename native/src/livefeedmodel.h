#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QVector>

class QNetworkReply;

class LiveFeedModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY hasMoreChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    enum Role { RoomIdRole = Qt::UserRole + 1, TitleRole, OwnerRole, CoverRole, AreaRole, WatchedRole };

    explicit LiveFeedModel(QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString errorMessage() const { return m_errorMessage; }

public slots:
    void refresh();
    void loadMore();

signals:
    void loadingChanged();
    void hasMoreChanged();
    void errorMessageChanged();

private:
    struct Item {
        QString roomId;
        QString title;
        QString owner;
        QString cover;
        QString area;
        QString watched;
    };

    void setLoading(bool value);
    void setErrorMessage(const QString &value);
    void setHasMore(bool value);
    void requestPage(bool reset);

    QVector<Item> m_items;
    QSet<QString> m_seenRoomIds;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_activeReply;
    bool m_loading;
    bool m_hasMore;
    int m_page;
    int m_generation;
    QString m_errorMessage;
};
