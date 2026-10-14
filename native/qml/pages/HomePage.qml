import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components/ImageUrls.js" as ImageUrls
import "../components"

Page {
    id: page
    property int networkScrollReleaseCount: 0
    readonly property int contentColumns: appSettings.contentColumns === 2 ? 2 : 1
    readonly property real gridCellWidth: width / contentColumns
    readonly property bool horizontalCards: contentColumns === 1 || width > height
    readonly property real singleCoverWidth:
        Math.min(gridCellWidth * 0.38, Theme.itemSizeHuge * 2)
    readonly property real gridCellHeight: horizontalCards
        ? Math.max(singleCoverWidth * 9 / 16, cardTextHeight)
          + 2 * Theme.paddingMedium
        : (gridCellWidth - 2 * Theme.paddingMedium) * 9 / 16
          + cardTextHeight + 3 * Theme.paddingMedium
    readonly property real cardTextHeight: cardMetrics.titleHeight
        + 3 * cardMetrics.metadataHeight + 3 * Theme.paddingSmall
    CardTextMetrics { id: cardMetrics }
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "home"
        columns: page.contentColumns
    }

    onStatusChanged: {
        if (status === PageStatus.Active && Qt.application.active)
            foregroundPrepareTimer.restart()
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.active && page.status === PageStatus.Active)
                foregroundPrepareTimer.restart()
        }
    }

    Timer {
        id: foregroundPrepareTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (page.status === PageStatus.Active && Qt.application.active
                    && !listView.moving && !listView.dragging
                    && !homeFeed.loading && !playbackSession.active)
                listView.prepareCenteredVideo()
        }
    }

    FeedPagination {
        id: pagination
        view: listView
        feed: homeFeed
        pageActive: page.status === PageStatus.Active
        loading: homeFeed.loading
        hasMore: homeFeed.hasMore
        itemCount: listView.count
        errorMessage: homeFeed.errorMessage
    }

    SilicaGridView {
        id: listView
        anchors.fill: parent
        cacheBuffer: height
        model: homeFeed
        cellWidth: page.gridCellWidth
        cellHeight: page.gridCellHeight
        clip: true

        function maybeLoadMore() { pagination.schedule() }
        function prepareCenteredVideo() {
            if (moving || dragging || homeFeed.loading || playbackSession.active
                    || page.status !== PageStatus.Active || !Qt.application.active)
                return
            var item = itemAt(width / 2, contentY + height * 0.48)
            if (item && typeof item.preparePlayback === "function")
                item.preparePlayback()
        }
        onAtYEndChanged: maybeLoadMore()
        onContentYChanged: maybeLoadMore()
        onMovementStarted: {
            foregroundPrepareTimer.stop()
            if (nativeTestPage === "network-scroll")
                console.log("native home: physical scroll movement started",
                            "contentY", Math.round(contentY))
        }
        onMovementEnded: {
            maybeLoadMore()
            foregroundPrepareTimer.restart()
            if (nativeTestPage === "network-scroll") {
                ++page.networkScrollReleaseCount
                console.log("native home: physical scroll movement ended",
                            "count", page.networkScrollReleaseCount,
                            "contentY", Math.round(contentY),
                            "loading", homeFeed.loading,
                            "error", homeFeed.errorMessage.length > 0)
            }
        }
        onCountChanged: {
            maybeLoadMore()
            foregroundPrepareTimer.restart()
        }

        Connections {
            target: homeFeed
            onLoadingChanged: {
                if (!homeFeed.loading) {
                    listView.maybeLoadMore()
                    foregroundPrepareTimer.restart()
                }
            }
        }



        PullDownMenu {
            MenuItem { text: qsTr("关于 silisili"); onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml")) }
            MenuItem { text: qsTr("更多内容"); onClicked: pageStack.push(Qt.resolvedUrl("NavigationPage.qml")) }
            MenuItem { text: qsTr("搜索"); onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml")) }
            MenuItem { text: qsTr("刷新"); onClicked: homeFeed.refresh() }
        }

        header: Column {
            width: listView.width

            PageHeader {
                title: qsTr("SiliSili")
                description: accountService.loggedIn
                             ? accountService.userName : qsTr("Sailfish OS 原生版")
            }

            Row {
                id: primaryNavigation
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeMedium

                NavigationTile {
                    width: primaryNavigation.width / 4
                    height: primaryNavigation.height
                    title: qsTr("直播")
                    titleFontSize: Theme.fontSizeMedium
                    onClicked: pageStack.push(Qt.resolvedUrl("LiveFeedPage.qml"))
                }
                NavigationTile {
                    width: primaryNavigation.width / 4
                    height: primaryNavigation.height
                    title: qsTr("推荐")
                    titleFontSize: Theme.fontSizeMedium
                    selected: homeFeed.feedKind === "recommended"
                    onClicked: homeFeed.showRecommended()
                }
                NavigationTile {
                    width: primaryNavigation.width / 4
                    height: primaryNavigation.height
                    title: qsTr("热门")
                    titleFontSize: Theme.fontSizeMedium
                    selected: homeFeed.feedKind === "popular"
                    onClicked: homeFeed.showPopular()
                }
                NavigationTile {
                    width: primaryNavigation.width / 4
                    height: primaryNavigation.height
                    title: qsTr("追番")
                    titleFontSize: Theme.fontSizeMedium
                    onClicked: pageStack.push(Qt.resolvedUrl("PgcFeedPage.qml"))
                }
            }

            SectionHeader { text: homeFeed.feedTitle }
        }

        delegate: BackgroundItem {
            id: delegateRoot
            width: listView.cellWidth
            height: listView.cellHeight
            function preparePlayback() {
                if (page.status === PageStatus.Active && Qt.application.active
                        && bvid.length > 0 && cid.length > 0)
                    playbackSession.prepareVideo(bvid, cid,
                                                 accountService.defaultPlaybackQuality)
            }
            // Only the idle viewport timer prefetches metadata. A press may
            // become a swipe; it must never start or replace a video decoder.
            onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoTitle: title,
                videoOwner: owner,
                videoBvid: bvid,
                videoCid: cid,
                videoCover: cover
            })

            Image {
                id: coverImage
                x: page.horizontalCards
                   ? Theme.horizontalPageMargin : Theme.paddingMedium
                y: page.horizontalCards ? (parent.height - height) / 2 : Theme.paddingMedium
                width: page.horizontalCards
                       ? page.singleCoverWidth
                       : parent.width - 2 * Theme.paddingMedium
                height: width * 9 / 16
                source: ImageUrls.thumbnail(cover, width)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
            }
            Column {
                id: details
                x: page.horizontalCards
                   ? coverImage.x + coverImage.width + Theme.paddingMedium
                   : Theme.paddingMedium
                y: page.horizontalCards
                   ? Math.max(Theme.paddingMedium,
                              coverImage.y + (coverImage.height - implicitHeight) / 2)
                   : coverImage.y + coverImage.height + Theme.paddingSmall
                width: page.horizontalCards
                       ? parent.width - x - Theme.horizontalPageMargin
                       : parent.width - 2 * Theme.paddingMedium
                spacing: Theme.paddingSmall
                AppLabel { width: parent.width; text: title; color: delegateRoot.highlighted ? Theme.highlightColor : Theme.primaryColor; wrapMode: Text.Wrap; maximumLineCount: 2; truncationMode: TruncationMode.Fade }
                AppLabel { width: parent.width; text: owner; color: Theme.secondaryColor; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode); truncationMode: TruncationMode.Fade }
                AppLabel { width: parent.width; visible: recommendReason.length > 0; text: recommendReason; color: Theme.highlightColor; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode); truncationMode: TruncationMode.Fade }
                AppLabel { width: parent.width; text: qsTr("播放 %1 · 弹幕 %2").arg(playCount).arg(danmakuCount); color: Theme.secondaryColor; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode); truncationMode: TruncationMode.Fade }
            }
        }

        footer: Item {
            width: listView.width
            height: Math.max(Theme.itemSizeMedium, footerLabel.implicitHeight + Theme.iconSizeSmall + 3 * Theme.paddingSmall)
            visible: listView.count > 0

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Theme.paddingSmall
                running: homeFeed.loading && listView.count > 0
                size: BusyIndicatorSize.Small
                visible: running
            }
            AppLabel {
                id: footerLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.paddingSmall
                horizontalAlignment: Text.AlignHCenter
                text: homeFeed.errorMessage.length > 0 ? homeFeed.errorMessage
                      : homeFeed.loading
                      ? qsTr("正在加载更多")
                      : homeFeed.hasMore
                        ? qsTr("上滑到底自动加载")
                        : qsTr("已经到底了")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                truncationMode: TruncationMode.Fade
            }
        }

        VerticalScrollDecorator {}
        ViewPlaceholder {
            enabled: listView.count === 0 && homeFeed.errorMessage.length > 0
            text: homeFeed.errorMessage
            hintText: qsTr("从顶部下拉即可重试")
        }
        BusyIndicator { anchors.centerIn: parent; running: homeFeed.loading && listView.count === 0; size: BusyIndicatorSize.Large }
    }
}
