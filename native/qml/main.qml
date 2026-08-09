import QtQuick 2.2
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow {
    id: appWindow
    property int runtimeOrientations: nativeForcedOrientation === "landscape"
                                      ? Orientation.Landscape | Orientation.LandscapeInverted
                                      : nativeForcedOrientation === "portrait"
                                        ? Orientation.Portrait | Orientation.PortraitInverted
                                        : Orientation.All
    property bool compactTestTransitionComplete: false
    property int compactContinuityStage: 0
    property bool multipartEofTestRequested: false
    allowedOrientations: runtimeOrientations
    initialPage: nativeTestPage === "navigation" ? navigationTestPage
                 : nativeTestPage === "about" ? aboutTestPage
                 : nativeTestPage === "playback-presentation" ? playbackPresentationTestPage
                 : nativeTestPage === "account-library" ? accountLibraryTestPage
                 : nativeTestPage === "comment-actions" ? commentActionsTestPage
                 : nativeTestPage === "pgc-consistency" ? pgcConsistencyTestPage
                 : nativeTestPage === "dynamic" ? dynamicTestPage
                 : nativeTestPage === "author-space" ? authorSpaceTestPage
                 : nativeTestPage === "video-detail" || nativeTestPage === "compact"
                   || nativeTestPage === "compact-continuity"
                   || nativeTestPage === "multipart-autonext"
                   || nativeTestPage === "history-resume"
                   ? videoDetailTestPage : homePage
    cover: Qt.resolvedUrl("cover/CoverPage.qml")

    Component { id: homePage; HomePage {} }
    Component { id: navigationTestPage; NavigationPage {} }
    Component { id: aboutTestPage; AboutPage {} }
    Component { id: playbackPresentationTestPage; PlaybackPresentationPage {} }
    Component {
        id: pgcConsistencyTestPage
        PgcFeedPage { consistencyRegression: true }
    }
    Component {
        id: commentActionsTestPage
        CommentsPage {
            commentAid: nativeTestAid
            commentType: 1
            contentTitle: qsTr("评论操作回归")
            actionRegression: true
        }
    }
    Component {
        id: accountLibraryTestPage
        AccountLibraryPage {
            contentMode: nativeTestContentMode.length > 0
                         ? nativeTestContentMode : "history"
            pageTitle: qsTr("个人内容回归")
        }
    }
    Component {
        id: dynamicTestPage
        DynamicPage {
            feedSection: nativeTestContentMode === "video" ? "video" : "nonvideo"
        }
    }
    Component {
        id: authorSpaceTestPage
        AuthorSpacePage {
            authorMid: nativeTestMid
            initialName: qsTr("UP 主空间回归")
        }
    }
    Component {
        id: videoDetailTestPage
        VideoDetailPage {
            videoBvid: nativeTestBvid.length > 0 ? nativeTestBvid : "BV1Gg3E6BEdC"
            videoCid: nativeTestCid
            videoTitle: qsTr("横屏与悬浮窗测试")
            historyResumeRequested: nativeTestPage === "history-resume"
            historyResumePosition: nativeTestStartPosition
            // Direct regression models a tap after the visible home cards
            // have finished their bounded metadata prefetch.
            deferAutoplayUntilPrefetched: nativeTestPage !== "history-resume"
                                           && nativeTestContentMode !== "direct"
        }
    }

    Timer {
        // Device-only regression hook: drive a real multi-part first episode
        // to EOF, then let PlaybackSession prove that it opens the next cid on
        // the existing surface. Production launches never enable this mode.
        interval: 350
        repeat: true
        running: nativeTestPage === "multipart-autonext"
                 && !appWindow.multipartEofTestRequested
        onTriggered: {
            if (!playbackSession.active || playbackSession.loading
                    || !playbackSession.playing || playbackSession.duration <= 2)
                return
            appWindow.multipartEofTestRequested = true
            playbackSession.seek(Math.max(0, playbackSession.duration - 0.18))
            playbackSession.setPaused(false)
            console.log("native multipart: test EOF requested",
                        "cid", playbackSession.cid,
                        "duration", Math.round(playbackSession.duration))
        }
    }

    Timer {
        interval: 400
        repeat: true
        running: (nativeTestPage === "compact"
                  || nativeTestPage === "compact-continuity")
                 && !appWindow.compactTestTransitionComplete
        onTriggered: {
            if (playbackSession.active && playbackSession.duration > 0) {
                appWindow.compactTestTransitionComplete = true
                pageStack.push(Qt.resolvedUrl("pages/NavigationPage.qml"))
                console.log("native compact player: test transition handled",
                            "position", Math.round(playbackSession.position),
                            "duration", Math.round(playbackSession.duration))
            }
        }
    }

    Timer {
        // Keep the synthetic navigator at a human-operable PageStack cadence:
        // start the next push only after the previous 450 ms continuity audit
        // and its page construction have completed. This still exercises one
        // real animated transition per frame-floor window without stacking two
        // otherwise non-interactive page builds into the same GUI interval.
        interval: 1200
        repeat: true
        running: nativeTestPage === "compact-continuity"
                 && appWindow.compactTestTransitionComplete
                 && appWindow.compactContinuityStage < 4
        onTriggered: {
            if (pageStack.busy || !playbackSession.compact || playbackSession.ended)
                return
            if (appWindow.compactContinuityStage === 0) {
                pageStack.push(Qt.resolvedUrl("pages/SearchPage.qml"))
                appWindow.compactContinuityStage = 1
                console.log("native compact player: continuity test page switch", 1)
            } else if (appWindow.compactContinuityStage === 1) {
                pageStack.push(Qt.resolvedUrl("pages/NavigationPage.qml"))
                appWindow.compactContinuityStage = 2
                console.log("native compact player: continuity test page switch", 2)
            } else if (appWindow.compactContinuityStage === 2) {
                pageStack.push(Qt.resolvedUrl("pages/SearchPage.qml"))
                appWindow.compactContinuityStage = 3
                console.log("native compact player: continuity test page switch", 3)
            } else if (playbackSession.duration > 1) {
                appWindow.compactContinuityStage = 4
                playbackSession.seek(Math.max(0, playbackSession.duration - 0.18))
                playbackSession.setPaused(false)
                console.log("native compact player: continuity test EOF requested",
                            "duration", Math.round(playbackSession.duration))
            }
        }
    }

    Component.onCompleted: console.log("native layout: application ready forced",
                                       nativeForcedOrientation.length > 0
                                       ? nativeForcedOrientation : "device",
                                       "width", width, "height", height)
    onOrientationChanged: console.log("native layout: application orientation",
                                      orientation, "width", width, "height", height)

    function restoreCompactPlayer() {
        var target = pageStack.find(function(page) {
            return page
                   && typeof page.restorePlaybackSurface === "function"
                   && page.restorePlaybackSurface()
        })
        if (target) {
            if (typeof target.prepareCompactRestore === "function")
                target.prepareCompactRestore()
            if (target !== pageStack.currentPage)
                pageStack.pop(target)
            return
        }

        if (playbackSession.bvid.length > 0) {
            pageStack.push(Qt.resolvedUrl("pages/VideoDetailPage.qml"), {
                videoBvid: playbackSession.bvid,
                videoTitle: playbackSession.title,
                videoCover: playbackSession.cover
            })
            return
        }

        pageStack.push(Qt.resolvedUrl("pages/PlayerPage.qml"))
    }

    function formatCompactTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0))
        var minutes = Math.floor(value / 60)
        var secs = value % 60
        return minutes + ":" + (secs < 10 ? "0" : "") + secs
    }

    Rectangle {
        id: compactPlayer
        // ApplicationWindow exposes one stable layer that follows the active
        // page orientation. Keep the compact player there so PageStack never
        // detaches/reparents its live texture during navigation.
        parent: appWindow._rotatingItem
        property real edgeMargin: Theme.paddingMedium
        property real horizontalRatio: 1.0
        property real verticalRatio: 0.90
        property bool dragMoved: false
        property bool positioned: false
        property bool controlsVisible: false
        property bool landscapeOrientation: parent && parent.width > parent.height
        property real longEdge: parent ? Math.max(parent.width, parent.height) : 0
        property real shortEdge: parent ? Math.min(parent.width, parent.height) : 0
        property real compactAspectRatio: Math.max(16 / 9,
                                                    playbackSession.videoAspectRatio > 0
                                                    ? playbackSession.videoAspectRatio : 16 / 9)
        property real targetWidth: landscapeOrientation
                                   ? Math.min(longEdge * 0.42, shortEdge * 0.86)
                                   : (parent ? parent.width * 0.52 : 0)

        width: Math.min(Math.max(0, parent ? parent.width - 2 * edgeMargin : 0),
                        Math.max(0, parent ? parent.height - 2 * edgeMargin : 0)
                        * compactAspectRatio,
                        Math.max(Theme.itemSizeHuge * 2.6,
                                 Math.min(targetWidth, Theme.itemSizeHuge * 4.6)))
        height: width / compactAspectRatio
        z: 1000
        visible: playbackSession.active && playbackSession.compact
                 && !playbackSession.surfaceTransition
                 && !playbackSession.ended
        clip: true
        radius: Theme.paddingSmall
        color: "black"

        function availableX() {
            return Math.max(0, parent.width - width - 2 * edgeMargin)
        }

        function availableY() {
            return Math.max(0, parent.height - height - 2 * edgeMargin)
        }

        function placeFromRatio(reason) {
            if (!visible || parent.width <= 0 || parent.height <= 0)
                return
            x = edgeMargin + availableX() * Math.max(0, Math.min(1, horizontalRatio))
            y = edgeMargin + availableY() * Math.max(0, Math.min(1, verticalRatio))
            positioned = true
            console.log("native compact player: floating geometry", reason,
                        "orientation", landscapeOrientation ? "landscape" : "portrait",
                        "coordinateSpaceWidth", Math.round(parent.width),
                        "coordinateSpaceHeight", Math.round(parent.height),
                        "rotationLayerBound", parent === appWindow._rotatingItem,
                        "x", Math.round(x), "y", Math.round(y),
                        "width", Math.round(width), "height", Math.round(height),
                        "aspect", width / Math.max(1, height),
                        "landscapeWindow", width > height)
        }

        function rememberPosition(reason) {
            horizontalRatio = availableX() > 0
                              ? Math.max(0, Math.min(1, (x - edgeMargin) / availableX())) : 0
            verticalRatio = availableY() > 0
                            ? Math.max(0, Math.min(1, (y - edgeMargin) / availableY())) : 0
            placeFromRatio(reason)
        }

        function showControls(reason) {
            controlsVisible = true
            compactControlsTimer.restart()
            console.log("native compact player: controls shown", reason,
                        "overlayFraction",
                        compactControlBar.height / Math.max(1, height),
                        "unobscuredFraction",
                        1 - compactControlBar.height / Math.max(1, height))
        }

        function hideControls(reason) {
            controlsVisible = false
            compactControlsTimer.stop()
            console.log("native compact player: controls hidden", reason,
                        "overlayFraction", 0,
                        "unobscuredFraction", 1)
        }

        onVisibleChanged: {
            console.log("native compact player: visibility",
                        visible ? "visible" : "hidden",
                        "active", playbackSession.active,
                        "compact", playbackSession.compact,
                        "ended", playbackSession.ended,
                        "stableParent", parent === appWindow._rotatingItem,
                        "frameSerial", playbackVideo.presentedFrameSerial)
            if (visible) {
                hideControls("compact-visible")
                compactPositionTimer.restart()
            } else {
                controlsVisible = false
                compactControlsTimer.stop()
            }
        }
        onWidthChanged: if (visible) compactPositionTimer.restart()
        onHeightChanged: if (visible) compactPositionTimer.restart()
        onParentChanged: console.log("native compact player: parent changed",
                                     "stableRotationLayer",
                                     parent === appWindow._rotatingItem)
        Component.onCompleted: {
            if (parent)
                parent.z = 1000
            console.log("native compact player: stable rotation layer ready",
                        "parentStable", parent === appWindow._rotatingItem,
                        "layerWidth", parent ? Math.round(parent.width) : 0,
                        "layerHeight", parent ? Math.round(parent.height) : 0)
        }

        Connections {
            target: compactPlayer.parent
            onWidthChanged: if (compactPlayer.visible) compactPositionTimer.restart()
            onHeightChanged: if (compactPlayer.visible) compactPositionTimer.restart()
        }

        Connections {
            target: pageStack
            onCurrentPageChanged: {
                if (compactPlayer.visible) {
                    compactPositionTimer.restart()
                    compactTransitionAuditTimer.restart()
                    console.log("native compact player: page transition retained",
                                "phase", "start",
                                "visible", compactPlayer.visible,
                                "stableParent",
                                compactPlayer.parent === appWindow._rotatingItem,
                                "frameSerial", playbackVideo.presentedFrameSerial)
                }
            }
        }

        Timer {
            id: compactTransitionAuditTimer
            interval: 450
            repeat: false
            onTriggered: console.log("native compact player: page transition retained",
                                     "phase", "complete",
                                     "visible", compactPlayer.visible,
                                     "stableParent",
                                     compactPlayer.parent === appWindow._rotatingItem,
                                     "frameSerial", playbackVideo.presentedFrameSerial)
        }

        Timer {
            id: compactPositionTimer
            interval: 100
            repeat: false
            onTriggered: compactPlayer.placeFromRatio(compactPlayer.positioned
                                                       ? "bounds-changed" : "initial")
        }

        Timer {
            id: compactControlsTimer
            interval: 2200
            repeat: false
            onTriggered: compactPlayer.hideControls("auto-hide")
        }

        Rectangle {
            anchors.fill: parent
            radius: compactPlayer.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.highlightColor
            opacity: Theme.opacityHigh
            z: 5
        }

        Image {
            anchors.fill: parent
            visible: playbackSession.loading
            source: playbackSession.cover
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            onVisibleChanged: console.log("native compact player: loading cover",
                                          visible ? "visible" : "hidden",
                                          "orientation",
                                          compactPlayer.landscapeOrientation
                                          ? "landscape" : "portrait")
        }

        Item {
            id: compactVideoHost
            anchors.fill: parent
            Component.onCompleted: playbackSession.setFallbackHost(compactVideoHost)
        }

        MouseArea {
            anchors.fill: parent
            drag.target: compactPlayer
            drag.axis: Drag.XAndYAxis
            drag.minimumX: compactPlayer.edgeMargin
            drag.maximumX: Math.max(drag.minimumX,
                                    compactPlayer.parent.width - compactPlayer.width
                                    - compactPlayer.edgeMargin)
            drag.minimumY: compactPlayer.edgeMargin
            drag.maximumY: Math.max(drag.minimumY,
                                    compactPlayer.parent.height - compactPlayer.height
                                    - compactPlayer.edgeMargin)
            onPressed: {
                compactPlayer.dragMoved = false
                console.log("native compact player: drag started",
                            "x", Math.round(compactPlayer.x),
                            "y", Math.round(compactPlayer.y))
            }
            onPositionChanged: {
                if (drag.active)
                    compactPlayer.dragMoved = true
            }
            onReleased: {
                if (compactPlayer.dragMoved)
                    compactPlayer.rememberPosition("drag-repositioned")
            }
            onClicked: {
                if (!compactPlayer.dragMoved) {
                    if (compactPlayer.controlsVisible)
                        compactPlayer.hideControls("touch-toggle")
                    else
                        compactPlayer.showControls("touch-toggle")
                }
            }
            onDoubleClicked: {
                if (!compactPlayer.dragMoved) {
                    console.log("native compact player: activated")
                    compactPlayer.hideControls("double-tap-restore")
                    appWindow.restoreCompactPlayer()
                }
            }
        }

        Rectangle {
            id: compactControlBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Theme.itemSizeMedium, parent.height * 0.24)
            color: Theme.rgba("black", Theme.opacityHigh)
            visible: compactPlayer.controlsVisible
            z: 10

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: restoreButton.left
                anchors.rightMargin: Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("%1 / %2 · %3")
                      .arg(appWindow.formatCompactTime(playbackSession.position))
                      .arg(appWindow.formatCompactTime(playbackSession.duration))
                      .arg(playbackSession.selectedQualityLabel)
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
            }

            IconButton {
                id: restoreButton
                anchors.right: pauseButton.left
                anchors.verticalCenter: parent.verticalCenter
                width: compactControlBar.height
                height: compactControlBar.height
                icon.source: "image://theme/icon-m-enter-next"
                onClicked: {
                    console.log("native compact player: activated")
                    compactPlayer.hideControls("button-restore")
                    appWindow.restoreCompactPlayer()
                }
            }
            IconButton {
                id: pauseButton
                anchors.right: stopButton.left
                anchors.verticalCenter: parent.verticalCenter
                width: compactControlBar.height
                height: compactControlBar.height
                icon.source: playbackSession.paused ? "image://theme/icon-m-play" : "image://theme/icon-m-pause"
                onClicked: {
                    playbackSession.togglePaused()
                    compactPlayer.showControls("pause-toggle")
                }
            }
            IconButton {
                id: stopButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                width: compactControlBar.height
                height: compactControlBar.height
                icon.source: "image://theme/icon-m-close"
                onClicked: {
                    console.log("native compact player: closed")
                    compactPlayer.hideControls("closed")
                    playbackSession.stop()
                }
            }
        }
    }
}
