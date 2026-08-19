import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import "../components"

Page {
    id: page
    property string videoBvid
    property string videoCid
    property string videoTitle
    property string videoCover
    property var returnSurfaceOwner
    property bool controlsVisible: true
    property int orientationMode: 0
    property bool previousPlaying: playbackSession.playing
    property string loadedDanmakuCid
    property bool portraitControls: page.height > page.width
    property bool retainedByDialog: pageStack.currentPage
                                    && pageStack.currentPage !== page
                                    && typeof pageStack.currentPage.playbackSurfaceOwner !== "undefined"
                                    && pageStack.currentPage.playbackSurfaceOwner === page
    property bool wantsPlaybackSurface: (status === PageStatus.Active || retainedByDialog)
                                        && playbackSession.active

    property int automaticOrientations: playbackSession.videoAspectRatio > 1.05
                                        ? Orientation.Landscape | Orientation.LandscapeInverted
                                        : playbackSession.videoAspectRatio > 0
                                          && playbackSession.videoAspectRatio < 0.95
                                          ? Orientation.Portrait | Orientation.PortraitInverted
                                          : Orientation.All
    property string orientationModeLabel: orientationMode === 0 ? qsTr("按视频比例")
                                          : orientationMode === 1 ? qsTr("跟随设备")
                                          : orientationMode === 2 ? qsTr("锁定竖屏")
                                                                  : qsTr("锁定横屏")

    allowedOrientations: orientationMode === 0 ? automaticOrientations
                         : orientationMode === 1 ? Orientation.All
                         : orientationMode === 2
                           ? Orientation.Portrait | Orientation.PortraitInverted
                           : Orientation.Landscape | Orientation.LandscapeInverted
    backgroundColor: "black"

    ResponsivePageMetrics {
        target: page
        pageName: "vod-player"
        columns: page.portraitControls ? 1 : 2
        primaryExtent: bottomControls.height
        secondaryExtent: topControls.height
    }

    function formatTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0))
        var hours = Math.floor(value / 3600)
        var minutes = Math.floor((value % 3600) / 60)
        var secs = value % 60
        var result = (minutes < 10 && hours > 0 ? "0" : "") + minutes + ":" + (secs < 10 ? "0" : "") + secs
        return hours > 0 ? hours + ":" + result : result
    }

    function openQualityDialog() {
        var qualityButton = portraitControls ? qualityButtonPortrait
                                             : qualityButtonLandscape
        var qualityButtonPosition = qualityButton.mapToItem(page, 0, 0)
        console.log("native player: quality control activated",
                    "portrait", portraitControls,
                    "x", Math.round(qualityButtonPosition.x),
                    "y", Math.round(qualityButtonPosition.y),
                    "width", Math.round(qualityButton.width),
                    "height", Math.round(qualityButton.height))
        qualityPanel.qualities = playbackSession.qualities
        qualityPanel.selectedQuality = playbackSession.selectedQuality
        qualityPanel.open()
        showControls()
    }

    function logQualityControlGeometry() {
        var qualityButton = portraitControls ? qualityButtonPortrait
                                             : qualityButtonLandscape
        if (!qualityButton.visible)
            return
        var point = qualityButton.mapToItem(page, 0, 0)
        console.log("native player: quality control geometry",
                    "portrait", portraitControls,
                    "pageWidth", Math.round(page.width),
                    "pageHeight", Math.round(page.height),
                    "x", Math.round(point.x),
                    "y", Math.round(point.y),
                    "width", Math.round(qualityButton.width),
                    "height", Math.round(qualityButton.height))
    }

    function claimPlayer() {
        if (wantsPlaybackSurface) {
            playbackSession.claimSurface(videoHost)
            fullResolutionTimer.restart()
        } else {
            fullResolutionTimer.stop()
            playbackSession.setSurfaceHighResolution(videoHost, false)
            playbackSession.releaseSurface(videoHost)
        }
    }

    function leaveFullscreen() {
        if (returnSurfaceOwner)
            playbackSession.beginSurfaceTransition(videoHost)
        pageStack.pop()
    }

    function openDanmakuSettings() {
        pageStack.push(Qt.resolvedUrl("DanmakuSettingsDialog.qml"), {
            allowedOrientations: page.allowedOrientations,
            playbackSurfaceOwner: page
        })
    }

    function showControls() {
        controlsVisible = true
        if (playbackSession.playing)
            hideTimer.restart()
        else
            hideTimer.stop()
    }

    function toggleControls() {
        if (!playbackSession.playing) {
            controlsVisible = true
            hideTimer.stop()
        } else if (controlsVisible) {
            controlsVisible = false
            hideTimer.stop()
        } else {
            showControls()
        }
    }

    function cycleOrientationMode() {
        orientationMode = (orientationMode + 1) % 4
        orientationToast.visible = true
        orientationToastTimer.restart()
        showControls()
        console.log("native player: orientation mode", orientationModeLabel,
                    "video", playbackSession.videoWidth, playbackSession.videoHeight)
    }

    function synchronizeDanmaku() {
        var cid = playbackSession.cid.length > 0
                  ? playbackSession.cid : videoCid
        if (cid.length === 0 || cid === loadedDanmakuCid)
            return
        loadedDanmakuCid = cid
        danmakuModel.load(cid)
        console.log("native multipart: fullscreen danmaku synchronized", cid)
    }

    Component.onCompleted: {
        // Claim the full-screen host while the page is being constructed,
        // before the outgoing detail page can release its host to compact mode.
        // This is a same-texture handoff and does not reload or seek mpv.
        if (playbackSession.active)
            playbackSession.claimSurface(videoHost)
        if (videoBvid.length > 0 && videoCid.length > 0) {
            playbackSession.claimSurface(videoHost)
            playbackSession.playVideo(videoBvid, videoCid, videoTitle, videoCover, 80)
        }
        synchronizeDanmaku()
        previousPlaying = playbackSession.playing
        showControls()
        fullResolutionTimer.restart()
        qualityControlGeometryTimer.restart()
    }
    Component.onDestruction: {
        fullResolutionTimer.stop()
        playbackSession.setSurfaceHighResolution(videoHost, false)
        playbackSession.releaseSurface(videoHost)
    }
    onWantsPlaybackSurfaceChanged: claimPlayer()
    onWidthChanged: {
        if (wantsPlaybackSurface)
            fullResolutionTimer.restart()
    }
    onHeightChanged: {
        if (wantsPlaybackSurface)
            fullResolutionTimer.restart()
        qualityControlGeometryTimer.restart()
    }
    onControlsVisibleChanged: if (controlsVisible) qualityControlGeometryTimer.restart()

    Connections {
        target: Qt.application
        onStateChanged: page.claimPlayer()
    }

    Connections {
        target: playbackSession
        onChanged: {
            synchronizeDanmaku()
            if (playbackSession.paused || playbackSession.ended) {
                controlsVisible = true
                hideTimer.stop()
            } else if (playbackSession.playing && !previousPlaying) {
                showControls()
            } else if (!playbackSession.playing) {
                hideTimer.stop()
            }
            previousPlaying = playbackSession.playing
        }
    }

    DisplayBlanking {
        preventBlanking: Qt.application.active && page.status === PageStatus.Active
                         && playbackSession.playing
    }

    Rectangle { anchors.fill: parent; z: -20; color: "black" }
    Image {
        anchors.fill: parent
        z: -10
        visible: playbackSession.loading
        source: playbackSession.cover
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        onVisibleChanged: console.log("native player: loading cover",
                                      visible ? "visible" : "hidden")
    }
    Item {
        id: videoHost
        anchors.centerIn: parent
        z: 0
        property real sourceAspect: playbackSession.videoAspectRatio > 0
                                    ? playbackSession.videoAspectRatio : 16 / 9
        property bool fitByWidth: parent.width / parent.height <= sourceAspect
        width: fitByWidth ? parent.width : parent.height * sourceAspect
        height: fitByWidth ? parent.width / sourceAspect : parent.height
    }
    DanmakuOverlay {
        anchors.fill: parent
        anchors.topMargin: controlsVisible ? topControls.height : Theme.paddingSmall
        anchors.bottomMargin: controlsVisible ? bottomControls.height : Theme.paddingSmall
        z: 10
        active: page.status === PageStatus.Active
    }

    PlayerGestureArea {
        id: playerGestures
        anchors.fill: parent
        z: 20
        controller: playbackSession
        pressSpeedEnabled: playbackSession.playing
        onTapped: toggleControls()
        onGestureStarted: {
            if (playbackSession.playing)
                controlsVisible = false
            hideTimer.stop()
        }
        onInteraction: hideTimer.stop()
    }

    SwipeBackArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: playerGestures.backSwipeCorridorWidth
        z: 25
        onSwiped: leaveFullscreen()
    }

    Rectangle {
        id: topControls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.itemSizeLarge
        visible: controlsVisible
        z: 30
        color: Theme.rgba("black", Theme.opacityHigh)

        IconButton {
            id: backButton
            anchors.left: parent.left
            anchors.leftMargin: Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            icon.source: "image://theme/icon-m-back"
            onClicked: leaveFullscreen()
        }
        Label {
            anchors.left: backButton.right
            anchors.leftMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            text: playbackSession.title || videoTitle
            color: "white"
            truncationMode: TruncationMode.Fade
        }
    }

    IconButton {
        anchors.centerIn: parent
        visible: controlsVisible && playbackSession.errorMessage.length === 0
        z: 30
        icon.source: playbackSession.paused || playbackSession.ended
                     ? "image://theme/icon-l-play" : "image://theme/icon-l-pause"
        onClicked: {
            if (playbackSession.ended) {
                playbackSession.seek(0)
                playbackSession.setPaused(false)
            } else {
                playbackSession.togglePaused()
            }
            showControls()
        }
    }

    Rectangle {
        id: bottomControls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: controls.height + 2 * Theme.paddingMedium
        visible: controlsVisible
        z: 30
        color: Theme.rgba("black", Theme.opacityHigh)

        Column {
            id: controls
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.paddingMedium
            spacing: Theme.paddingSmall
            property real contentWidth: Math.max(Theme.itemSizeLarge,
                                                 page.width - 2 * Theme.horizontalPageMargin)
            property real halfWidth: Math.floor((contentWidth - Theme.paddingMedium) / 2)

            Slider {
                id: playerSeekSlider
                x: portraitControls ? Theme.horizontalPageMargin
                                    : playerGestures.backSwipeCorridorWidth
                width: Math.max(Theme.itemSizeLarge,
                                parent.width - 2 * (portraitControls
                                                    ? Theme.horizontalPageMargin
                                                    : playerGestures.backSwipeCorridorWidth))
                minimumValue: 0
                maximumValue: Math.max(1, playbackSession.duration)
                value: playbackSession.position
                valueText: formatTime(value) + " / " + formatTime(playbackSession.duration)
                onPressed: hideTimer.stop()
                onReleased: {
                    var nextPosition = value
                    playbackSession.seek(nextPosition)
                    value = Qt.binding(function() { return playbackSession.position })
                    showControls()
                }
                onCanceled: {
                    value = Qt.binding(function() { return playbackSession.position })
                    showControls()
                }
            }

            Row {
                visible: !portraitControls
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium
                IconButton { icon.source: "image://theme/icon-m-back"; onClicked: playbackSession.seek(playbackSession.position - 10) }
                ValueButton {
                    id: qualityButtonLandscape
                    width: Math.min(page.width * 0.30, Theme.itemSizeHuge * 3)
                    label: qsTr("清晰度")
                    value: playbackSession.selectedQualityLabel
                    onClicked: openQualityDialog()
                }
                IconButton { icon.source: "image://theme/icon-m-forward"; onClicked: playbackSession.seek(playbackSession.position + 10) }
                Button {
                    text: danmakuModel.enabled ? qsTr("弹幕开") : qsTr("弹幕关")
                    preferredWidth: Theme.buttonWidthSmall
                    onClicked: danmakuModel.enabled = !danmakuModel.enabled
                }
                Button {
                    text: qsTr("弹幕设置")
                    preferredWidth: Theme.buttonWidthSmall
                    onClicked: openDanmakuSettings()
                }
                IconButton {
                    icon.source: orientationMode === 1
                                 ? "image://theme/icon-m-rotate"
                                 : "image://theme/icon-m-orientation-lock"
                    onClicked: cycleOrientationMode()
                }
            }

            Row {
                visible: portraitControls
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                IconButton {
                    icon.source: "image://theme/icon-m-back"
                    onClicked: playbackSession.seek(playbackSession.position - 10)
                }
                IconButton {
                    icon.source: "image://theme/icon-m-forward"
                    onClicked: playbackSession.seek(playbackSession.position + 10)
                }
                IconButton {
                    icon.source: orientationMode === 1
                                 ? "image://theme/icon-m-rotate"
                                 : "image://theme/icon-m-orientation-lock"
                    onClicked: cycleOrientationMode()
                }
            }

            ValueButton {
                id: qualityButtonPortrait
                visible: portraitControls
                anchors.horizontalCenter: parent.horizontalCenter
                width: controls.contentWidth
                label: qsTr("清晰度")
                value: playbackSession.selectedQualityLabel
                onClicked: openQualityDialog()
            }

            Row {
                visible: portraitControls
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                Button {
                    preferredWidth: controls.halfWidth
                    text: danmakuModel.enabled ? qsTr("弹幕开") : qsTr("弹幕关")
                    onClicked: danmakuModel.enabled = !danmakuModel.enabled
                }
                Button {
                    preferredWidth: controls.halfWidth
                    text: qsTr("弹幕设置")
                    onClicked: openDanmakuSettings()
                }
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        z: 25
        enabled: false
        running: playbackSession.loading && playbackSession.errorMessage.length === 0
        size: BusyIndicatorSize.Large
    }
    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        z: 40
        horizontalAlignment: Text.AlignHCenter
        text: playbackSession.errorMessage
        color: Theme.highlightColor
        wrapMode: Text.Wrap
        visible: text.length > 0
    }
    Rectangle {
        id: orientationToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.itemSizeLarge + Theme.paddingLarge
        width: orientationLabel.implicitWidth + 2 * Theme.paddingLarge
        height: orientationLabel.implicitHeight + 2 * Theme.paddingMedium
        radius: Theme.paddingSmall
        color: Theme.rgba("black", Theme.opacityHigh)
        visible: false
        z: 40
        Label {
            id: orientationLabel
            anchors.centerIn: parent
            text: orientationModeLabel
            color: "white"
        }
    }
    QualityPickerPanel {
        id: qualityPanel
        title: qsTr("清晰度")
        onQualitySelected: {
            playbackSession.requestQuality(quality)
            showControls()
        }
    }
    Timer { id: orientationToastTimer; interval: 1800; onTriggered: orientationToast.visible = false }
    Timer {
        id: fullResolutionTimer
        interval: 350
        onTriggered: {
            if (!wantsPlaybackSurface)
                return
            playbackSession.setSurfaceHighResolution(videoHost, true)
            console.log("native player: fullscreen native-resolution promotion requested",
                        "host", Math.round(videoHost.width), Math.round(videoHost.height),
                        "source", playbackSession.videoWidth, playbackSession.videoHeight)
        }
    }
    Timer {
        id: qualityControlGeometryTimer
        interval: 120
        repeat: false
        onTriggered: page.logQualityControlGeometry()
    }
    Timer {
        id: hideTimer
        interval: 3200
        onTriggered: {
            if (playbackSession.playing)
                controlsVisible = false
        }
    }
}
