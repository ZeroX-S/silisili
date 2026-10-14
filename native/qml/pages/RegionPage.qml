import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components/ImageUrls.js" as ImageUrls
import "../components"

Page {
    id: page

    property int regionId: 1
    property string regionTitle: qsTr("动画排行")

    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "region"
        columns: 1
    }

    function selectRegion(id, title) {
        if (regionId === id && regionTitle === title)
            return
        regionId = id
        regionTitle = title
        list.positionViewAtBeginning()
        regionFeed.load(regionId, regionTitle)
    }

    Component.onCompleted: regionFeed.load(regionId, regionTitle)

    SilicaListView {
        id: list
        anchors.fill: parent
        model: regionFeed
        spacing: Theme.paddingSmall

        PullDownMenu {
            MenuItem {
                text: qsTr("刷新")
                onClicked: regionFeed.load(regionId, regionTitle)
            }
        }

        header: Column {
            width: list.width

            PageHeader {
                title: qsTr("分区排行榜")
                description: regionTitle
            }

            ComboBox {
                width: parent.width
                label: qsTr("当前分区")
                value: regionTitle
                menu: ContextMenu {
                    MenuItem { text: qsTr("动画排行"); onClicked: selectRegion(1, text) }
                    MenuItem { text: qsTr("音乐排行"); onClicked: selectRegion(3, text) }
                    MenuItem { text: qsTr("游戏排行"); onClicked: selectRegion(4, text) }
                    MenuItem { text: qsTr("知识排行"); onClicked: selectRegion(36, text) }
                    MenuItem { text: qsTr("影视排行"); onClicked: selectRegion(181, text) }
                }
            }
        }

        delegate: BackgroundItem {
            id: regionItem
            width: list.width
            height: Math.max(coverImage.height, labels.implicitHeight) + 2 * Theme.paddingMedium
            onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoBvid: bvid,
                videoTitle: title,
                videoOwner: owner,
                videoCover: cover
            })

            Image {
                id: coverImage
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.36, Theme.itemSizeHuge * 2.2)
                height: width * 9 / 16
                sourceSize.width: Math.max(1, width)
                sourceSize.height: Math.max(1, height)
                source: ImageUrls.thumbnail(cover, width)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Column {
                id: labels
                anchors.left: coverImage.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall

                AppLabel {
                    width: parent.width
                    text: title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                    color: regionItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                AppLabel {
                    width: parent.width
                    text: owner
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    text: qsTr("播放 %1 · 弹幕 %2").arg(playCount).arg(danmakuCount)
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    color: Theme.secondaryColor
                }
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: regionFeed.loading
            size: BusyIndicatorSize.Large
        }
        ViewPlaceholder {
            enabled: regionFeed.errorMessage.length > 0
            text: regionFeed.errorMessage
            hintText: qsTr("从顶部下拉重试")
        }
        VerticalScrollDecorator {}
    }
}
