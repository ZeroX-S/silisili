import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property string commentAid
    property int commentType: 1
    property string rootRpid
    property string rootAuthor
    property string rootAvatar
    property string rootMessage
    property string rootTime
    property string rootLike
    property bool rootLiked: false
    property real readableWidth: Math.min(width, Theme.itemSizeHuge * 9)
    property real readableStart: Math.max(Theme.horizontalPageMargin,
                                          (width - readableWidth) / 2
                                          + Theme.horizontalPageMargin)
    allowedOrientations: Orientation.All

    CommentModel { id: threadModel }

    ResponsivePageMetrics {
        target: page
        pageName: "reply-thread"
        columns: 1
        primaryExtent: page.readableWidth
    }

    Component.onCompleted: threadModel.loadThreadResource(commentAid, commentType, rootRpid)

    function openReplyEditor(parentRpid, author) {
        if (!accountService.loggedIn)
            return
        console.log("native comment action: reply editor opened",
                    "parent", parentRpid, "root", rootRpid, "author", author)
        pageStack.push(Qt.resolvedUrl("CommentDialog.qml"), {
            commentModel: threadModel,
            replyMode: true,
            parentRpid: parentRpid,
            rootRpid: rootRpid,
            replyAuthor: author
        })
    }

    Connections {
        target: threadModel
        onCommentLikeChanged: {
            if (rpid !== page.rootRpid)
                return
            page.rootLiked = liked
            page.rootLike = likeCount.toString()
        }
    }

    SilicaListView {
        id: replyList
        anchors.fill: parent
        model: threadModel
        onAtYEndChanged: {
            if (atYEnd && count > 0)
                threadModel.loadMore()
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("刷新回复")
                onClicked: threadModel.refresh()
            }
        }

        header: Column {
            width: replyList.width

            PageHeader {
                title: qsTr("评论回复")
                description: rootAuthor
            }

            Item {
                width: parent.width
                height: rootContent.height + 2 * Theme.paddingLarge

                Rectangle {
                    id: rootAvatarMask
                    x: page.readableStart
                    y: Theme.paddingLarge
                    width: Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: rootAvatar
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Column {
                    id: rootContent
                    x: rootAvatarMask.x + rootAvatarMask.width + Theme.paddingMedium
                    y: Theme.paddingLarge
                    width: parent.width - x - page.readableStart
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        text: rootAuthor
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: rootMessage
                        wrapMode: Text.Wrap
                    }
                    Label {
                        width: parent.width
                        text: qsTr("%1  ·  赞 %2").arg(rootTime).arg(rootLike)
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.paddingMedium
                        CommentActionButton {
                            iconSource: page.rootLiked
                                        ? "image://theme/icon-m-like"
                                        : "image://theme/icon-m-outline-like"
                            label: parseInt(page.rootLike) > 0
                                   ? page.rootLike : qsTr("赞")
                            active: page.rootLiked
                            enabled: accountService.loggedIn && !threadModel.actioning
                            onClicked: {
                                console.log("native comment action: root like control activated",
                                            "rpid", page.rootRpid,
                                            "currentlyLiked", page.rootLiked)
                                threadModel.toggleLikeRpid(page.rootRpid,
                                                          page.rootLiked,
                                                          parseInt(page.rootLike) || 0)
                            }
                        }
                        CommentActionButton {
                            iconSource: "image://theme/icon-m-message-reply"
                            label: qsTr("回复")
                            enabled: accountService.loggedIn && !threadModel.posting
                            onClicked: page.openReplyEditor(page.rootRpid,
                                                            page.rootAuthor)
                        }
                    }
                }
            }

            SectionHeader {
                text: threadModel.totalCount > 0
                      ? qsTr("全部回复 · %1 条").arg(threadModel.totalCount)
                      : qsTr("全部回复")
            }
        }

        delegate: BackgroundItem {
            id: replyItem
            width: replyList.width
            height: Math.max(replyAvatar.height, replyContent.height) + 2 * Theme.paddingLarge

            Rectangle {
                id: replyAvatarMask
                x: page.readableStart
                y: Theme.paddingLarge
                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                clip: true

                Image {
                    id: replyAvatar
                    anchors.fill: parent
                    source: avatar
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                id: replyContent
                x: replyAvatarMask.x + replyAvatarMask.width + Theme.paddingMedium
                y: Theme.paddingLarge
                width: parent.width - x - page.readableStart
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    text: author
                    color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: messageText
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    text: qsTr("%1  ·  赞 %2").arg(commentTime).arg(likeCount)
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium
                    CommentActionButton {
                        iconSource: liked ? "image://theme/icon-m-like"
                                          : "image://theme/icon-m-outline-like"
                        label: likeCount > 0 ? likeCount.toString() : qsTr("赞")
                        active: liked
                        enabled: accountService.loggedIn && !threadModel.actioning
                        onClicked: {
                            console.log("native comment action: reply like control activated",
                                        "row", index, "rpid", rpid,
                                        "currentlyLiked", liked)
                            threadModel.toggleLike(index)
                        }
                    }
                    CommentActionButton {
                        iconSource: "image://theme/icon-m-message-reply"
                        label: qsTr("回复")
                        enabled: accountService.loggedIn && !threadModel.posting
                        onClicked: page.openReplyEditor(rpid, author)
                    }
                }
            }

            ContextMenu {
                MenuItem {
                    text: liked ? qsTr("取消点赞") : qsTr("点赞")
                    enabled: accountService.loggedIn && !threadModel.actioning
                    onClicked: threadModel.toggleLike(index)
                }
                MenuItem {
                    text: qsTr("回复 @%1").arg(author)
                    enabled: accountService.loggedIn && !threadModel.posting
                    onClicked: page.openReplyEditor(rpid, author)
                }
            }
        }

        footer: Item {
            width: replyList.width
            height: Theme.itemSizeLarge

            Button {
                anchors.centerIn: parent
                visible: threadModel.hasMore && !threadModel.loading
                text: qsTr("加载更多回复")
                onClicked: threadModel.loadMore()
            }

            Label {
                anchors.centerIn: parent
                visible: !threadModel.loading && !threadModel.hasMore && replyList.count > 0
                text: qsTr("回复已全部加载")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: threadModel.loading || threadModel.posting || threadModel.actioning
            size: BusyIndicatorSize.Large
        }
        ViewPlaceholder {
            enabled: !threadModel.loading && replyList.count === 0
            text: threadModel.errorMessage.length > 0 ? threadModel.errorMessage : qsTr("暂无回复")
            hintText: qsTr("从顶部下拉可重试")
        }
        VerticalScrollDecorator {}
    }
}
