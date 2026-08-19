import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.player 1.0

CoverBackground {
    id: cover

    readonly property bool liveCoverVideo:
        systemPipController.backgroundPlaybackMode === "cover"
    readonly property bool liveStream:
        playbackSession.mediaKind === "live"
    readonly property real progressRatio:
        liveStream ? 1.0
                   : Math.max(0, Math.min(1,
                         playbackSession.position
                         / Math.max(1, playbackSession.duration)))
    property string lastLayoutProbeSignature: ""

    onWidthChanged: scheduleLayoutProbe()
    onHeightChanged: scheduleLayoutProbe()

    function layoutProbeSignature() {
        return Math.round(cover.width) + "x"
                + Math.round(cover.height) + "|"
                + Math.round(artwork.height) + "|"
                + Math.round(playbackCover.spacing) + "|"
                + playbackSession.mediaKind + "|"
                + systemPipController.backgroundPlaybackMode
    }

    function scheduleLayoutProbe() {
        if (!playbackSession.active) {
            lastLayoutProbeSignature = ""
            coverLayoutProbe.stop()
            return
        }
        if (layoutProbeSignature() !== lastLayoutProbeSignature
                && !coverLayoutProbe.running) {
            coverLayoutProbe.start()
        }
    }

    function paddedNumber(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(seconds || 0))
        var hours = Math.floor(total / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        var remaining = total % 60
        if (hours > 0)
            return hours + ":" + paddedNumber(minutes) + ":"
                    + paddedNumber(remaining)
        return paddedNumber(minutes) + ":" + paddedNumber(remaining)
    }

    function resolutionText() {
        var label = playbackSession.selectedQualityLabel || ""
        if (playbackSession.videoWidth > 0 && playbackSession.videoHeight > 0) {
            var dimensions = playbackSession.videoWidth + "x"
                    + playbackSession.videoHeight
            if (label.indexOf(dimensions) < 0
                    && label.indexOf(playbackSession.videoWidth + "×"
                                     + playbackSession.videoHeight) < 0) {
                label += (label.length > 0 ? " · " : "") + dimensions
            }
        }
        if (playbackVideo.sourceFrameRate > 1.0 && label.indexOf("fps") < 0) {
            label += (label.length > 0 ? " · " : "")
                    + Math.round(playbackVideo.sourceFrameRate) + " fps"
        }
        return label.length > 0 ? label : qsTr("正在获取分辨率")
    }

    function toggleBackgroundPresentation() {
        var previous = systemPipController.backgroundPlaybackMode
        var next = previous === "cover" ? "pip" : "cover"
        systemPipController.setBackgroundPlaybackMode(next)
        scheduleLayoutProbe()
        console.log("native cover: background presentation toggle handled",
                    "from", previous,
                    "to", next,
                    "stored", systemPipController.backgroundPlaybackMode,
                    "mediaKind", playbackSession.mediaKind)
    }

    // Fill beyond every edge so the clipped, rotated rows never leave a bare
    // corner. The source artwork is supplied at high resolution and reduced in
    // the resource bundle; every tile reuses that one decoded image.
    Item {
        id: idleWatermark
        anchors.fill: parent
        visible: !playbackSession.active
        clip: true

        Item {
            id: watermarkPlane
            width: cover.width * 1.75
            height: cover.height * 1.55
            anchors.centerIn: parent
            rotation: -24
            transformOrigin: Item.Center

            readonly property int columns: 5
            readonly property int rows: 8
            readonly property real cellWidth: width / columns
            readonly property real cellHeight: height / rows

            Repeater {
                model: watermarkPlane.columns * watermarkPlane.rows

                delegate: Image {
                    readonly property int tileRow:
                        Math.floor(index / watermarkPlane.columns)
                    width: Math.min(watermarkPlane.cellWidth * 0.84,
                                    Theme.itemSizeHuge * 1.34)
                    height: width * 316 / 512
                    x: (index % watermarkPlane.columns)
                       * watermarkPlane.cellWidth
                       + (tileRow % 2) * watermarkPlane.cellWidth * 0.5
                       - width * 0.5
                    y: tileRow * watermarkPlane.cellHeight
                       + (tileRow % 3) * Theme.paddingSmall
                    source: "qrc:/qml/assets/cover-handheld-watermark.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: false
                    opacity: tileRow % 2 === 0 ? 0.16 : 0.11
                }
            }
        }
    }

    Image {
        id: idleLogo
        property bool readinessReported: false

        visible: !playbackSession.active
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.72, Theme.itemSizeHuge * 2.1)
        height: width * 56 / 144
        source: "qrc:/qml/assets/cover-idle-logo.png"
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        smooth: true

        function reportReadiness() {
            if (status !== Image.Ready || readinessReported)
                return
            readinessReported = true
            console.log("native cover: idle logo ready",
                        "source", sourceSize.width + "x" + sourceSize.height,
                        "display", Math.round(width) + "x"
                                   + Math.round(height),
                        "watermarks",
                        watermarkPlane.columns * watermarkPlane.rows)
        }

        onStatusChanged: reportReadiness()
        Component.onCompleted: reportReadiness()
    }

    Timer {
        id: coverLayoutProbe
        interval: 240
        repeat: false
        running: true
        onTriggered: {
            if (playbackSession.active) {
                var signature = cover.layoutProbeSignature()
                if (signature === cover.lastLayoutProbeSignature)
                    return
                cover.lastLayoutProbeSignature = signature
                console.log("native cover: active layout ready",
                            "order", "resolution-video-title-progress-actions",
                            "cover", Math.round(cover.width) + "x"
                                     + Math.round(cover.height),
                            "videoHeight", Math.round(artwork.height),
                            "gap", Math.round(playbackCover.spacing),
                            "occupiedHeight",
                            Math.round(playbackCover.occupiedHeight),
                            "availableHeight",
                            Math.round(playbackCover.height),
                            "balanced",
                            playbackCover.balancedDistribution,
                            "progress", cover.progressRatio.toFixed(3),
                            "actions", 3,
                            "mode",
                            systemPipController.backgroundPlaybackMode)
            } else {
                cover.lastLayoutProbeSignature = ""
            }
        }
    }

    Connections {
        target: playbackSession
        onChanged: cover.scheduleLayoutProbe()
    }

    Column {
        id: playbackCover
        visible: playbackSession.active
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.paddingMedium
        anchors.bottomMargin: Theme.itemSizeSmall + Theme.paddingSmall
        anchors.leftMargin: Theme.paddingMedium
        anchors.rightMargin: Theme.paddingMedium
        spacing: distributedGap

        readonly property real fixedContentHeight:
            resolutionLabel.implicitHeight + titleClip.height
            + progressBlock.height
        readonly property real minimumGap: Theme.paddingSmall
        readonly property real availableVideoHeight:
            Math.max(Theme.itemSizeSmall,
                     height - fixedContentHeight - minimumGap * 3)
        readonly property real videoHeight:
            Math.min(width * 9 / 16, availableVideoHeight)
        readonly property real distributedGap:
            Math.max(minimumGap,
                     (height - fixedContentHeight - videoHeight) / 3)
        readonly property real occupiedHeight:
            fixedContentHeight + videoHeight + spacing * 3
        readonly property bool balancedDistribution:
            spacing >= minimumGap
            && Math.abs(occupiedHeight - height) <= 1

        Label {
            id: resolutionLabel
            width: parent.width
            text: cover.resolutionText()
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
            truncationMode: TruncationMode.Fade
        }

        Item {
            id: artwork
            width: parent.width
            height: playbackCover.videoHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            MpvVideoMirrorItem {
                id: coverVideo
                anchors.fill: parent
                usage: "cover"
                source: cover.liveCoverVideo ? playbackVideo : null
                preserveAspectRatio: true
                visible: cover.liveCoverVideo
                         && playbackSession.active && !playbackSession.ended
            }

            Image {
                anchors.fill: parent
                visible: playbackSession.cover.length > 0
                         && (!cover.liveCoverVideo || playbackSession.loading)
                source: playbackSession.cover
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Label {
                anchors.centerIn: parent
                visible: !cover.liveCoverVideo
                         && playbackSession.cover.length === 0
                text: qsTr("系统小窗播放")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor,
                                         Theme.opacityLow)
            }
        }

        Item {
            id: titleClip
            width: parent.width
            height: titleLabel.implicitHeight + Theme.paddingSmall
            clip: true

            readonly property real overflow:
                Math.max(0, titleLabel.implicitWidth - width)

            Label {
                id: titleLabel
                y: (parent.height - height) / 2
                x: titleClip.overflow > 0
                   ? 0 : (titleClip.width - implicitWidth) / 2
                text: playbackSession.title
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }

            SequentialAnimation {
                id: titleMarquee
                running: playbackSession.active
                         && titleClip.overflow > Theme.paddingSmall
                loops: Animation.Infinite

                PauseAnimation { duration: 900 }
                NumberAnimation {
                    target: titleLabel
                    property: "x"
                    from: 0
                    to: -titleClip.overflow
                    duration: Math.max(1800, titleClip.overflow * 24)
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 700 }
                NumberAnimation {
                    target: titleLabel
                    property: "x"
                    from: -titleClip.overflow
                    to: 0
                    duration: 260
                    easing.type: Easing.OutQuad
                }
            }
        }

        Item {
            id: progressBlock
            width: parent.width
            height: progressTrack.height + progressTimes.implicitHeight
                    + Theme.paddingSmall

            Rectangle {
                id: progressTrack
                anchors.top: parent.top
                width: parent.width
                height: Math.max(3, Theme.paddingSmall / 3)
                radius: height / 2
                color: Theme.rgba(Theme.primaryColor, Theme.opacityLow)

                Rectangle {
                    width: parent.width * cover.progressRatio
                    height: parent.height
                    radius: parent.radius
                    color: Theme.highlightColor
                }
            }

            Row {
                id: progressTimes
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: progressTrack.bottom
                anchors.topMargin: Theme.paddingSmall

                Label {
                    width: parent.width / 2
                    text: cover.liveStream
                          ? qsTr("直播")
                          : cover.formatTime(playbackSession.position)
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    width: parent.width / 2
                    text: cover.liveStream
                          ? (playbackSession.paused ? qsTr("已暂停")
                                                    : qsTr("实时"))
                          : cover.formatTime(playbackSession.duration)
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    CoverActionList {
        enabled: playbackSession.active

        CoverAction {
            iconSource: playbackSession.paused
                        ? "image://theme/icon-cover-play"
                        : "image://theme/icon-cover-pause"
            onTriggered: playbackSession.togglePaused()
        }
        CoverAction {
            iconSource: systemPipController.backgroundPlaybackMode === "cover"
                        ? "file:///usr/share/icons/hicolor/86x86/apps/silisili-native-cover-pip.png"
                        : "file:///usr/share/icons/hicolor/86x86/apps/silisili-native-cover-cover.png"
            onTriggered: cover.toggleBackgroundPresentation()
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-cancel"
            onTriggered: playbackSession.stop()
        }
    }
}
