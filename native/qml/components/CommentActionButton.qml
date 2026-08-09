import QtQuick 2.2
import Sailfish.Silica 1.0

// Compact, borderless comment action. It keeps a full Silica touch target
// while avoiding the visual weight of a standard form Button in every row.
BackgroundItem {
    id: root
    property string iconSource
    property string label
    property bool active: false

    width: actionContent.width + 2 * Theme.paddingMedium
    height: Theme.itemSizeSmall

    Row {
        id: actionContent
        anchors.centerIn: parent
        spacing: Theme.paddingSmall

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmall
            height: width
            source: root.iconSource
            color: !root.enabled ? Theme.rgba(Theme.secondaryColor,
                                               Theme.opacityLow)
                                 : root.active || root.highlighted
                                   ? Theme.highlightColor
                                   : Theme.secondaryColor
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: !root.enabled ? Theme.rgba(Theme.secondaryColor,
                                               Theme.opacityLow)
                                 : root.active || root.highlighted
                                   ? Theme.highlightColor
                                   : Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }
}
