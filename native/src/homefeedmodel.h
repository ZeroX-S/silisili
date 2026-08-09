#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QVector>

class AccountService;
class QNetworkReply;

class HomeFeedModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY hasMoreChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString feedKind READ feedKind NOTIFY feedChanged)
    Q_PROPERTY(QString feedTitle READ feedTitle NOTIFY feedChanged)

public:
    enum Role { TitleRole = Qt::UserRole + 1, OwnerRole, CoverRole, BvidRole,
                CidRole, PlayRole, DanmakuRole, ReasonRole };
    explicit HomeFeedModel(AccountService *accountService, QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString errorMessage() const { return m_errorMessage; }
    QString feedKind() const { return m_feedKind; }
    QString feedTitle() const;

public slots:
    void refresh();
    void loadMore();
    void showRecommended();
    void showPopular();

signals:
    void loadingChanged();
    void hasMoreChanged();
    void errorMessageChanged();
    void feedChanged();

private:
    struct Item { QString title, owner, cover, bvid, cid, play, danmaku, reason; };
    void setLoading(bool value);
    void setHasMore(bool value);
    void setErrorMessage(const QString &value);
    void loadFeed(const QString &feedKind);
    void requestFeed(bool reset);
    static QString countText(qint64 value);

    QVector<Item> m_items;
    QSet<QString> m_seenBvids;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_activeReply;
    AccountService *m_accountService;
    bool m_loading, m_hasMore;
    int m_requestSerial, m_nextPage;
    QString m_errorMessage, m_feedKind;
};
