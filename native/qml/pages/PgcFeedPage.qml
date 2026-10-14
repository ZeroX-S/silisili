import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components/ImageUrls.js" as ImageUrls
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property bool consistencyRegression: false
    property int consistencyStage: 0
    property string consistencyBangumiFirst
    property string consistencyBangumiSignature
    property int consistencyCycles: 0
    property bool consistencyStable: true
    allowedOrientations: Orientation.All

    PgcFeedModel { id: pgcFeed }

    ResponsivePageMetrics {
        target: page
        pageName: "pgc-feed"
        columns: 1
    }

    Component.onCompleted: {
        if (consistencyRegression)
            pgcFeed.showBangumi()
        else
            pgcFeed.refresh()
    }

    Timer {
        interval: 150
        repeat: true
        running: page.consistencyRegression && page.consistencyStage < 4
        onTriggered: {
            if (pgcFeed.loading || pgcFeed.itemCount <= 0)
                return
            if (page.consistencyStage === 0 && pgcFeed.category === "bangumi") {
                page.consistencyBangumiFirst = pgcFeed.firstSeasonId
                page.consistencyBangumiSignature = pgcFeed.initialSignature
                page.consistencyStage = 1
                console.log("native pgc consistency: regression bangumi captured",
                            "firstSeasonId", page.consistencyBangumiFirst,
                            "items", pgcFeed.itemCount,
                            "signature", page.consistencyBangumiSignature)
                feedList.positionViewAtEnd()
                pgcFeed.showCinema()
            } else if (page.consistencyStage === 1
                       && pgcFeed.category === "cinema") {
                var categoryDifferent =
                        pgcFeed.initialSignature
                        !== page.consistencyBangumiSignature
                page.consistencyStable = page.consistencyStable
                                         && categoryDifferent
                console.log("native pgc consistency: regression cinema captured",
                            "firstSeasonId", pgcFeed.firstSeasonId,
                            "items", pgcFeed.itemCount,
                            "differentFromBangumi", categoryDifferent)
                page.consistencyStage = 2
                feedList.positionViewAtEnd()
                pgcFeed.showBangumi()
            } else if (page.consistencyStage === 2
                       && pgcFeed.category === "bangumi") {
                var cycleStable =
                        pgcFeed.initialSignature
                        === page.consistencyBangumiSignature
                page.consistencyStable = page.consistencyStable && cycleStable
                page.consistencyCycles += 1
                console.log("native pgc consistency: regression cycle",
                            "cycle", page.consistencyCycles,
                            "stable", cycleStable,
                            "firstSeasonId", pgcFeed.firstSeasonId,
                            "items", pgcFeed.itemCount)
                if (page.consistencyCycles < 8) {
                    page.consistencyStage = 1
                    feedList.positionViewAtEnd()
                    pgcFeed.showCinema()
                } else {
                    page.consistencyStage = 3
                    // Rapidly cross two categories while requests are being
                    // replaced. The final Bangumi response must be the only
                    // one allowed to commit.
                    pgcFeed.showCinema()
                    pgcFeed.showBangumiRank()
                    pgcFeed.showBangumi()
                }
            } else if (page.consistencyStage === 3
                       && pgcFeed.category === "bangumi") {
                var rapidRestoreStable =
                        pgcFeed.initialSignature
                        === page.consistencyBangumiSignature
                page.consistencyStable = page.consistencyStable
                                         && rapidRestoreStable
                console.log("native pgc consistency: regression ready",
                            "stable", page.consistencyStable,
                            "cycles", page.consistencyCycles,
                            "category", pgcFeed.category,
                            "firstSeasonId", pgcFeed.firstSeasonId,
                            "items", pgcFeed.itemCount,
                            "rapidStable", rapidRestoreStable)
                page.consistencyStage = 4
            }
        }
    }

    FeedPagination {
        id: pagination
        view: feedList
        feed: pgcFeed
        pageActive: page.status === PageStatus.Active
        loading: pgcFeed.loading
        hasMore: pgcFeed.hasMore
        itemCount: feedList.count
        errorMessage: pgcFeed.errorMessage
    }

    SilicaListView {
        id: feedList
        anchors.fill: parent
        cacheBuffer: height
        model: pgcFeed
        clip: true
        spacing: Theme.paddingSmall


        PullDownMenu {
            MenuItem { text: qsTr("刷新"); onClicked: pgcFeed.refresh() }
        }

        header: Column {
            width: feedList.width
            PageHeader { title: qsTr("追番"); description: qsTr("热搜榜与分类内容") }
            ComboBox {
                width: parent.width
                label: qsTr("内容分类")
                value: pgcFeed.feedTitle
                menu: ContextMenu {
                    MenuItem { text: qsTr("追番热搜榜"); onClicked: pgcFeed.showBangumiRank() }
                    MenuItem { text: qsTr("番剧"); onClicked: pgcFeed.showBangumi() }
                    MenuItem { text: qsTr("影视"); onClicked: pgcFeed.showCinema() }
                }
            }
            SectionHeader { text: pgcFeed.feedTitle }
        }

        delegate: BackgroundItem {
            id: feedItem
            width: feedList.width
            height: Math.max(poster.height, details.implicitHeight) + 2 * Theme.paddingMedium
            onClicked: pageStack.push(Qt.resolvedUrl("PgcDetailPage.qml"), {
                seasonId: seasonId,
                initialTitle: title,
                initialCover: cover
            })

            Image {
                id: poster
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.29, Theme.itemSizeHuge * 1.35)
                height: width * 4 / 3
                source: ImageUrls.thumbnail(cover, width)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
            }
            Column {
                id: details
                anchors.left: poster.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall

                AppLabel {
                    width: parent.width
                    text: title
                    color: feedItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    visible: descriptionText.length > 0
                    text: descriptionText
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    visible: badge.length > 0
                    text: badge
                    color: Theme.highlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    visible: sectionTitle.length > 0
                    text: sectionTitle
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        footer: Item {
            width: feedList.width
            height: pgcFeed.hasMore || pgcFeed.loading ? Theme.itemSizeLarge : Theme.paddingLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: pgcFeed.loading
                size: BusyIndicatorSize.Medium
            }
            Button {
                anchors.centerIn: parent
                visible: pgcFeed.hasMore && !pgcFeed.loading
                text: qsTr("加载更多")
                onClicked: pgcFeed.errorMessage.length > 0
                           ? pgcFeed.refresh() : pgcFeed.loadMore()
            }
        }

        ViewPlaceholder {
            enabled: !pgcFeed.loading && feedList.count === 0
            text: pgcFeed.errorMessage.length > 0 ? pgcFeed.errorMessage : qsTr("暂无内容")
            hintText: qsTr("从顶部下拉可重试")
        }
        VerticalScrollDecorator {}
    }
}
