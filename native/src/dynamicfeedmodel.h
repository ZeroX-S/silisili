#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QVector>

class AccountService;
class QNetworkReply;

class DynamicFeedModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)
    Q_PROPERTY(QString section READ section WRITE setSection NOTIFY stateChanged)

public:
    enum Role {
        AuthorRole = Qt::UserRole + 1,
        AvatarRole,
        TextRole,
        TitleRole,
        CoverRole,
        BvidRole,
        TimeRole,
        KindRole,
        SourceRole,
        ImageUrlsRole,
        SeasonIdRole,
        RoomIdRole,
        StatsRole,
        DynamicIdRole,
        CommentOidRole,
        CommentTypeRole
    };

    explicit DynamicFeedModel(AccountService *account, QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString errorMessage() const { return m_errorMessage; }
    QString section() const { return m_section; }

public slots:
    void setSection(const QString &section);
    void refresh();
    void loadMore();

signals:
    void stateChanged();

private:
    struct Item {
        QString author;
        QString avatar;
        QString text;
        QString title;
        QString cover;
        QString bvid;
        QString time;
        QString kind;
        QString source;
        QStringList imageUrls;
        QString seasonId;
        QString roomId;
        QString stats;
        QString dynamicId;
        QString commentOid;
        int commentType = 17;
    };

    static QString normalizedUrl(const QString &url);
    static QString jsonId(const QJsonValue &value);
    static void parseMajor(const QJsonObject &major, Item *item);
    static void parseOriginal(const QJsonObject &original, Item *item);
    void request(bool reset);

    AccountService *m_account;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_activeReply;
    QVector<Item> m_items;
    QSet<QString> m_seen;
    bool m_loading;
    bool m_hasMore;
    int m_generation;
    QString m_offset;
    QString m_errorMessage;
    QString m_section;
};
