import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components/ImageUrls.js" as ImageUrls
import "../components"

Page {
    id: page
    property string feedSection: "nonvideo"
    property bool landscapeLayout: width > height
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "dynamic-" + page.feedSection
        columns: page.landscapeLayout ? 4 : 3
    }

    function pageTitle() {
        return feedSection === "video" ? qsTr("视频动态") : qsTr("图文与转发")
    }

    function openComments(item) {
        if (!item.commentOid || item.commentOid.length === 0)
            return
        pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
            commentAid: item.commentOid,
            commentType: item.commentType,
            contentTitle: item.mediaTitle.length > 0 ? item.mediaTitle : item.bodyText
        })
    }

    function openMedia(item) {
        if (item.bvid.length > 0) {
            pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoBvid: item.bvid,
                videoTitle: item.mediaTitle,
                videoOwner: item.author,
                videoCover: item.mediaCover
            })
        } else if (item.seasonId.length > 0) {
            pageStack.push(Qt.resolvedUrl("PgcDetailPage.qml"), {
                seasonId: item.seasonId,
                initialTitle: item.mediaTitle,
                initialCover: item.mediaCover
            })
        } else if (item.roomId.length > 0) {
            pageStack.push(Qt.resolvedUrl("LivePlayerPage.qml"), {
                roomId: item.roomId,
                roomTitle: item.mediaTitle,
                roomOwner: item.author,
                roomCover: item.mediaCover
            })
        }
    }

    function openDetail(item) {
        pageStack.push(Qt.resolvedUrl("DynamicDetailPage.qml"), item)
    }

    Component.onCompleted: {
        dynamicFeed.setSection(feedSection)
        dynamicFeed.refresh()
        console.log("native dynamic page: ready section", feedSection)
    }

    FeedPagination {
        id: pagination
        view: list
        feed: dynamicFeed
        pageActive: page.status === PageStatus.Active
        loading: dynamicFeed.loading
        hasMore: dynamicFeed.hasMore
        itemCount: list.count
        errorMessage: dynamicFeed.errorMessage
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        cacheBuffer: height
        model: dynamicFeed
        spacing: Theme.paddingSmall
        clip: true

        PullDownMenu {
            MenuItem { text: qsTr("刷新"); onClicked: dynamicFeed.refresh() }
        }

        header: Column {
            width: list.width
            PageHeader { title: page.pageTitle(); description: accountService.userName }
            SectionHeader {
                text: feedSection === "video" ? qsTr("只显示视频") : qsTr("不含视频动态")
            }
        }

        delegate: BackgroundItem {
            id: card
            width: list.width
            height: cardContent.height + 2 * Theme.paddingLarge
            property var pictures: imageUrls || []
            property bool canOpen: bvid.length > 0 || seasonId.length > 0 || roomId.length > 0
            property bool canComment: commentOid.length > 0

            Timer {
                interval: 120
                running: index === 0
                repeat: false
                onTriggered: {
                    var point = card.mapToItem(page, 0, 0)
                    console.log("native dynamic: first card geometry",
                                "section", page.feedSection,
                                "x", Math.round(point.x), "y", Math.round(point.y),
                                "width", Math.round(card.width),
                                "height", Math.round(card.height))
                }
            }

            function openCurrent() {
                if (canOpen) page.openMedia({
                    bvid: bvid,
                    seasonId: seasonId,
                    roomId: roomId,
                    mediaTitle: mediaTitle,
                    mediaCover: mediaCover,
                    author: author
                })
            }

            function openCurrentComments() {
                if (canComment) page.openComments({
                    commentOid: commentOid,
                    commentType: commentType,
                    mediaTitle: mediaTitle,
                    bodyText: bodyText
                })
            }

            onClicked: page.openDetail({
                author: author,
                avatar: avatar,
                publishTime: publishTime,
                kindLabel: kindLabel,
                bodyText: bodyText,
                sourceText: sourceText,
                mediaTitle: mediaTitle,
                mediaCover: mediaCover,
                imageUrls: imageUrls || [],
                bvid: bvid,
                seasonId: seasonId,
                roomId: roomId,
                statsText: statsText,
                dynamicId: dynamicId,
                commentOid: commentOid,
                commentType: commentType
            })

            Column {
                id: cardContent
                x: Theme.horizontalPageMargin
                y: Theme.paddingLarge
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Math.max(avatarMask.height, authorColumn.height)

                    Rectangle {
                        id: avatarMask
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.iconSizeMedium
                        height: width
                        radius: width / 2
                        color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                        clip: true
                        AvatarImage {
                            anchors.fill: parent
                            source: avatar
                            debugContext: "dynamic"
                        }
                    }
                    Column {
                        id: authorColumn
                        anchors.left: avatarMask.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        AppLabel {
                            width: parent.width
                            text: author
                            color: card.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                            truncationMode: TruncationMode.Fade
                        }
                        AppLabel {
                            width: parent.width
                            text: publishTime + (kindLabel.length > 0 ? "  ·  " + kindLabel : "")
                            color: Theme.secondaryColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }

                AppLabel {
                    width: parent.width
                    visible: bodyText.length > 0
                    text: bodyText
                    wrapMode: Text.Wrap
                    color: Theme.primaryColor
                }

                AppLabel {
                    width: parent.width
                    visible: sourceText.length > 0
                    text: sourceText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    truncationMode: TruncationMode.Fade
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                }

                Grid {
                    id: pictureGrid
                    width: parent.width
                    visible: card.pictures.length > 0
                    columns: Math.min(page.landscapeLayout ? 4 : 3,
                                      Math.max(1, card.pictures.length))
                    spacing: Theme.paddingSmall
                    property real cellWidth: (width - (columns - 1) * spacing) / columns
                    height: visible
                            ? Math.ceil(card.pictures.length / columns) * (cellWidth + spacing) - spacing
                            : 0

                    Repeater {
                        model: card.pictures
                        Image {
                            width: pictureGrid.cellWidth
                            height: width
                            source: ImageUrls.thumbnail(modelData, width)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: width
                            sourceSize.height: height
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: visible ? Math.max(mediaImage.height, mediaColumn.height) + 2 * Theme.paddingMedium : 0
                    visible: mediaCover.length > 0 || mediaTitle.length > 0
                    color: Theme.rgba(Theme.highlightBackgroundColor,
                                      card.highlighted ? Theme.opacityLow : Theme.opacityFaint)
                    radius: Theme.paddingSmall

                    Image {
                        id: mediaImage
                        x: Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? Math.min(parent.width * 0.36, Theme.itemSizeHuge * 1.7) : 0
                        height: visible ? width * 9 / 16 : 0
                        visible: mediaCover.length > 0
                        source: ImageUrls.thumbnail(mediaCover, width)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                    }
                    Column {
                        id: mediaColumn
                        anchors.left: mediaImage.visible ? mediaImage.right : parent.left
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall
                        AppLabel {
                            width: parent.width
                            text: mediaTitle
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            truncationMode: TruncationMode.Fade
                            color: card.canOpen ? Theme.highlightColor : Theme.primaryColor
                        }
                        AppLabel {
                            width: parent.width
                            visible: card.canOpen
                            text: bvid.length > 0 ? qsTr("打开视频 ›")
                                  : seasonId.length > 0 ? qsTr("打开番剧 ›")
                                  : qsTr("进入直播间 ›")
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                        }
                    }
                }

                AppLabel {
                    width: parent.width
                    visible: statsText.length > 0
                    text: statsText
                    horizontalAlignment: Text.AlignRight
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: card.canComment
                    text: qsTr("查看评论")
                    onClicked: card.openCurrentComments()
                }
            }

            ContextMenu {
                MenuItem {
                    text: bvid.length > 0 ? qsTr("查看视频")
                          : seasonId.length > 0 ? qsTr("查看番剧")
                          : roomId.length > 0 ? qsTr("进入直播间")
                          : qsTr("此动态暂无可执行操作")
                    enabled: card.canOpen
                    onClicked: card.openCurrent()
                }
                MenuItem {
                    text: qsTr("查看动态评论")
                    enabled: card.canComment
                    onClicked: card.openCurrentComments()
                }
            }
        }

        footer: Item {
            width: list.width
            height: dynamicFeed.loading || dynamicFeed.hasMore
                    ? Theme.itemSizeHuge : Theme.itemSizeLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: dynamicFeed.loading && list.count > 0
                size: BusyIndicatorSize.Medium
            }
            AppLabel {
                anchors.centerIn: parent
                visible: !dynamicFeed.loading && !dynamicFeed.hasMore && list.count > 0
                text: qsTr("已加载全部动态")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: dynamicFeed.loading && list.count === 0
            size: BusyIndicatorSize.Large
        }
        ViewPlaceholder {
            enabled: dynamicFeed.errorMessage.length > 0 && list.count === 0
            text: dynamicFeed.errorMessage
            hintText: qsTr("从顶部下拉重试")
        }
        VerticalScrollDecorator {}
    }
}
