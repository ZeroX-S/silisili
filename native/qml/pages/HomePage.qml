import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property int networkScrollReleaseCount: 0
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "home"
        columns: 1
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
        interval: 120
        repeat: false
        onTriggered: {
            if (page.status === PageStatus.Active && Qt.application.active)
                listView.prepareCenteredVideo()
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: homeFeed
        spacing: Theme.paddingSmall
        clip: true

        function nearBottom() {
            return atYEnd
                   || visibleArea.yPosition + visibleArea.heightRatio > 0.92
                   || contentY + height >= contentHeight - Theme.itemSizeLarge * 2
        }

        function maybeLoadMore() {
            if (count <= 0 || !homeFeed.hasMore || homeFeed.loading)
                return
            if (contentHeight <= height)
                return
            if (nearBottom())
                homeFeed.loadMore()
        }
        function prepareCenteredVideo() {
            var item = itemAt(width / 2, contentY + height * 0.48)
            if (item && typeof item.preparePlayback === "function")
                item.preparePlayback()
        }
        onAtYEndChanged: maybeLoadMore()
        onContentYChanged: maybeLoadMore()
        onMovementStarted: {
            if (nativeTestPage === "network-scroll")
                console.log("native home: physical scroll movement started",
                            "contentY", Math.round(contentY))
        }
        onMovementEnded: {
            maybeLoadMore()
            prepareCenteredVideo()
            if (nativeTestPage === "network-scroll") {
                ++page.networkScrollReleaseCount
                console.log("native home: physical scroll movement ended",
                            "count", page.networkScrollReleaseCount,
                            "contentY", Math.round(contentY),
                            "loading", homeFeed.loading,
                            "error", homeFeed.errorMessage.length > 0)
            }
        }
        onCountChanged: maybeLoadMore()

        Connections {
            target: homeFeed
            onLoadingChanged: if (!homeFeed.loading) listView.maybeLoadMore()
        }

        Timer {
            interval: 600
            repeat: true
            running: page.status === PageStatus.Active && listView.count > 0
            onTriggered: listView.maybeLoadMore()
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
            width: listView.width
            height: Math.max(coverImage.height, details.implicitHeight) + 2 * Theme.paddingMedium
            function preparePlayback() {
                if (page.status === PageStatus.Active && Qt.application.active
                        && bvid.length > 0 && cid.length > 0)
                    playbackSession.prepareVideo(bvid, cid, 80)
            }
            // The feed already includes CID. Resolve the first visible cards
            // while the user is reading the list so a tap does not wait on a
            // transient multi-second playurl API response. Metadata prefetch is
            // limited to the first six cards; only one card at a time is ever
            // prepared by the single paused software decoder.
            Component.onCompleted: {
                if (bvid.length === 0 || cid.length === 0)
                    return
                if (index === 0)
                    preparePlayback()
                else if (index < 6)
                    playbackResolver.prefetchVideo(bvid, cid, 80)
            }
            onPressedChanged: {
                if (pressed)
                    preparePlayback()
            }
            onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoTitle: title,
                videoOwner: owner,
                videoBvid: bvid,
                videoCid: cid,
                videoCover: cover
            })

            Image {
                id: coverImage
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: Math.min(parent.width * 0.38, Theme.itemSizeHuge * 2)
                height: width * 9 / 16
                source: cover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
            }
            Column {
                id: details
                anchors.left: coverImage.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: coverImage.verticalCenter
                spacing: Theme.paddingSmall
                Label { width: parent.width; text: title; color: delegateRoot.highlighted ? Theme.highlightColor : Theme.primaryColor; font.pixelSize: Theme.fontSizeMedium; wrapMode: Text.Wrap; maximumLineCount: 2; truncationMode: TruncationMode.Fade }
                Label { width: parent.width; text: owner; color: Theme.secondaryColor; font.pixelSize: Theme.fontSizeSmall; truncationMode: TruncationMode.Fade }
                Label { width: parent.width; visible: recommendReason.length > 0; text: recommendReason; color: Theme.highlightColor; font.pixelSize: Theme.fontSizeExtraSmall; truncationMode: TruncationMode.Fade }
                Label { text: qsTr("播放 %1 · 弹幕 %2").arg(playCount).arg(danmakuCount); color: Theme.secondaryColor; font.pixelSize: Theme.fontSizeExtraSmall }
            }
        }

        footer: Item {
            width: listView.width
            height: Theme.itemSizeMedium
            visible: listView.count > 0

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Theme.paddingSmall
                running: homeFeed.loading && listView.count > 0
                size: BusyIndicatorSize.Small
                visible: running
            }
            Label {
                id: footerLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.paddingSmall
                horizontalAlignment: Text.AlignHCenter
                text: homeFeed.loading
                      ? qsTr("正在加载更多")
                      : homeFeed.hasMore
                        ? qsTr("上滑到底自动加载")
                        : qsTr("已经到底了")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
            }
        }

        VerticalScrollDecorator {}
        ViewPlaceholder {
            enabled: homeFeed.errorMessage.length > 0
            text: homeFeed.errorMessage
            hintText: qsTr("从顶部下拉即可重试")
        }
        BusyIndicator { anchors.centerIn: parent; running: homeFeed.loading; size: BusyIndicatorSize.Large }
    }
}
