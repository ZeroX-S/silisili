#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QVector>

class AccountService;
class QNetworkReply;

class InboxModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY stateChanged)
    Q_PROPERTY(QString feedTitle READ feedTitle NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)

public:
    enum Role {
        AuthorRole = Qt::UserRole + 1,
        AvatarRole,
        TitleRole,
        TextRole,
        TimeRole,
        CategoryRole
    };

    explicit InboxModel(AccountService *account, QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString feedTitle() const;
    QString errorMessage() const { return m_errorMessage; }

public slots:
    void showReplies();
    void showMentions();
    void showLikes();
    void refresh();
    void loadMore();

signals:
    void stateChanged();

private:
    struct Item {
        QString author;
        QString avatar;
        QString title;
        QString text;
        QString time;
        QString category;
    };

    void selectCategory(const QString &category);
    void request(bool reset);

    AccountService *m_account;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_activeReply;
    QVector<Item> m_items;
    QSet<QString> m_seen;
    bool m_loading;
    bool m_hasMore;
    int m_generation;
    QString m_category;
    QString m_cursorId;
    QString m_cursorTime;
    QString m_errorMessage;
};
