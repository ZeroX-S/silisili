import QtQuick 2.2
import QtSensors 5.0
import Sailfish.Silica 1.0
import cn.silisili.native.player 1.0

Item {
    id: root
    width: Screen.width
    height: Screen.height

    function applySensorOrientation(rawOrientation) {
        var angle = 0
        switch (rawOrientation) {
        case 1: // OrientationReading.TopUp
            angle = 0
            break
        case 2: // OrientationReading.TopDown
            angle = 180
            break
        case 3: // OrientationReading.LeftUp
            angle = -90
            break
        case 4: // OrientationReading.RightUp
            angle = 90
            break
        default:
            return
        }
        systemPipController.setSensorOrientation(angle)
        console.log("native system PiP: sensor orientation",
                    rawOrientation, "angle", angle)
    }

    function syncInputRegion(reason) {
        systemPipController.setInputRect(dragBox.x, dragBox.y,
                                         dragBox.width, dragBox.height)
        console.log("native system PiP: overlay box synchronized",
                    reason,
                    Math.round(dragBox.x), Math.round(dragBox.y),
                    Math.round(dragBox.width), Math.round(dragBox.height),
                    "angle", systemPipController.orientationAngle)
    }

    Component.onCompleted: {
        systemPipController.setSensorOrientation(0)
        inputRegionTimer.restart()
        console.log("native system PiP: full-screen QML canvas ready",
                    Math.round(width), Math.round(height),
                    "transparentOutside", true)
    }
    onWidthChanged: inputRegionTimer.restart()
    onHeightChanged: inputRegionTimer.restart()

    OrientationSensor {
        id: orientationSensor
        active: systemPipController.visible
        onReadingChanged: {
            if (reading)
                root.applySensorOrientation(reading.orientation)
        }
    }

    Connections {
        target: systemPipController
        onOverlayGeometryChanged: {
            if (!dragArea.drag.active) {
                dragBox.x = systemPipController.overlayX
                dragBox.y = systemPipController.overlayY
            }
            inputRegionTimer.restart()
        }
        onOrientationAngleChanged: inputRegionTimer.restart()
    }

    Timer {
        id: inputRegionTimer
        interval: 0
        repeat: false
        onTriggered: root.syncInputRegion("geometry")
    }

    Item {
        id: dragBox
        x: systemPipController.overlayX
        y: systemPipController.overlayY
        width: Math.abs(systemPipController.orientationAngle) === 90
               ? systemPipController.overlayHeight
               : systemPipController.overlayWidth
        height: Math.abs(systemPipController.orientationAngle) === 90
                ? systemPipController.overlayWidth
                : systemPipController.overlayHeight

        Item {
            id: pipFrame
            anchors.centerIn: parent
            width: systemPipController.overlayWidth
            height: systemPipController.overlayHeight
            rotation: systemPipController.orientationAngle
            transformOrigin: Item.Center

            Behavior on rotation {
                SmoothedAnimation { duration: 280 }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                radius: Theme.paddingSmall
            }

            Item {
                anchors.fill: parent
                clip: true

                MpvVideoMirrorItem {
                    id: mirror
                    anchors.fill: parent
                    source: playbackVideo
                    usage: "pip"
                    preserveAspectRatio: true
                }

                Image {
                    anchors.fill: parent
                    visible: playbackSession.loading
                             && playbackSession.cover.length > 0
                    source: playbackSession.cover
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.paddingSmall
                color: "transparent"
                border.width: 1
                border.color: Theme.highlightColor
                opacity: Theme.opacityHigh
                z: 4
            }

        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            z: 8
            drag.target: dragBox
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 0
            drag.maximumX: Math.max(0, root.width - dragBox.width)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, root.height - dragBox.height)
            preventStealing: true

            onPressed: console.log("native system PiP: pointer press",
                                   Math.round(mouse.x), Math.round(mouse.y))
            onReleased: {
                systemPipController.commitOverlayPosition(
                            dragBox.x, dragBox.y,
                            dragBox.width, dragBox.height)
                console.log("native system PiP: pointer release",
                            Math.round(dragBox.x), Math.round(dragBox.y),
                            "dragActive", drag.active)
            }
            onClicked: {
                console.log("native system PiP: tap restore handled")
                systemPipController.restoreApplication()
            }
        }

        Item {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.paddingSmall
            width: Theme.itemSizeSmall
            height: Theme.itemSizeSmall
            z: 12

            Image {
                anchors.centerIn: parent
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
                source: "image://theme/icon-m-close"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("native system PiP: close tapped")
                    playbackSession.stop()
                }
            }
        }
    }
}
