import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property string commentAid
    property int commentType: 1
    property string contentTitle
    property var sharedCommentModel
    property var commentSource: sharedCommentModel ? sharedCommentModel : privateComments
    property bool actionRegression: false
    property real readableWidth: Math.min(width, Theme.itemSizeHuge * 9)
    property real readableStart: Math.max(Theme.horizontalPageMargin,
                                          (width - readableWidth) / 2
                                          + Theme.horizontalPageMargin)
    allowedOrientations: Orientation.All

    CommentModel { id: privateComments }

    ResponsivePageMetrics {
        target: page
        pageName: "comments"
        columns: 1
        primaryExtent: page.readableWidth
    }

    function openEditor() {
        pageStack.push(Qt.resolvedUrl("CommentDialog.qml"), { commentModel: commentSource })
    }

    function openReplyEditor(parentRpid, rootRpid, author) {
        if (!accountService.loggedIn)
            return
        console.log("native comment action: reply editor opened",
                    "parent", parentRpid, "root", rootRpid, "author", author)
        pageStack.push(Qt.resolvedUrl("CommentDialog.qml"), {
            commentModel: commentSource,
            replyMode: true,
            parentRpid: parentRpid,
            rootRpid: rootRpid,
            replyAuthor: author,
            regressionPrepareText: page.actionRegression
        })
    }

    Component.onCompleted: commentSource.loadResource(commentAid, commentType)

    SilicaListView {
        id: commentList
        anchors.fill: parent
        model: commentSource
        onAtYEndChanged: {
            if (atYEnd && count > 0)
                commentSource.loadMore()
        }
        onCountChanged: viewportCheckTimer.restart()

        Timer {
            id: viewportCheckTimer
            interval: 250
            repeat: false
            onTriggered: {
                if (commentList.count > 0 && commentList.contentHeight <= commentList.height
                        && commentSource.hasMore && !commentSource.loading)
                    commentSource.loadMore()
            }
        }

        PullDownMenu {
            MenuItem {
                text: accountService.loggedIn ? qsTr("发表评论") : qsTr("登录后可发表评论")
                enabled: accountService.loggedIn
                onClicked: openEditor()
            }
            MenuItem { text: qsTr("刷新评论"); onClicked: commentSource.refresh() }
        }

        header: Column {
            width: commentList.width
            PageHeader { title: qsTr("全部评论"); description: contentTitle }
            SectionHeader {
                text: commentSource.totalCount > 0
                      ? qsTr("%1 条（含楼中楼回复）").arg(commentSource.totalCount)
                      : qsTr("评论")
            }
            Label {
                x: page.readableStart
                width: parent.width - 2 * page.readableStart
                text: commentSource.totalCount > 0
                      ? qsTr("已显示 %1 条主评论").arg(commentList.count)
                      : qsTr("正在加载评论")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: accountService.loggedIn ? qsTr("发表评论") : qsTr("登录后发表评论")
                enabled: accountService.loggedIn && !commentSource.posting
                onClicked: openEditor()
            }
        }

        delegate: BackgroundItem {
            id: commentItem
            width: commentList.width
            height: Math.max(avatarImage.height, commentColumn.height) + 2 * Theme.paddingLarge
            property int repliesTotal: parseInt(replyCount) || 0

            function openReplies() {
                if (repliesTotal <= 0)
                    return
                pageStack.push(Qt.resolvedUrl("ReplyThreadPage.qml"), {
                    commentAid: page.commentAid,
                    commentType: page.commentType,
                    rootRpid: rpid,
                    rootAuthor: author,
                    rootAvatar: avatar,
                    rootMessage: messageText,
                    rootTime: commentTime,
                    rootLike: likeCount,
                    rootLiked: liked
                })
            }

            onClicked: openReplies()

            Rectangle {
                id: avatarMask
                x: page.readableStart
                y: Theme.paddingLarge
                width: Theme.iconSizeMedium
                height: width
                radius: width / 2
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                clip: true
                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: avatar
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            Column {
                id: commentColumn
                x: avatarMask.x + avatarMask.width + Theme.paddingMedium
                y: Theme.paddingLarge
                width: parent.width - x - page.readableStart
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    text: pinned ? qsTr("置顶 · %1").arg(author) : author
                    color: Theme.highlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: messageText
                    font.pixelSize: appSettings.scaledFontSize(
                                        Theme.fontSizeSmall,
                                        appSettings.fontSizeMode)
                    wrapMode: Text.Wrap
                }
                Label {
                    width: parent.width
                    text: qsTr("%1  ·  赞 %2  ·  回复 %3")
                          .arg(commentTime).arg(likeCount).arg(replyCount)
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                }
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium

                    CommentActionButton {
                        id: likeButton
                        iconSource: liked ? "image://theme/icon-m-like"
                                          : "image://theme/icon-m-outline-like"
                        label: likeCount > 0 ? likeCount.toString() : qsTr("赞")
                        active: liked
                        enabled: accountService.loggedIn
                                 && !commentSource.actioning
                        onClicked: {
                            console.log("native comment action: like control activated",
                                        "row", index, "rpid", rpid,
                                        "currentlyLiked", liked)
                            commentSource.toggleLike(index)
                        }
                    }
                    CommentActionButton {
                        id: replyButton
                        iconSource: "image://theme/icon-m-message-reply"
                        label: qsTr("回复")
                        enabled: accountService.loggedIn && !commentSource.posting
                        onClicked: page.openReplyEditor(rpid, rpid, author)
                    }
                }
                Timer {
                    interval: 0
                    repeat: false
                    running: page.actionRegression && index === 0
                    onTriggered: {
                        var likePoint = likeButton.mapToItem(null,
                                                             likeButton.width / 2,
                                                             likeButton.height / 2)
                        var replyPoint = replyButton.mapToItem(null,
                                                               replyButton.width / 2,
                                                               replyButton.height / 2)
                        console.log("native comment action: controls ready",
                                    "row", index, "rpid", rpid,
                                    "liked", liked, "likeCount", likeCount,
                                    "likeX", Math.round(likePoint.x),
                                    "likeY", Math.round(likePoint.y),
                                    "replyX", Math.round(replyPoint.x),
                                    "replyY", Math.round(replyPoint.y))
                    }
                }
                Label {
                    width: parent.width
                    visible: commentItem.repliesTotal > 0
                    text: qsTr("查看全部 %1 条回复 ›").arg(commentItem.repliesTotal)
                    color: Theme.highlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                }
            }
            ContextMenu {
                MenuItem {
                    text: qsTr("查看 %1 条回复").arg(commentItem.repliesTotal)
                    enabled: commentItem.repliesTotal > 0
                    onClicked: commentItem.openReplies()
                }
                MenuItem {
                    text: liked ? qsTr("取消点赞") : qsTr("点赞")
                    enabled: accountService.loggedIn && !commentSource.actioning
                    onClicked: commentSource.toggleLike(index)
                }
                MenuItem {
                    text: qsTr("回复 @%1").arg(author)
                    enabled: accountService.loggedIn && !commentSource.posting
                    onClicked: page.openReplyEditor(rpid, rpid, author)
                }
            }
        }

        footer: Item {
            width: commentList.width
            height: Theme.itemSizeLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: commentSource.loading || commentSource.posting
                size: BusyIndicatorSize.Medium
            }
            Button {
                anchors.centerIn: parent
                visible: commentSource.hasMore && !commentSource.loading
                text: qsTr("加载更多评论")
                onClicked: commentSource.loadMore()
            }
            Label {
                anchors.centerIn: parent
                visible: !commentSource.loading && !commentSource.hasMore && commentList.count > 0
                text: qsTr("主评论已全部加载；点按可查看楼中楼回复")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            }
        }

        ViewPlaceholder {
            enabled: !commentSource.loading && commentList.count === 0
            text: commentSource.errorMessage.length > 0 ? commentSource.errorMessage : qsTr("暂无评论")
            hintText: qsTr("从顶部下拉可重试")
        }
        VerticalScrollDecorator {}
    }
}
