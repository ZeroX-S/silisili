import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import "../components"

Page {
    id: page
    property bool portraitControls: height > width
    property string roomId
    property string roomTitle
    property string roomOwner
    property string roomCover
    property bool controlsVisible: true
    property bool wasPlaying: false
    property int orientationMode: 0
    property var video: playbackVideo
    property bool qualityRegression: false
    property bool qualityRegressionRequested: false
    property bool qualityRegressionComplete: false
    property bool wantsPlaybackSurface:
        status === PageStatus.Active && playbackSession.mediaKind === "live"
    property int qualityRegressionPreviousLoadSerial: 0
    property bool liveStartRequested: false
    property int actualQualityLoggedLoadSerial: 0
    property int actualQualityLoggedTextureWidth: 0
    property int actualQualityLoggedTextureHeight: 0
    property int actualQualityLoggedVideoWidth: 0
    property int actualQualityLoggedVideoHeight: 0

    property bool playerLoading: playbackSession.loading
    property string playerError: playbackSession.errorMessage
    property bool playerPlaying: playbackSession.active
                                 && playbackSession.mediaKind === "live"
                                 && playbackSession.playing
    // PlaybackSession retains the last verified aspect while the decoder
    // replaces one quality with another. Reading the raw item aspect here
    // would briefly return zero and unlock portrait orientation mid-switch.
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
        pageName: "live-player"
        columns: page.portraitControls ? 1 : 2
        primaryExtent: bottomRow.width
    }

    function requestQuality(quality) {
        playbackSession.requestQuality(quality)
    }

    function startLiveWhenRendererReady() {
        if (liveStartRequested || !video.rendererReady)
            return
        liveStartRequested = true
        console.log("native live: renderer ready before resolve")
        if (playbackSession.live && playbackSession.liveRoomId === roomId) {
            playbackSession.claimSurface(videoHost)
            fullResolutionTimer.restart()
            console.log("native compact player: live surface restored",
                        "roomId", roomId,
                        "decoderReload", false)
            return
        }
        // Let LiveResolver request the account-visible original stream. A
        // positive qn is reserved for an explicit quality-picker selection.
        playbackSession.playLive(roomId, roomTitle, roomCover, 0)
        playbackSession.claimSurface(videoHost)
        // Match PlayerPage's proven full-screen presentation path. Without
        // this promotion live remained on the 800-pixel compact/Cover texture
        // even when the decoder input was 1920x1080.
        fullResolutionTimer.restart()
    }

    function openQualityDialog() {
        qualityPanel.qualities = playbackSession.qualities
        qualityPanel.selectedQuality = playbackSession.selectedQuality
        qualityPanel.open()
        showControls()
    }

    function showControls() {
        controlsVisible = true
        if (playerPlaying)
            hideTimer.restart()
        else
            hideTimer.stop()
    }

    function toggleControls() {
        if (!playerPlaying) {
            controlsVisible = true
            hideTimer.stop()
        } else if (controlsVisible) {
            controlsVisible = false
            hideTimer.stop()
        } else {
            showControls()
        }
    }

    function synchronizeControls() {
        if ((video.paused || video.ended) && !playerLoading && playerError.length === 0) {
            controlsVisible = true
            hideTimer.stop()
        } else if (playerPlaying && !wasPlaying) {
            showControls()
        } else if (!playerPlaying) {
            hideTimer.stop()
        }
        wasPlaying = playerPlaying
    }

    function reportActualQuality() {
        if (playbackSession.mediaKind !== "live"
                || playbackSession.selectedQuality <= 0
                || playbackSession.videoWidth <= 0
                || playbackSession.videoHeight <= 0
                || playbackSession.sourceFrameRate <= 0
                || video.presentedTextureWidth <= 0
                || video.presentedTextureHeight <= 0
                || (video.loadSerial === actualQualityLoggedLoadSerial
                    && video.presentedTextureWidth === actualQualityLoggedTextureWidth
                    && video.presentedTextureHeight === actualQualityLoggedTextureHeight
                    && video.presentedVideoWidth === actualQualityLoggedVideoWidth
                    && video.presentedVideoHeight === actualQualityLoggedVideoHeight))
            return
        actualQualityLoggedLoadSerial = video.loadSerial
        actualQualityLoggedTextureWidth = video.presentedTextureWidth
        actualQualityLoggedTextureHeight = video.presentedTextureHeight
        actualQualityLoggedVideoWidth = video.presentedVideoWidth
        actualQualityLoggedVideoHeight = video.presentedVideoHeight
        var sourceShortEdge = Math.min(playbackSession.videoWidth,
                                       playbackSession.videoHeight)
        var sourceLongEdge = Math.max(playbackSession.videoWidth,
                                      playbackSession.videoHeight)
        var presentedShortEdge = Math.min(video.presentedVideoWidth,
                                          video.presentedVideoHeight)
        var presentedLongEdge = Math.max(video.presentedVideoWidth,
                                         video.presentedVideoHeight)
        var sourcePixelsPreserved = presentedShortEdge >= sourceShortEdge
                                    && presentedLongEdge >= sourceLongEdge
        console.log("native live quality: actual stream ready",
                    "qn", playbackSession.selectedQuality,
                    "label", playbackSession.selectedQualityLabel,
                    "geometry", playbackSession.videoWidth,
                    "x", playbackSession.videoHeight,
                    "sourceFps", playbackSession.sourceFrameRate,
                    "presentation", video.presentedTextureWidth,
                    "x", video.presentedTextureHeight,
                    "videoViewport", video.presentedVideoWidth,
                    "x", video.presentedVideoHeight,
                    "profile", video.fullResolutionPresentation
                               ? "fullscreen-native" : "bounded-shared",
                    "sourcePixelsPreserved", sourcePixelsPreserved,
                    "loadSerial", video.loadSerial)
    }

    function cycleOrientationMode() {
        orientationMode = (orientationMode + 1) % 4
        orientationToast.visible = true
        orientationToastTimer.restart()
        showControls()
        console.log("native live player: orientation mode", orientationModeLabel,
                    "video", video.videoWidth, video.videoHeight)
    }

    Component.onCompleted: {
        // Live playback used to create a page-local MpvVideoItem. Destroying
        // that item while Sailfish/Qt still owned its render thread could leave
        // a crashed process and a stale single-instance lock. Reuse the
        // process-lifetime mpv item and stop any VOD session before live starts.
        wasPlaying = playerPlaying
        startLiveWhenRendererReady()
    }
    Component.onDestruction: {
        // A delayed page teardown must never stop a VOD/PGC session that has
        // already replaced this live room in the shared PlaybackSession.
        fullResolutionTimer.stop()
        playbackSession.setSurfaceHighResolution(videoHost, false)
        playbackSession.releaseSurface(videoHost)
    }
    onWantsPlaybackSurfaceChanged: {
        if (wantsPlaybackSurface) {
            playbackSession.claimSurface(videoHost)
            fullResolutionTimer.restart()
        } else {
            fullResolutionTimer.stop()
            playbackSession.setSurfaceHighResolution(videoHost, false)
            playbackSession.releaseSurface(videoHost)
        }
    }
    onWidthChanged: if (playbackSession.mediaKind === "live") fullResolutionTimer.restart()
    onHeightChanged: if (playbackSession.mediaKind === "live") fullResolutionTimer.restart()

    Connections {
        target: playbackSession
        onChanged: {
            synchronizeControls()
            reportActualQuality()
        }
    }

    Connections {
        target: video
        onRendererReadyChanged: startLiveWhenRendererReady()
        onStateChanged: synchronizeControls()
        onPresentationGeometryChanged: reportActualQuality()
        onSharedTextureFrameChanged: {
            if (qualityRegressionRequested && !qualityRegressionComplete
                    && frameSerial > 0
                    && video.loadSerial > qualityRegressionPreviousLoadSerial) {
                qualityRegressionComplete = true
                console.log("native live quality: cycle ready",
                            "quality", playbackSession.selectedQuality,
                            "loadSerial", video.loadSerial,
                            "frameSerial", frameSerial)
            }
        }
    }

    DisplayBlanking {
        preventBlanking: Qt.application.active && page.status === PageStatus.Active
                         && playerPlaying
    }

    Rectangle { anchors.fill: parent; z: -20; color: "black" }
    Item { id: videoHost; anchors.fill: parent; z: 0 }

    PlayerGestureArea {
        id: liveGestures
        anchors.fill: parent
        z: 20
        controller: video
        seekEnabled: false
        onTapped: toggleControls()
        onGestureStarted: {
            if (playerPlaying)
                controlsVisible = false
            hideTimer.stop()
        }
        onInteraction: hideTimer.stop()
    }

    SwipeBackArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: liveGestures.backSwipeCorridorWidth
        z: 25
        onSwiped: pageStack.pop()
    }

    Rectangle {
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
            onClicked: pageStack.pop()
        }
        Column {
            anchors.left: backButton.right
            anchors.leftMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            Label {
                width: parent.width
                text: roomTitle
                color: "white"
                truncationMode: TruncationMode.Fade
                maximumLineCount: 1
            }
            Label {
                width: parent.width
                text: roomOwner
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
                maximumLineCount: 1
            }
        }
    }

    IconButton {
        anchors.centerIn: parent
        visible: controlsVisible && !playerLoading && playerError.length === 0
        z: 30
        icon.source: video.paused || video.ended
                     ? "image://theme/icon-l-play" : "image://theme/icon-l-pause"
        onClicked: {
            if (video.ended) {
                playbackSession.requestQuality(
                            playbackSession.selectedQuality > 0
                            ? playbackSession.selectedQuality : 0)
            } else {
                var requestedPause = !video.paused
                playbackSession.togglePaused()
                console.log("native live transport: pause requested",
                            requestedPause,
                            "actual", video.paused,
                            "position", video.position,
                            "frameSerial", video.presentedFrameSerial)
            }
            showControls()
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: bottomRow.height + 2 * Theme.paddingMedium
        visible: controlsVisible
        z: 30
        color: Theme.rgba("black", Theme.opacityHigh)

        Row {
            id: bottomRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.paddingMedium
            spacing: Theme.paddingMedium

            ValueButton {
                id: qualityButton
                width: Math.min(page.width - orientationButton.width - 3 * Theme.paddingLarge,
                                Theme.itemSizeHuge * 4)
                label: qsTr("清晰度")
                value: playbackSession.selectedQualityLabel
                onClicked: openQualityDialog()
            }

            IconButton {
                id: orientationButton
                icon.source: orientationMode === 1
                             ? "image://theme/icon-m-rotate"
                             : "image://theme/icon-m-orientation-lock"
                onClicked: cycleOrientationMode()
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        z: 40
        running: playerLoading && playerError.length === 0
        size: BusyIndicatorSize.Large
    }

    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        z: 40
        horizontalAlignment: Text.AlignHCenter
        text: playerError
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
        title: qsTr("直播清晰度")
        onQualitySelected: {
            requestQuality(quality)
            showControls()
        }
    }

    Timer {
        id: orientationToastTimer
        interval: 1800
        onTriggered: orientationToast.visible = false
    }
    Timer {
        id: fullResolutionTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (playbackSession.mediaKind !== "live")
                return
            playbackSession.setSurfaceHighResolution(videoHost, true)
            console.log("native live player: fullscreen native-resolution promotion requested",
                        "host", Math.round(videoHost.width), Math.round(videoHost.height),
                        "source", playbackSession.videoWidth, playbackSession.videoHeight)
        }
    }
    Timer {
        id: hideTimer
        interval: 3200
        onTriggered: {
            if (playerPlaying)
                controlsVisible = false
        }
    }
    Timer {
        // Development-only semantic regression: after the first real frame,
        // request one different server-advertised live quality and require a
        // second real frame on the same process-lifetime player. Production
        // pages leave qualityRegression false and never run this timer.
        interval: 250
        repeat: true
        running: qualityRegression && !qualityRegressionRequested
        onTriggered: {
            if (video.presentedFrameSerial <= 0 || playbackSession.loading
                    || playbackSession.qualities.length < 2)
                return
            for (var index = playbackSession.qualities.length - 1; index >= 0; --index) {
                var candidate = playbackSession.qualities[index].id
                if (candidate !== playbackSession.selectedQuality) {
                    qualityRegressionRequested = true
                    qualityRegressionPreviousLoadSerial = video.loadSerial
                    console.log("native live quality: cycle requested",
                                "from", playbackSession.selectedQuality,
                                "to", candidate,
                                "loadSerial", video.loadSerial,
                                "frameSerial", video.presentedFrameSerial)
                    requestQuality(candidate)
                    return
                }
            }
        }
    }
}
