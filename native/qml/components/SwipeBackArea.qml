import QtQuick 2.2
import Sailfish.Silica 1.0

Item {
    id: root
    signal swiped()
    property real threshold: Theme.itemSizeMedium
    property real verticalTolerance: Theme.itemSizeHuge

    MouseArea {
        anchors.fill: parent
        preventStealing: true
        property real startX: 0
        property real startY: 0
        property bool triggered: false

        onPressed: {
            startX = mouse.x
            startY = mouse.y
            triggered = false
        }
        onPositionChanged: {
            if (triggered)
                return
            var dx = mouse.x - startX
            var dy = Math.abs(mouse.y - startY)
            if (dx > root.threshold && dy < root.verticalTolerance) {
                triggered = true
                root.swiped()
            }
        }
    }
}
