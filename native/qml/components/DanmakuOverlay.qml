import QtQuick 2.2
import Sailfish.Silica 1.0

Item {
    id: root
    property bool active: true
    property int nextSerial: 1
    property real lastPosition: -1
    property real laneHeight: Theme.fontSizeLarge + 2 * Theme.paddingSmall
    property int laneCount: Math.max(4, Math.floor(Math.max(0, height - 2 * Theme.paddingSmall) / laneHeight))
    property int fixedLaneCount: Math.max(1, Math.floor(laneCount * 0.16))
    property int scrollingFirstLane: fixedLaneCount
    property int scrollingLaneCount: Math.max(1, laneCount - 2 * fixedLaneCount)
    property int nextScrollingLane: 0
    property int nextTopLane: 0
    property int nextBottomLane: 0
    property var scrollingLanes: []
    property var topLanes: []
    property var bottomLanes: []

    clip: true
    visible: active && danmakuModel.enabled

    function clearLaneState() {
        scrollingLanes = []
        topLanes = []
        bottomLanes = []
        nextScrollingLane = 0
        nextTopLane = 0
        nextBottomLane = 0
    }

    function resetTimeline() {
        bullets.clear()
        clearLaneState()
        lastPosition = playbackSession.position
        danmakuModel.seek(lastPosition)
    }

    function bulletFontSize(size) {
        return Math.min(Theme.fontSizeLarge,
                        Math.max(Theme.fontSizeExtraSmall,
                                 Theme.fontSizeSmall * danmakuModel.fontScale
                                 * Math.max(0.75, size / 25.0)))
    }

    function estimatedTextWidth(message, pixelSize) {
        // A lightweight approximation keeps this component compatible with
        // QtQuick 2.2, where TextMetrics is not consistently available.
        var units = 0
        for (var index = 0; index < message.length; ++index)
            units += message.charCodeAt(index) < 256 ? 0.58 : 1.0
        return Math.max(pixelSize * 2, units * pixelSize)
    }

    function fixedLane(lanes, count, startLane, position, duration) {
        for (var offset = 0; offset < count; ++offset) {
            var lane = (startLane + offset) % count
            if (lanes[lane] === undefined || position >= lanes[lane]) {
                lanes[lane] = position + duration
                return lane
            }
        }
        return -1
    }

    function scrollingLane(item, position) {
        if (width <= 0 || scrollingLaneCount <= 0)
            return -1

        var speed = Math.max(0.1, danmakuModel.speed)
        var duration = 8.0 / speed
        var textWidth = estimatedTextWidth(item.text, bulletFontSize(item.size))
        var velocity = (width + textWidth) / duration
        var gap = Theme.paddingLarge

        for (var offset = 0; offset < scrollingLaneCount; ++offset) {
            var lane = (nextScrollingLane + offset) % scrollingLaneCount
            var previous = scrollingLanes[lane]
            var available = previous === undefined

            if (!available) {
                var elapsed = position - previous.startPosition
                if (elapsed >= previous.duration) {
                    available = true
                } else if (elapsed >= 0) {
                    var previousX = width - previous.velocity * elapsed
                    var currentGap = width - (previousX + previous.textWidth)
                    var remaining = previous.duration - elapsed
                    var catchUp = Math.max(0, velocity - previous.velocity) * remaining
                    available = currentGap >= gap + catchUp
                }
            }

            if (available) {
                scrollingLanes[lane] = {
                    startPosition: position,
                    duration: duration,
                    textWidth: textWidth,
                    velocity: velocity
                }
                nextScrollingLane = (lane + 1) % scrollingLaneCount
                return scrollingFirstLane + lane
            }
        }
        return -1
    }

    function assignLane(item, position) {
        var holdDuration = 4.5 / Math.max(0.1, danmakuModel.speed)
        var lane = -1
        if (item.mode === 5) {
            lane = fixedLane(topLanes, fixedLaneCount, nextTopLane, position, holdDuration)
            if (lane >= 0)
                nextTopLane = (lane + 1) % fixedLaneCount
        } else if (item.mode === 4) {
            lane = fixedLane(bottomLanes, fixedLaneCount, nextBottomLane, position, holdDuration)
            if (lane >= 0)
                nextBottomLane = (lane + 1) % fixedLaneCount
        } else {
            lane = scrollingLane(item, position)
        }
        return lane
    }

    function removeSerial(serial) {
        for (var index = 0; index < bullets.count; ++index) {
            if (bullets.get(index).serial === serial) {
                bullets.remove(index)
                return
            }
        }
    }

    onActiveChanged: {
        if (active) resetTimeline()
        else {
            bullets.clear()
            clearLaneState()
        }
    }
    onWidthChanged: geometryResetTimer.restart()
    onHeightChanged: geometryResetTimer.restart()

    Timer {
        id: geometryResetTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.active)
                root.resetTimeline()
            else
                root.clearLaneState()
        }
    }

    ListModel { id: bullets }

    Timer {
        interval: 160
        repeat: true
        running: root.active && danmakuModel.enabled
        onTriggered: {
            var position = playbackSession.position
            if (root.lastPosition < 0 || position + 0.5 < root.lastPosition || position - root.lastPosition > 2.5)
                root.resetTimeline()
            var due = danmakuModel.takeUntil(position, 20)
            var accepted = 0
            var maximumAccepted = Math.min(8, root.laneCount)
            for (var index = 0; index < due.length && accepted < maximumAccepted; ++index) {
                var item = due[index]
                var lane = root.assignLane(item, position)
                if (lane < 0)
                    continue
                bullets.append({
                    serial: root.nextSerial++,
                    message: item.text,
                    bulletMode: item.mode,
                    bulletSize: item.size,
                    bulletColor: item.color,
                    lane: lane
                })
                ++accepted
            }
            root.lastPosition = position
        }
    }

    Repeater {
        model: bullets
        delegate: Text {
            id: bullet
            property bool scrolling: bulletMode <= 3
            x: scrolling ? root.width : Math.max(0, (root.width - width) / 2)
            y: bulletMode === 5
               ? Theme.paddingSmall + lane * root.laneHeight + (root.laneHeight - height) / 2
               : bulletMode === 4
                 ? root.height - Theme.paddingSmall - (lane + 1) * root.laneHeight
                   + (root.laneHeight - height) / 2
                 : Theme.paddingSmall + lane * root.laneHeight + (root.laneHeight - height) / 2
            text: message
            color: bulletColor
            opacity: danmakuModel.opacity
            font.pixelSize: root.bulletFontSize(bulletSize)
            style: Text.Outline
            styleColor: "black"

            function syncPaused() {
                if (playbackSession.paused) {
                    if (scrolling) scrollAnimation.pause()
                    else holdAnimation.pause()
                } else {
                    if (scrolling) scrollAnimation.resume()
                    else holdAnimation.resume()
                }
            }

            Component.onCompleted: {
                if (scrolling) scrollAnimation.start()
                else holdAnimation.start()
                syncPaused()
            }
            Connections { target: playbackSession; onChanged: bullet.syncPaused() }

            NumberAnimation {
                id: scrollAnimation
                target: bullet
                property: "x"
                from: root.width
                to: -bullet.width
                duration: Math.floor(8000 / danmakuModel.speed)
                onStopped: if (!paused) root.removeSerial(serial)
            }
            SequentialAnimation {
                id: holdAnimation
                PauseAnimation { duration: Math.floor(4500 / danmakuModel.speed) }
                ScriptAction { script: root.removeSerial(serial) }
            }
        }
    }
}
