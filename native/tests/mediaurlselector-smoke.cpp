#include "mediaurlselector.h"
#include <cassert>
#include <cstdio>

int main() {
    const QString cdn = QStringLiteral("https://upos-sz-mirrorcos.bilivideo.com/video.m4s?sig=a%2Bb&qn=80");
    const QString peer = QStringLiteral("https://node.edge.mountaintoys.cn:4483/video.m4s?sig=original");
    const QString mcdn = QStringLiteral("https://xy1.mcdn.bilivideo.cn:8082/video.m4s");
    QJsonObject media;
    media.insert(QStringLiteral("id"), 80);
    media.insert(QStringLiteral("codecid"), 7);
    media.insert(QStringLiteral("base_url"), peer);
    media.insert(QStringLiteral("backup_url"), QJsonArray{mcdn, cdn});
    assert(MediaUrlSelector::select(media) == cdn);
    assert(media.value(QStringLiteral("id")).toInt() == 80);
    assert(media.value(QStringLiteral("codecid")).toInt() == 7);
    media.insert(QStringLiteral("base_url"), QStringLiteral("https://cdn.example.com/original.m4s"));
    assert(MediaUrlSelector::select(media) == media.value(QStringLiteral("base_url")).toString());
    media.insert(QStringLiteral("base_url"), peer);
    media.insert(QStringLiteral("backup_url"), QJsonArray{mcdn});
    assert(MediaUrlSelector::select(media) == peer);
    media.insert(QStringLiteral("backup_url"), QJsonArray{QStringLiteral("http://cdn.example.com/file")});
    assert(MediaUrlSelector::select(media) == peer); // No HTTPS downgrade.
    QJsonObject camel;
    camel.insert(QStringLiteral("baseUrl"), mcdn);
    camel.insert(QStringLiteral("backupUrl"), QJsonArray{peer, cdn});
    assert(MediaUrlSelector::select(camel) == cdn);
    QJsonObject progressive;
    progressive.insert(QStringLiteral("url"), peer);
    progressive.insert(QStringLiteral("backup_url"), QJsonArray{cdn});
    assert(MediaUrlSelector::select(progressive) == cdn);
    QJsonObject backupOnly;
    backupOnly.insert(QStringLiteral("backup_url"), QJsonArray{cdn});
    assert(MediaUrlSelector::select(backupOnly) == cdn);
    assert(MediaUrlSelector::select(QJsonObject()).isEmpty());
    assert(MediaUrlSelector::ordinaryHttps(QStringLiteral("https://cdn.example.com:443/file")));
    assert(!MediaUrlSelector::ordinaryHttps(QStringLiteral("https://cdn.example.com:4483/file")));
    assert(!MediaUrlSelector::ordinaryHttps(QStringLiteral("https://xy1.mcdn.bilivideo.cn/file")));
    assert(!MediaUrlSelector::ordinaryHttps(QStringLiteral("http://cdn.example.com/file")));
    assert(!MediaUrlSelector::ordinaryHttps(QStringLiteral("/relative/file")));
    std::puts("media_url_selector=ready|same-track-preserved=1|signed-url-unchanged=1|ordinary-primary-preserved=1|peer-only-fallback=1|https-no-downgrade=1");
}
