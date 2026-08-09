import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property string authorMid
    property string initialName
    property bool landscapeLayout: width > height
    allowedOrientations: Orientation.All

    AuthorSpaceModel { id: authorSpace }

    ResponsivePageMetrics {
        target: page
        pageName: "author-space"
        columns: page.landscapeLayout ? 4 : 3
    }

    Component.onCompleted: authorSpace.load(authorMid)

    function openDynamicComments(item) {
        if (!item.commentOid || item.commentOid.length === 0)
            return
        pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
            commentAid: item.commentOid,
            commentType: item.commentType,
            contentTitle: item.title && item.title.length > 0 ? item.title : item.text
        })
    }

    function openDynamic(item) {
        pageStack.push(Qt.resolvedUrl("DynamicDetailPage.qml"), {
            author: authorSpace.name || initialName,
            avatar: authorSpace.avatar,
            publishTime: item.time || "",
            kindLabel: item.kindLabel || qsTr("动态"),
            bodyText: item.text || "",
            sourceText: item.source || "",
            mediaTitle: item.title || "",
            mediaCover: item.cover || "",
            imageUrls: item.imageUrls || [],
            bvid: item.bvid || "",
            statsText: item.stats || "",
            dynamicId: item.dynamicId || "",
            commentOid: item.commentOid || "",
            commentType: item.commentType || 17
        })
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge
        clip: true

        function nearBottom() {
            return contentY + height >= contentHeight - Theme.itemSizeHuge * 3
        }

        function maybeLoadMore() {
            if (authorSpace.hasMore && !authorSpace.loading && nearBottom())
                authorSpace.loadMore()
        }

        onContentYChanged: maybeLoadMore()
        onMovementEnded: maybeLoadMore()

        Connections {
            target: authorSpace
            onChanged: if (!authorSpace.loading) spacePaginationTimer.restart()
        }

        Timer {
            id: spacePaginationTimer
            interval: 250
            repeat: false
            onTriggered: flickable.maybeLoadMore()
        }

        Timer {
            interval: 700
            repeat: true
            running: page.status === PageStatus.Active
                     && (authorSpace.videos.length > 0 || authorSpace.dynamics.length > 0)
            onTriggered: flickable.maybeLoadMore()
        }

        PullDownMenu {
            MenuItem { text: qsTr("刷新空间和动态"); onClicked: authorSpace.load(authorMid) }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: authorSpace.name.length > 0 ? authorSpace.name : (initialName || qsTr("UP 主空间"))
                description: authorMid.length > 0 ? qsTr("UP 主空间与动态") : qsTr("UP 主空间")
            }

            Item {
                width: parent.width
                height: Math.max(avatar.height, profile.implicitHeight) + 2 * Theme.paddingMedium

                Rectangle {
                    id: avatarMask
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.itemSizeLarge
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                    clip: true
                    AvatarImage {
                        id: avatar
                        anchors.fill: parent
                        source: authorSpace.avatar
                        debugContext: "author-space"
                    }
                }
                Column {
                    id: profile
                    anchors.left: avatarMask.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: avatarMask.verticalCenter
                    spacing: Theme.paddingSmall
                    Label {
                        width: parent.width
                        text: authorSpace.name || initialName
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        visible: authorSpace.signature.length > 0
                        text: authorSpace.signature
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: authorSpace.errorMessage.length > 0
                text: authorSpace.errorMessage
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("最新作品") }
            Repeater {
                model: authorSpace.videos
                BackgroundItem {
                    width: content.width
                    height: Math.max(poster.height, videoLabels.implicitHeight) + 2 * Theme.paddingMedium
                    onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                        videoBvid: modelData.bvid,
                        videoTitle: modelData.title,
                        videoOwner: authorSpace.name || initialName,
                        videoCover: modelData.cover
                    })
                    Image {
                        id: poster
                        x: Theme.horizontalPageMargin
                        y: Theme.paddingMedium
                        width: Math.min(parent.width * 0.36, Theme.itemSizeHuge * 1.6)
                        height: width * 9 / 16
                        source: modelData.cover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                    }
                    Column {
                        id: videoLabels
                        anchors.left: poster.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: poster.verticalCenter
                        spacing: Theme.paddingSmall
                        Label {
                            width: parent.width
                            text: modelData.title
                            color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: modelData.stats + (modelData.duration.length > 0 ? " · " + modelData.duration : "")
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !authorSpace.loading && authorSpace.videos.length === 0
                text: qsTr("暂未取得公开作品")
                color: Theme.secondaryColor
            }

            SectionHeader { text: qsTr("最新动态") }
            Repeater {
                model: authorSpace.dynamics
                BackgroundItem {
                    id: dynamicCard
                    width: content.width
                    height: dynamicContent.implicitHeight + 2 * Theme.paddingMedium
                    property var pictures: modelData.imageUrls || []
                    property bool canComment: (modelData.commentOid || "").length > 0
                    onClicked: page.openDynamic(modelData)

                    function openComments() {
                        if (canComment)
                            page.openDynamicComments(modelData)
                    }
                    Column {
                        id: dynamicContent
                        x: Theme.horizontalPageMargin
                        y: Theme.paddingMedium
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingSmall
                        Label {
                            width: parent.width
                            visible: modelData.time.length > 0
                            text: modelData.time
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                        Label {
                            width: parent.width
                            text: modelData.text
                            color: Theme.primaryColor
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            visible: (modelData.source || "").length > 0
                            text: modelData.source || ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 5
                            truncationMode: TruncationMode.Fade
                        }
                        Grid {
                            id: dynamicPictures
                            width: parent.width
                            visible: dynamicCard.pictures.length > 0
                            columns: Math.min(page.landscapeLayout ? 4 : 3,
                                              Math.max(1, dynamicCard.pictures.length))
                            spacing: Theme.paddingSmall
                            property real cellWidth: (width - (columns - 1) * spacing) / columns
                            height: visible
                                    ? Math.ceil(dynamicCard.pictures.length / columns) * (cellWidth + spacing) - spacing
                                    : 0
                            Repeater {
                                model: dynamicCard.pictures
                                Image {
                                    width: dynamicPictures.cellWidth
                                    height: width
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: width
                                    sourceSize.height: height
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: visible ? Math.max(dynamicCover.height, dynamicTitle.implicitHeight) + 2 * Theme.paddingSmall : 0
                            visible: (modelData.title || "").length > 0
                            color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityFaint)
                            Image {
                                id: dynamicCover
                                x: Theme.paddingSmall
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? Math.min(parent.width * 0.30, Theme.itemSizeLarge * 1.6) : 0
                                height: width * 9 / 16
                                visible: (modelData.cover || "").length > 0
                                source: modelData.cover || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Label {
                                id: dynamicTitle
                                anchors.left: dynamicCover.visible ? dynamicCover.right : parent.left
                                anchors.leftMargin: Theme.paddingSmall
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.paddingSmall
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title || ""
                                color: Theme.secondaryHighlightColor
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                truncationMode: TruncationMode.Fade
                            }
                        }
                        Label {
                            width: parent.width
                            visible: (modelData.stats || "").length > 0
                            text: modelData.stats || ""
                            horizontalAlignment: Text.AlignRight
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: dynamicCard.canComment
                            text: qsTr("查看动态评论")
                            onClicked: dynamicCard.openComments()
                        }
                    }

                    ContextMenu {
                        MenuItem {
                            text: qsTr("查看动态视频")
                            visible: (modelData.bvid || "").length > 0
                            enabled: visible
                            onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                                videoBvid: modelData.bvid,
                                videoTitle: modelData.title,
                                videoOwner: authorSpace.name || initialName,
                                videoCover: modelData.cover
                            })
                        }
                        MenuItem {
                            text: qsTr("查看动态评论")
                            enabled: dynamicCard.canComment
                            onClicked: dynamicCard.openComments()
                        }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !authorSpace.loading && authorSpace.dynamics.length === 0
                text: qsTr("暂未取得公开动态")
                color: Theme.secondaryColor
            }

            Item {
                width: parent.width
                height: authorSpace.loading || authorSpace.hasMore
                        ? Theme.itemSizeHuge : Theme.itemSizeLarge
                BusyIndicator {
                    anchors.centerIn: parent
                    running: authorSpace.loading
                            && (authorSpace.videos.length > 0 || authorSpace.dynamics.length > 0)
                    size: BusyIndicatorSize.Medium
                }
                Button {
                    anchors.centerIn: parent
                    visible: authorSpace.hasMore && !authorSpace.loading
                    text: qsTr("加载更多空间内容")
                    onClicked: authorSpace.loadMore()
                }
                Label {
                    anchors.centerIn: parent
                    visible: !authorSpace.loading && !authorSpace.hasMore
                             && (authorSpace.videos.length > 0 || authorSpace.dynamics.length > 0)
                    text: qsTr("空间内容已全部加载")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }
        BusyIndicator {
            anchors.centerIn: parent
            running: authorSpace.loading
            size: BusyIndicatorSize.Large
        }
        VerticalScrollDecorator {}
    }
}
