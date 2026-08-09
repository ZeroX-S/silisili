#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QVector>

class AccountService;
class QJsonObject;
class QJsonValue;
class QNetworkRequest;
class QNetworkReply;
class QUrl;

class AccountLibraryModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY configurationChanged)
    Q_PROPERTY(QString collectionId READ collectionId WRITE setCollectionId NOTIFY configurationChanged)
    Q_PROPERTY(int collectionType READ collectionType WRITE setCollectionType NOTIFY configurationChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY stateChanged)

public:
    enum Role {
        TitleRole = Qt::UserRole + 1,
        SubtitleRole,
        CoverRole,
        BvidRole,
        CidRole,
        SeasonIdRole,
        EpisodeIdRole,
        RoomIdRole,
        FolderIdRole,
        FolderTypeRole,
        BadgeRole,
        ProgressTextRole,
        ProgressRatioRole,
        ResumePositionRole,
        KindRole,
        OwnerRole,
        CanOpenRole
    };

    explicit AccountLibraryModel(QObject *parent = 0);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString mode() const { return m_mode; }
    void setMode(const QString &mode);
    QString collectionId() const { return m_collectionId; }
    void setCollectionId(const QString &collectionId);
    int collectionType() const { return m_collectionType; }
    void setCollectionType(int collectionType);
    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString errorMessage() const { return m_errorMessage; }
    int totalCount() const { return m_totalCount; }

public slots:
    void refresh();
    void loadMore();

signals:
    void configurationChanged();
    void stateChanged();

private:
    struct Item {
        QString title;
        QString subtitle;
        QString cover;
        QString bvid;
        QString cid;
        QString seasonId;
        QString episodeId;
        QString roomId;
        QString folderId;
        int folderType = 0;
        QString badge;
        QString progressText;
        qreal progressRatio = -1.0;
        qreal resumePosition = 0.0;
        QString kind;
        QString owner;
        bool canOpen = false;
    };

    QNetworkRequest requestFor(const QUrl &url) const;
    void request(bool reset);
    QVector<Item> parseItems(const QJsonObject &data, bool reset);
    QVector<Item> parseHistory(const QJsonObject &data);
    QVector<Item> parseFolders(const QJsonObject &data, bool subscriptions);
    QVector<Item> parseCollection(const QJsonObject &data);
    QVector<Item> parseBangumi(const QJsonObject &data);
    QVector<Item> parseLater(const QJsonObject &data);
    static QString jsonId(const QJsonValue &value);
    static QString normalizedUrl(QString value);
    static QString formatDuration(int seconds);
    static QString formatDate(qint64 epochSeconds);
    static QString formatCount(qint64 count);

    AccountService *m_account;
    QNetworkAccessManager m_network;
    QVector<Item> m_items;
    QString m_mode;
    QString m_collectionId;
    int m_collectionType;
    bool m_loading;
    bool m_hasMore;
    QString m_errorMessage;
    int m_totalCount;
    int m_page;
    qint64 m_historyMax;
    qint64 m_historyViewAt;
    QString m_historyBusiness;
    int m_generation;
    QPointer<QNetworkReply> m_activeReply;
};
