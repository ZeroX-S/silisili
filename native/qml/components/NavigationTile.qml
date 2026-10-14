import QtQuick 2.2
import Sailfish.Silica 1.0

BackgroundItem {
    id: root

    property string title
    property string description
    property int titleFontSize: Theme.fontSizeSmall
    property bool selected: false

    height: Math.max(Theme.itemSizeLarge, tileContent.implicitHeight + 2 * Theme.paddingMedium)

    Column {
        id: tileContent
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingMedium
        spacing: Theme.paddingSmall / 2

        AppLabel {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            color: root.highlighted || root.selected ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: appSettings.scaledFontSize(root.titleFontSize, appSettings.fontSizeMode)
            truncationMode: TruncationMode.Fade
        }

        AppLabel {
            width: parent.width
            visible: root.description.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: root.description
            wrapMode: Text.Wrap
            maximumLineCount: 2
            color: root.highlighted || root.selected
                   ? Theme.secondaryHighlightColor : Theme.secondaryColor
            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
            truncationMode: TruncationMode.Fade
        }
    }
}
