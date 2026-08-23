import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    readonly property int contentColumns: appSettings.contentColumns === 2 ? 2 : 1
    readonly property real gridCellWidth: width / contentColumns
    readonly property real singleCoverWidth:
        Math.min(width * 0.42, Theme.itemSizeHuge * 2)
    readonly property real gridCellHeight: contentColumns === 1
        ? Math.max(singleCoverWidth * 9 / 16, Theme.itemSizeLarge * 1.35)
          + 2 * Theme.paddingMedium
        : Math.max(Theme.itemSizeHuge * 1.5,
                   (gridCellWidth - 2 * Theme.paddingMedium) * 9 / 16
                   + Theme.itemSizeLarge * 1.35 + 2 * Theme.paddingMedium)
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "live-feed"
        columns: page.contentColumns
    }

    SilicaGridView {
        id: listView
        anchors.fill: parent
        model: liveFeed
        cellWidth: page.gridCellWidth
        cellHeight: page.gridCellHeight
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
            width: listView.cellWidth
            height: listView.cellHeight
            onClicked: pageStack.push(Qt.resolvedUrl("LivePlayerPage.qml"), {
                roomId: roomId,
                roomTitle: title,
                roomOwner: owner,
                roomCover: cover
            })

            Image {
                id: coverImage
                x: page.contentColumns === 1
                   ? Theme.horizontalPageMargin : Theme.paddingMedium
                y: Theme.paddingMedium
                width: page.contentColumns === 1
                       ? page.singleCoverWidth
                       : parent.width - 2 * Theme.paddingMedium
                height: width * 9 / 16
                source: cover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
            }
            Column {
                id: details
                x: page.contentColumns === 1
                   ? coverImage.x + coverImage.width + Theme.paddingMedium
                   : Theme.paddingMedium
                y: page.contentColumns === 1
                   ? Math.max(Theme.paddingMedium,
                              coverImage.y + (coverImage.height - implicitHeight) / 2)
                   : coverImage.y + coverImage.height + Theme.paddingSmall
                width: page.contentColumns === 1
                       ? parent.width - x - Theme.horizontalPageMargin
                       : parent.width - 2 * Theme.paddingMedium
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    text: title
                    color: delegateRoot.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: appSettings.scaledFontSize(
                                        page.contentColumns === 1
                                        ? Theme.fontSizeMedium
                                        : Theme.fontSizeSmall, appSettings.fontSizeMode)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: owner
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: area + (watched.length > 0 ? "  ·  " + watched : "")
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
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
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
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
