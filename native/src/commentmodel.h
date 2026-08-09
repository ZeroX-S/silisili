#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QSet>
#include <QVector>

class CommentModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool posting READ posting NOTIFY stateChanged)
    Q_PROPERTY(bool actioning READ actioning NOTIFY stateChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY stateChanged)
    Q_PROPERTY(int count READ count NOTIFY stateChanged)
    Q_PROPERTY(int revision READ revision NOTIFY stateChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)

public:
    enum Role {
        AuthorRole = Qt::UserRole + 1,
        AvatarRole,
        MessageRole,
        LikeRole,
        ReplyRole,
        TimeRole,
        RpidRole,
        PinnedRole,
        LikedRole
    };

    explicit CommentModel(QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    bool posting() const { return m_posting; }
    bool actioning() const { return m_actioning; }
    bool hasMore() const { return m_hasMore; }
    int count() const { return m_items.size(); }
    int revision() const { return m_revision; }
    int totalCount() const { return m_totalCount; }
    QString errorMessage() const { return m_error; }

    Q_INVOKABLE QVariantMap get(int row) const;

public slots:
    void load(const QString &aid);
    void loadResource(const QString &oid, int type);
    void loadThread(const QString &aid, const QString &rootRpid);
    void loadThreadResource(const QString &oid, int type, const QString &rootRpid);
    void refresh();
    void loadMore();
    void postComment(const QString &message);
    void postReply(const QString &message, const QString &parentRpid,
                   const QString &rootRpid, const QString &replyAuthor = QString());
    void toggleLike(int row);
    void toggleLikeRpid(const QString &rpid, bool currentlyLiked, int likeCount);

signals:
    void stateChanged();
    void commentPosted();
    void replyPosted(const QString &rootRpid, const QString &newRpid);
    void commentLikeChanged(const QString &rpid, bool liked, int likeCount);

private:
    struct Item {
        QString author, avatar, message, time, rpid;
        int likeCount = 0;
        int replyCount = 0;
        bool pinned = false;
        bool liked = false;
    };

    void requestPage(bool reset);
    void appendReplies(const QJsonArray &replies, bool pinned, QVector<Item> *items);
    void submitComment(const QString &message, const QString &parentRpid,
                       const QString &rootRpid, const QString &replyAuthor);
    int rowForRpid(const QString &rpid) const;
    void setItemLike(int row, bool liked, int likeCount);

    QNetworkAccessManager m_network;
    QVector<Item> m_items;
    QSet<QString> m_seenRpids;
    bool m_loading;
    bool m_posting;
    bool m_actioning;
    bool m_hasMore;
    bool m_refreshPending;
    bool m_threadMode;
    int m_next;
    int m_totalCount;
    int m_revision;
    int m_type;
    bool m_simulateActions;
    QString m_error, m_aid, m_rootRpid;
};
