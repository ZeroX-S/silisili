#pragma once
#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QVariantMap>
#include <QVector>
class RelatedModel:public QAbstractListModel{
Q_OBJECT
Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
Q_PROPERTY(int count READ count NOTIFY stateChanged)
Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY stateChanged)
public:enum Role{TitleRole=Qt::UserRole+1,OwnerRole,CoverRole,BvidRole,PlayRole};explicit RelatedModel(QObject*p=0);int rowCount(const QModelIndex&p=QModelIndex())const override;QVariant data(const QModelIndex&i,int r)const override;QHash<int,QByteArray>roleNames()const override;bool loading()const{return m_loading;}
int count()const{return m_items.size();}
QString errorMessage()const{return m_error;}
Q_INVOKABLE QVariantMap get(int row)const;
public slots:void load(const QString&bvid);signals:void stateChanged();
private:struct Item{QString title,owner,cover,bvid,play;};QNetworkAccessManager m_network;QVector<Item>m_items;bool m_loading;QString m_bvid, m_error;};
