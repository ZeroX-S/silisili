import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    Component.onCompleted: inboxModel.refresh()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: inboxModel
        clip: true

        onContentYChanged: {
            if (inboxModel.hasMore && !inboxModel.loading
                    && contentY + height >= contentHeight - Theme.itemSizeHuge * 2)
                inboxModel.loadMore()
        }

        PullDownMenu {
            MenuItem { text: qsTr("刷新"); onClicked: inboxModel.refresh() }
        }

        header: Column {
            width: list.width
            PageHeader { title: qsTr("消息"); description: accountService.userName }
            ComboBox {
                width: parent.width
                label: qsTr("消息分类")
                value: inboxModel.feedTitle
                menu: ContextMenu {
                    MenuItem { text: qsTr("回复我的"); onClicked: inboxModel.showReplies() }
                    MenuItem { text: qsTr("@ 我的"); onClicked: inboxModel.showMentions() }
                    MenuItem { text: qsTr("收到的赞"); onClicked: inboxModel.showLikes() }
                }
            }
            SectionHeader { text: inboxModel.feedTitle }
        }

        delegate: BackgroundItem {
            id: messageItem
            width: list.width
            height: Math.max(avatarMask.height, content.height) + 2 * Theme.paddingLarge

            function openDetail() {
                pageStack.push(Qt.resolvedUrl("InboxDetailPage.qml"), {
                    messageAuthor: author,
                    messageAvatar: avatar,
                    messageCategory: categoryLabel,
                    messageTime: messageTime,
                    messageText: messageText,
                    messageSubject: subject
                })
            }

            onClicked: openDetail()

            Rectangle {
                id: avatarMask
                x: Theme.horizontalPageMargin
                y: Theme.paddingLarge
                width: Theme.iconSizeMedium
                height: width
                radius: width / 2
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                clip: true
                Image {
                    anchors.fill: parent
                    source: avatar
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: width
                    sourceSize.height: height
                }
            }
            Column {
                id: content
                anchors.left: avatarMask.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                y: Theme.paddingLarge
                spacing: Theme.paddingSmall
                Label {
                    width: parent.width
                    text: author
                    color: messageItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: categoryLabel + (messageTime.length > 0 ? "  ·  " + messageTime : "")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: messageText
                    wrapMode: Text.Wrap
                    height: Math.min(implicitHeight, Theme.fontSizeMedium * 5.6)
                    clip: true
                }
                Label {
                    width: parent.width
                    text: subject
                    visible: subject.length > 0
                    wrapMode: Text.Wrap
                    height: visible ? Math.min(implicitHeight, Theme.fontSizeSmall * 3.0) : 0
                    clip: true
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                }
            }

            ContextMenu {
                MenuItem { text: qsTr("查看消息详情"); onClicked: messageItem.openDetail() }
            }
        }

        footer: Item {
            width: list.width
            height: inboxModel.loading || inboxModel.hasMore ? Theme.itemSizeHuge : Theme.itemSizeLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: inboxModel.loading && list.count > 0
                size: BusyIndicatorSize.Medium
            }
            Label {
                anchors.centerIn: parent
                visible: !inboxModel.loading && !inboxModel.hasMore && list.count > 0
                text: qsTr("此分类已全部加载")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: inboxModel.loading && list.count === 0
            size: BusyIndicatorSize.Large
        }
        ViewPlaceholder {
            enabled: inboxModel.errorMessage.length > 0 && list.count === 0
            text: inboxModel.errorMessage
            hintText: qsTr("切换分类或从顶部下拉重试")
        }
        VerticalScrollDecorator {}
    }
}
