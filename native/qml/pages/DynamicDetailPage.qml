import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property string author
    property url avatar
    property string publishTime
    property string kindLabel
    property string bodyText
    property string sourceText
    property string mediaTitle
    property url mediaCover
    property var imageUrls: []
    property string bvid
    property string seasonId
    property string roomId
    property string statsText
    property string dynamicId
    property string commentOid
    property int commentType: 17
    property bool landscapeLayout: width > height
    allowedOrientations: Orientation.All

    function openMedia() {
        if (bvid.length > 0) {
            pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoBvid: bvid, videoTitle: mediaTitle,
                videoOwner: author, videoCover: mediaCover
            })
        } else if (seasonId.length > 0) {
            pageStack.push(Qt.resolvedUrl("PgcDetailPage.qml"), {
                seasonId: seasonId, initialTitle: mediaTitle,
                initialCover: mediaCover
            })
        } else if (roomId.length > 0) {
            pageStack.push(Qt.resolvedUrl("LivePlayerPage.qml"), {
                roomId: roomId, roomTitle: mediaTitle, roomOwner: author
            })
        }
    }

    function openComments() {
        if (commentOid.length === 0)
            return
        pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
            commentAid: commentOid,
            commentType: commentType,
            contentTitle: mediaTitle.length > 0 ? mediaTitle : bodyText
        })
    }

    Component.onCompleted: console.log("native dynamic detail: ready",
                                       "text", bodyText.length > 0,
                                       "pictures", imageUrls.length,
                                       "media", bvid.length > 0
                                                || seasonId.length > 0
                                                || roomId.length > 0,
                                       "comments", commentOid.length > 0)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge
        clip: true

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("动态详情")
                description: kindLabel.length > 0 ? kindLabel : publishTime
            }

            Item {
                width: parent.width
                height: Math.max(avatarFrame.height, authorColumn.implicitHeight)
                        + 2 * Theme.paddingSmall

                Rectangle {
                    id: avatarFrame
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSizeLarge
                    height: width
                    radius: width / 2
                    clip: true
                    color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                    AvatarImage {
                        anchors.fill: parent
                        source: page.avatar
                        debugContext: "dynamic-detail"
                    }
                }
                Column {
                    id: authorColumn
                    anchors.left: avatarFrame.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: avatarFrame.verticalCenter
                    Label {
                        width: parent.width
                        text: page.author
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: page.publishTime
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: bodyText.length > 0
                text: bodyText
                color: Theme.primaryColor
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: sourceText.length > 0
                text: sourceText
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Grid {
                id: pictureGrid
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: imageUrls.length > 0
                columns: Math.min(page.landscapeLayout ? 4 : 3,
                                  Math.max(1, imageUrls.length))
                spacing: Theme.paddingSmall
                property real cellWidth: (width - (columns - 1) * spacing) / columns
                height: visible
                        ? Math.ceil(imageUrls.length / columns) * (cellWidth + spacing) - spacing
                        : 0
                Repeater {
                    model: page.imageUrls
                    Image {
                        width: pictureGrid.cellWidth
                        height: width
                        source: modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                    }
                }
            }

            BackgroundItem {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: visible ? Math.max(detailCover.height, mediaLabels.implicitHeight)
                                  + 2 * Theme.paddingMedium : 0
                visible: mediaTitle.length > 0 || mediaCover.toString().length > 0
                enabled: bvid.length > 0 || seasonId.length > 0 || roomId.length > 0
                onClicked: page.openMedia()
                Image {
                    id: detailCover
                    x: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Math.min(parent.width * 0.34, Theme.itemSizeHuge * 1.8) : 0
                    height: visible ? width * 9 / 16 : 0
                    visible: mediaCover.toString().length > 0
                    source: mediaCover
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Column {
                    id: mediaLabels
                    anchors.left: detailCover.visible ? detailCover.right : parent.left
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        text: mediaTitle
                        color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        wrapMode: Text.Wrap
                    }
                    Label {
                        width: parent.width
                        visible: parent.parent.enabled
                        text: bvid.length > 0 ? qsTr("打开视频 ›")
                              : seasonId.length > 0 ? qsTr("打开番剧 ›")
                              : qsTr("进入直播间 ›")
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: statsText.length > 0
                text: statsText
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: commentOid.length > 0
                text: qsTr("查看评论")
                onClicked: page.openComments()
            }
        }
        VerticalScrollDecorator {}
    }
}
