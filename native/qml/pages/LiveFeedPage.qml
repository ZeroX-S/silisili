import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "live-feed"
        columns: 1
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: liveFeed
        spacing: Theme.paddingSmall
        clip: true

        onContentYChanged: {
            if (liveFeed.hasMore && !liveFeed.loading
                    && contentY + height >= contentHeight - Theme.itemSizeHuge * 2)
                liveFeed.loadMore()
        }

        PullDownMenu {
            MenuItem { text: qsTr("刷新"); onClicked: liveFeed.refresh() }
        }

        header: Column {
            width: listView.width
            PageHeader { title: qsTr("直播"); description: qsTr("正在直播") }
            SectionHeader { text: qsTr("推荐直播间") }
        }

        delegate: BackgroundItem {
            id: delegateRoot
            width: listView.width
            height: Math.max(coverImage.height, details.implicitHeight) + 2 * Theme.paddingMedium
            onClicked: pageStack.push(Qt.resolvedUrl("LivePlayerPage.qml"), {
                roomId: roomId,
                roomTitle: title,
                roomOwner: owner,
                roomCover: cover
            })

            Image {
                id: coverImage
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: Math.min(parent.width * 0.42, Theme.itemSizeHuge * 2)
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

                Label {
                    width: parent.width
                    text: title
                    color: delegateRoot.highlighted ? Theme.highlightColor : Theme.primaryColor
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: owner
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: area + (watched.length > 0 ? "  ·  " + watched : "")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        footer: Item {
            width: listView.width
            height: liveFeed.loading || liveFeed.hasMore
                    ? Theme.itemSizeHuge : Theme.itemSizeLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: liveFeed.loading && listView.count > 0
                size: BusyIndicatorSize.Medium
            }
            Button {
                anchors.centerIn: parent
                visible: liveFeed.hasMore && !liveFeed.loading
                text: qsTr("加载更多直播")
                onClicked: liveFeed.loadMore()
            }
            Label {
                anchors.centerIn: parent
                visible: !liveFeed.loading && !liveFeed.hasMore && listView.count > 0
                text: qsTr("已加载全部直播")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
        ViewPlaceholder {
            enabled: liveFeed.errorMessage.length > 0
            text: liveFeed.errorMessage
            hintText: qsTr("从顶部下拉即可重试")
        }
        BusyIndicator {
            anchors.centerIn: parent
            running: liveFeed.loading && listView.count === 0
            size: BusyIndicatorSize.Large
        }
    }

    Component.onCompleted: liveFeed.refresh()
}
