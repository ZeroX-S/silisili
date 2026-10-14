import QtQuick 2.2
import Sailfish.Silica 1.0

Item {
    id: root
    property var controller
    property var systemController
    // Sailfish PageStack's interactive back gesture starts inside the page,
    // while a swipe from the physical edge minimizes the application. Keep
    // the verified native navigation corridor; playback gestures cover the
    // remaining surface in every player mode.
    property real backSwipeCorridorWidth: Math.max(Theme.paddingLarge,
                                                   Math.min(Theme.itemSizeSmall, width * 0.08))
    property int gestureMode: 0
    property bool wasGesture: false
    property real startX: 0
    property real startY: 0
    property real startPosition: 0
    property real startVolume: 100
    property real startBrightness: 0
    property real previewValue: 0
    property string previewText: ""
    property bool seekEnabled: true
    property bool systemControlGesturesEnabled: true
    property bool pressSpeedEnabled: false
    property real pressSpeed: 2.0
    property int pressSpeedDelay: 520
    property bool pressSpeedActive: false
    signal tapped()
    signal interaction()
    signal gestureStarted()

    function canPressSpeed() {
        return pressSpeedEnabled && controller && controller.playing
    }

    function startPressSpeed() {
        if (!canPressSpeed() || gestureMode !== 0)
            return
        pressSpeedActive = true
        wasGesture = true
        gestureMode = 5
        previewValue = pressSpeed
        previewText = qsTr("倍速 %1x").arg(Number(pressSpeed).toFixed(1))
        controller.setSpeed(pressSpeed)
        gestureStarted()
        console.log("native gesture: speed hold", Number(pressSpeed).toFixed(1))
    }

    function stopPressSpeed() {
        pressSpeedTimer.stop()
        if (!pressSpeedActive)
            return
        pressSpeedActive = false
        if (controller)
            controller.setSpeed(1.0)
        console.log("native gesture: speed restored")
    }

    Timer {
        id: pressSpeedTimer
        interval: root.pressSpeedDelay
        repeat: false
        onTriggered: root.startPressSpeed()
    }

    MouseArea {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        // Keep the native PageStack back-swipe corridor. Brightness uses the
        // left half of the remaining playback gesture surface.
        anchors.leftMargin: root.backSwipeCorridorWidth
        preventStealing: root.seekEnabled
        onPressed: {
            root.startX = mouse.x + root.backSwipeCorridorWidth
            root.startY = mouse.y
            root.startPosition = root.controller ? root.controller.position : 0
            root.startVolume = root.systemController
                               ? root.systemController.volumePercent : 100
            root.startBrightness = root.systemController
                                   ? root.systemController.brightnessPercent : 50
            root.gestureMode = 0
            root.wasGesture = false
            if (root.canPressSpeed())
                pressSpeedTimer.restart()
            else
                pressSpeedTimer.stop()
        }
        onPositionChanged: {
            if (!pressed || !root.controller)
                return
            if (root.pressSpeedActive)
                return
            var dx = mouse.x + root.backSwipeCorridorWidth - root.startX
            var dy = mouse.y - root.startY
            if (root.gestureMode === 0 && Math.max(Math.abs(dx), Math.abs(dy)) > Theme.paddingLarge) {
                pressSpeedTimer.stop()
                if (Math.abs(dx) > Math.abs(dy)) {
                    root.gestureMode = root.seekEnabled && root.controller.duration > 0 ? 1 : 4
                } else {
                    root.gestureMode = root.systemControlGesturesEnabled
                                     ? (root.startX < root.width / 2 ? 2 : 3) : 4
                }
                root.wasGesture = true
                root.gestureStarted()
            }
            if (root.gestureMode === 1) {
                var duration = Math.max(0, root.controller.duration)
                root.previewValue = Math.max(0, Math.min(duration,
                    root.startPosition + dx / width * Math.max(60, duration * 0.35)))
                root.previewText = qsTr("进度 %1 / %2").arg(formatTime(root.previewValue)).arg(formatTime(duration))
            } else if (root.gestureMode === 2) {
                root.previewValue = Math.max(1, Math.min(100,
                    root.startBrightness + (root.startY - mouse.y) / height * 100))
                if (root.systemController
                        && root.systemController.setBrightnessPercent(root.previewValue)) {
                    root.previewText = qsTr("系统亮度 %1%").arg(Math.round(root.previewValue))
                } else {
                    root.previewText = qsTr("系统亮度不可用")
                }
            } else if (root.gestureMode === 3) {
                root.previewValue = Math.max(0, Math.min(100,
                    root.startVolume + (root.startY - mouse.y) / height * 100))
                if (root.systemController
                        && root.systemController.setVolumePercent(root.previewValue)) {
                    root.previewText = qsTr("系统音量 %1%").arg(Math.round(root.previewValue))
                } else {
                    root.previewText = qsTr("系统音量不可用")
                }
            } else if (root.gestureMode === 4) {
                root.previewText = ""
            }
        }
        onReleased: {
            var wasSpeedHold = root.pressSpeedActive
            root.stopPressSpeed()
            if (root.gestureMode === 1 && root.controller) {
                root.controller.seek(root.previewValue)
                console.log("native gesture: seek", Math.round(root.previewValue))
            } else if (root.gestureMode === 2) {
                console.log("native gesture: system brightness", Math.round(root.previewValue))
            } else if (root.gestureMode === 3) {
                console.log("native gesture: system volume", Math.round(root.previewValue))
            } else if (root.gestureMode === 4) {
                console.log("native gesture: horizontal seek disabled")
            } else if (wasSpeedHold) {
                console.log("native gesture: speed hold released")
            }
            if (root.wasGesture)
                root.interaction()
            root.gestureMode = 0
        }
        onCanceled: {
            root.stopPressSpeed()
            if (root.wasGesture)
                root.interaction()
            root.gestureMode = 0
        }
        onClicked: {
            if (!root.wasGesture)
                root.tapped()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.horizontalPageMargin, previewLabel.implicitWidth + 2 * Theme.paddingLarge)
        height: previewLabel.implicitHeight + 2 * Theme.paddingMedium
        radius: Theme.paddingSmall
        color: Theme.rgba("black", Theme.opacityHigh)
        visible: root.gestureMode !== 0 && root.previewText.length > 0

        AppLabel {
            id: previewLabel
            anchors.centerIn: parent
            text: root.previewText
            color: "white"
            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode)
        }
    }

    function formatTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0))
        var hours = Math.floor(value / 3600)
        var minutes = Math.floor((value % 3600) / 60)
        var secs = value % 60
        var result = (minutes < 10 && hours > 0 ? "0" : "") + minutes + ":" + (secs < 10 ? "0" : "") + secs
        return hours > 0 ? hours + ":" + result : result
    }
}
