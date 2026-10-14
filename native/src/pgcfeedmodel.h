#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QVector>

class QNetworkReply;

class PgcFeedModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY stateChanged)
    Q_PROPERTY(QString feedTitle READ feedTitle NOTIFY stateChanged)
    Q_PROPERTY(QString category READ category NOTIFY stateChanged)
    Q_PROPERTY(QString firstSeasonId READ firstSeasonId NOTIFY stateChanged)
    Q_PROPERTY(QString initialSignature READ initialSignature NOTIFY stateChanged)
    Q_PROPERTY(int itemCount READ itemCount NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)

public:
    enum Role {
        TitleRole = Qt::UserRole + 1,
        DescriptionRole,
        CoverRole,
        SeasonIdRole,
        BadgeRole,
        SectionRole
    };

    explicit PgcFeedModel(QObject *parent = 0);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }
    bool hasMore() const { return m_hasMore; }
    QString feedTitle() const;
    QString category() const { return m_category; }
    QString firstSeasonId() const {
        return m_items.isEmpty() ? QString() : m_items.first().seasonId;
    }
    QString initialSignature() const { return m_initialSignature; }
    int itemCount() const { return m_items.size(); }
    QString errorMessage() const { return m_error; }

public slots:
    void showBangumiRank();
    void showBangumi();
    void showCinema();
    void refresh();
    void loadMore();

signals:
    void stateChanged();

private:
    struct Item {
        QString title, description, cover, seasonId, badge, section;
    };

    struct CategorySnapshot {
        CategorySnapshot() : hasMore(false), valid(false) {}
        QVector<Item> items;
        QSet<QString> seen;
        QString cursor;
        QString error;
        QString initialSignature;
        bool hasMore;
        bool valid;
    };

    void selectCategory(const QString &category);
    void cancelActiveRequest();
    void clearCurrentState(bool keepRows = false);
    void storeCurrentSnapshot();
    bool restoreSnapshot(const QString &category);
    void refreshInternal(bool rotateContent);
    void request(bool reset, bool rotateContent);
    void requestRank(bool reset, bool rotateContent);
    void requestTab(bool reset, bool rotateContent);
    QString signatureFor(const QVector<Item> &items) const;

    QNetworkAccessManager m_network;
    QVector<Item> m_items;
    QSet<QString> m_seen;
    bool m_loading;
    bool m_hasMore;
    QString m_category;
    QString m_cursor;
    QString m_error;
    QString m_initialSignature;
    QPointer<QNetworkReply> m_reply;
    int m_requestGeneration;
    QHash<QString, CategorySnapshot> m_snapshots;
};
