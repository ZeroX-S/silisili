#pragma once

#include <QQuickPaintedItem>
#include <QString>
#include <QVector>

class QPainter;

class QrCodeItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString sourceText READ sourceText WRITE setSourceText
               NOTIFY sourceTextChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY renderStateChanged)
    Q_PROPERTY(int moduleCount READ moduleCount NOTIFY renderStateChanged)
    Q_PROPERTY(QString error READ error NOTIFY renderStateChanged)

public:
    explicit QrCodeItem(QQuickItem *parent = 0);

    QString sourceText() const { return m_sourceText; }
    bool valid() const { return m_moduleCount > 0 && !m_modules.isEmpty(); }
    int moduleCount() const { return m_moduleCount; }
    QString error() const { return m_error; }

    void setSourceText(const QString &sourceText);
    void paint(QPainter *painter) override;

    static bool selfTest(int *moduleCount = 0);

signals:
    void sourceTextChanged();
    void renderStateChanged();

private:
    static bool encode(const QString &sourceText, QVector<quint8> *modules,
                       int *moduleCount, QString *error);
    void rebuild();

    QString m_sourceText;
    QVector<quint8> m_modules;
    int m_moduleCount;
    QString m_error;
};
