#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QVector>
#include <QStringList>
#include <QPointer>

class AccountService;
class QNetworkReply;

class SearchModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString query READ query NOTIFY queryChanged)
    Q_PROPERTY(QStringList history READ history NOTIFY historyChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY loadingChanged)
public:
    enum Role { TitleRole = Qt::UserRole + 1, OwnerRole, CoverRole, BvidRole, PlayRole, DurationRole };
    explicit SearchModel(AccountService *accountService, QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool loading() const { return m_loading; }
    QString errorMessage() const { return m_errorMessage; }
    QString query() const { return m_query; }
    QStringList history() const { return m_history; }
    bool hasMore() const { return m_hasMore; }
public slots:
    void search(const QString &query);
    void loadMore();
    void clearHistory();
signals:
    void loadingChanged();
    void errorMessageChanged();
    void queryChanged();
    void historyChanged();
private:
    void requestPage(bool reset);
    struct Item { QString title, owner, cover, bvid, play, duration; };
    void setLoading(bool value);
    void setErrorMessage(const QString &value);
    QVector<Item> m_items;
    QNetworkAccessManager m_network;
    AccountService *m_accountService;
    bool m_loading;
    QString m_errorMessage;
    QString m_query;
    QStringList m_history;
    int m_page;
    bool m_hasMore;
    quint64 m_requestSerial;
    QPointer<QNetworkReply> m_activeReply;
};
