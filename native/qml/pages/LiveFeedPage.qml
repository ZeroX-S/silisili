import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components/ImageUrls.js" as ImageUrls
import "../components"

Page {
    id: page
    readonly property int contentColumns: appSettings.contentColumns === 2 ? 2 : 1
    readonly property real gridCellWidth: width / contentColumns
    readonly property bool horizontalCards: contentColumns === 1 || width > height
    readonly property real singleCoverWidth:
        Math.min(gridCellWidth * 0.42, Theme.itemSizeHuge * 2)
    readonly property real gridCellHeight: horizontalCards
        ? Math.max(singleCoverWidth * 9 / 16, cardTextHeight)
          + 2 * Theme.paddingMedium
        : (gridCellWidth - 2 * Theme.paddingMedium) * 9 / 16
          + cardTextHeight + 3 * Theme.paddingMedium
    readonly property real cardTextHeight: cardMetrics.titleHeight
        + 2 * cardMetrics.metadataHeight + 2 * Theme.paddingSmall
    CardTextMetrics { id: cardMetrics }
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "live-feed"
        columns: page.contentColumns
    }

    FeedPagination {
        id: pagination
        view: listView
        feed: liveFeed
        pageActive: page.status === PageStatus.Active
        loading: liveFeed.loading
        hasMore: liveFeed.hasMore
        itemCount: listView.count
        errorMessage: liveFeed.errorMessage
    }

    SilicaGridView {
        id: listView
        anchors.fill: parent
        cacheBuffer: height
        model: liveFeed
        cellWidth: page.gridCellWidth
        cellHeight: page.gridCellHeight
        clip: true



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

                AppLabel {
                    width: parent.width
                    text: title
                    color: delegateRoot.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    text: owner
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
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
                onClicked: liveFeed.errorMessage.length > 0
                           ? liveFeed.refresh() : liveFeed.loadMore()
            }
            AppLabel {
                anchors.centerIn: parent
                visible: !liveFeed.loading && !liveFeed.hasMore && listView.count > 0
                text: qsTr("已加载全部直播")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            }
        }

        VerticalScrollDecorator {}
        ViewPlaceholder {
            enabled: listView.count === 0 && liveFeed.errorMessage.length > 0
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
