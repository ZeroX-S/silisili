import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    id: page
    property string messageAuthor
    property string messageAvatar
    property string messageCategory
    property string messageTime
    property string messageText
    property string messageSubject
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("消息详情"); description: messageCategory }

            Item {
                width: parent.width
                height: Math.max(avatarMask.height, authorColumn.height) + 2 * Theme.paddingMedium
                Rectangle {
                    id: avatarMask
                    x: Theme.horizontalPageMargin
                    y: Theme.paddingMedium
                    width: Theme.iconSizeLarge
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: messageAvatar
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Column {
                    id: authorColumn
                    anchors.left: avatarMask.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: avatarMask.verticalCenter
                    Label { width: parent.width; text: messageAuthor; color: Theme.highlightColor }
                    Label {
                        width: parent.width
                        text: messageTime
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            SectionHeader { text: messageCategory }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: messageText
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
            }

            SectionHeader { visible: messageSubject.length > 0; text: qsTr("原内容") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: messageSubject.length > 0
                text: messageSubject
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
        VerticalScrollDecorator {}
    }
}
