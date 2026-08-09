#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QVariantList>

class PgcDetailModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString cover READ cover NOTIFY changed)
    Q_PROPERTY(QString description READ description NOTIFY changed)
    Q_PROPERTY(QString ratingText READ ratingText NOTIFY changed)
    Q_PROPERTY(QString stats READ stats NOTIFY changed)
    Q_PROPERTY(QVariantList episodes READ episodes NOTIFY changed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY changed)

public:
    explicit PgcDetailModel(QObject *parent = 0);
    bool loading() const { return m_loading; }
    QString title() const { return m_title; }
    QString cover() const { return m_cover; }
    QString description() const { return m_description; }
    QString ratingText() const { return m_ratingText; }
    QString stats() const { return m_stats; }
    QVariantList episodes() const { return m_episodes; }
    QString errorMessage() const { return m_error; }

public slots:
    void load(const QString &seasonId);
    void loadEpisode(const QString &episodeId);

signals:
    void changed();

private:
    void loadById(const QString &queryKey, const QString &queryValue);
    QNetworkAccessManager m_network;
    bool m_loading;
    QString m_seasonId, m_title, m_cover, m_description, m_ratingText, m_stats, m_error;
    QVariantList m_episodes;
};
