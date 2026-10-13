import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    readonly property bool coverPlaybackPage: true
    property bool landscapeLayout: width > height
    property real landscapePlayerWidth: Math.round(width * 0.64)
    property string videoTitle
    property string videoOwner
    property string videoBvid
    property string videoCid
    property string videoCover
    property bool historyResumeRequested: false
    property real historyResumePosition: 0
    property int requestedInitialPlaybackQuality: 0
    readonly property int effectiveInitialPlaybackQuality:
        requestedInitialPlaybackQuality > 0
        ? requestedInitialPlaybackQuality : accountService.defaultPlaybackQuality
    property bool historyResumeConsumed: false
    property bool inlineControlsVisible: true
    property bool wasInlinePlaying: false
    property bool initialPlaybackRequested: false
    property bool commentsScheduled: false
    property bool relatedScheduled: false
    property bool commentRequestIssued: false
    property bool relatedRequestIssued: false
    property int commentRequestCount: 0
    property int relatedRequestCount: 0
    property bool detailReady: false
    property bool playbackSettled: false
    property bool userExploredDetails: false
    property bool compactRestorePending: false
    property bool compactRestoreRecoveryActive: false
    property int visibleDetailStage: 0
    property int visiblePartCount: 0
    property int visibleCommentCount: 0
    property int visibleRelatedCount: 0
    property int maxPreviewComments: 4
    property int maxPreviewRelated: 6
    property string pendingAutoplayCid
    property string pendingAutoplayTitle
    property string pendingDanmakuCid
    property bool retainedByDialog: pageStack.currentPage
                                    && pageStack.currentPage !== page
                                    && typeof pageStack.currentPage.playbackSurfaceOwner !== "undefined"
                                    && pageStack.currentPage.playbackSurfaceOwner === page
    property bool isCurrentVideo: playbackSession.active && playbackSession.bvid === videoBvid
    property bool inlinePlayerLoading: isCurrentVideo && playbackSession.loading
                                       && playbackSession.errorMessage.length === 0
    property string inlinePlayerError: isCurrentVideo ? playbackSession.errorMessage : ""
    property bool inlinePlaybackReady: isCurrentVideo && !inlinePlayerLoading
                                        && inlinePlayerError.length === 0
                                        && playbackSession.duration > 0
    property bool inlineTransportAvailable: isCurrentVideo
                                            && inlinePlayerError.length === 0
                                            && playbackSession.duration > 0
    property bool inlinePlaying: Qt.application.active && status === PageStatus.Active
                                 && isCurrentVideo && playbackSession.playing
    property bool wantsPlaybackSurface: (status === PageStatus.Active || retainedByDialog)
                                        && isCurrentVideo
    property var video: playbackVideo
    property var qualityMatrixIds: []
    property var qualityMatrixResolvedIds: []
    property int qualityMatrixIndex: -1
    property int qualityMatrixRequestedId: 0
    property int qualityMatrixPreviousLoadSerial: 0
    property bool qualityMatrixAwaitingFrame: false
    property double qualityMatrixSettledAtMs: 0
    property bool qualityMatrixComplete: false
    property bool systemVolumeRegressionStopScheduled: false
    allowedOrientations: Orientation.All

    VideoDetailModel { id: videoDetail }
    CommentModel { id: commentModel }
    RelatedModel { id: relatedModel }

    ResponsivePageMetrics {
        target: page
        pageName: "video-detail"
        columns: page.landscapeLayout ? 2 : 1
        primaryExtent: inlinePlayer.width
        secondaryExtent: detailFlickable.width
    }

    function formatTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0))
        var hours = Math.floor(value / 3600)
        var minutes = Math.floor((value % 3600) / 60)
        var secs = value % 60
        var result = (minutes < 10 && hours > 0 ? "0" : "") + minutes
                     + ":" + (secs < 10 ? "0" : "") + secs
        return hours > 0 ? hours + ":" + result : result
    }

    function openPlayer(cid, title) {
        if (!cid || cid.length === 0)
            return
        console.log("native playback quality: initial policy",
                    "mediaKind", "video",
                    "loggedIn", accountService.loggedIn,
                    "sessionCredentials", accountService.hasSessionCredentials,
                    "override", requestedInitialPlaybackQuality,
                    "requestedQuality", effectiveInitialPlaybackQuality)
        playbackSettled = false
        playbackSettledTimer.stop()
        supplementaryFallbackTimer.restart()
        console.log("native detail perf: start playback request", videoBvid, cid)
        // Claim the inline host before activating a prepared session. This
        // prevents the global compact layer from flashing one stale/empty
        // frame between the tap and the detail player's synchronous claim.
        playbackSession.claimSurface(inlineVideoHost)
        var useHistoryResume = historyResumeRequested && !historyResumeConsumed
                               && (videoCid.length === 0 || videoCid === cid)
        if (useHistoryResume) {
            historyResumeConsumed = true
            var startPosition = Math.max(0, historyResumePosition)
            console.log("native history resume: detail accepted",
                        "kind", "video", "bvid", videoBvid, "cid", cid,
                        "position", Math.round(startPosition))
            playbackSession.playVideoAt(videoBvid, cid,
                                        title || videoDetail.title || videoTitle,
                                        videoDetail.cover || videoCover,
                                        startPosition, effectiveInitialPlaybackQuality)
        } else {
            playbackSession.playVideo(videoBvid, cid,
                                      title || videoDetail.title || videoTitle,
                                      videoDetail.cover || videoCover,
                                      effectiveInitialPlaybackQuality)
        }
        pendingDanmakuCid = cid
        // Danmaku is useful but can parse/create many overlay items. Keep it
        // behind the first-frame path instead of competing with page entry.
        danmakuLoadTimer.restart()
        updatePlayerSurface()
    }

    function openFullscreen() {
        if (!playbackSession.active || playbackSession.bvid !== videoBvid)
            openPlayer(videoDetail.firstCid, videoDetail.title)
        if (playbackSession.active) {
            playbackSession.beginSurfaceTransition(inlineVideoHost)
            pageStack.push(Qt.resolvedUrl("PlayerPage.qml"), {
                returnSurfaceOwner: page
            })
        }
    }

    function restorePlaybackSurface() {
        return playbackSession.active && playbackSession.bvid === videoBvid
    }

    function prepareCompactRestore() {
        compactRestorePending = true
        compactRestoreRecoveryActive = true
        console.log("native detail perf: compact restore requested",
                    "comments", commentModel.count,
                    "related", relatedModel.count)
    }

    function requestComments(reason) {
        if (commentRequestIssued || commentModel.loading
                || videoDetail.aid.length === 0)
            return false
        commentLoadTimer.stop()
        commentsScheduled = true
        visibleCommentCount = 0
        commentRevealTimer.stop()
        commentRequestIssued = true
        ++commentRequestCount
        console.log("native detail perf: loading comments", reason,
                    "requestCount", commentRequestCount)
        commentModel.load(videoDetail.aid)
        return true
    }

    function requestRelated(reason) {
        if (relatedRequestIssued || relatedModel.loading
                || videoBvid.length === 0)
            return false
        relatedLoadTimer.stop()
        relatedScheduled = true
        visibleRelatedCount = 0
        relatedRevealTimer.stop()
        relatedRequestIssued = true
        ++relatedRequestCount
        console.log("native detail perf: loading related", reason,
                    "requestCount", relatedRequestCount)
        relatedModel.load(videoBvid)
        return true
    }

    function ensureCompactRestoreContent() {
        if (!compactRestoreRecoveryActive || status !== PageStatus.Active
                || !detailReady)
            return

        // Returning from the floating player is an explicit request to see
        // the detail page again. Do not leave comments or recommendations
        // behind viewport-distance lazy-loading gates. The issued flags keep
        // already-running/completed models intact, avoiding duplicate rows.
        if (!commentRequestIssued)
            requestComments("compact-restore")
        if (!relatedRequestIssued)
            requestRelated("compact-restore")
    }

    function resumeSupplementaryContent(reason) {
        if (status !== PageStatus.Active)
            return
        if (!playbackSettled && isCurrentVideo && playbackSession.duration > 0
                && !playbackSession.loading)
            markPlaybackSettled("compact-restore")
        maybeLoadSupplementaryContent()
        if (compactRestorePending || compactRestoreRecoveryActive)
            ensureCompactRestoreContent()
        // A request may finish while this page is below the compact player.
        // Its reveal timer then stops because the page is inactive; restart
        // delegate revelation from the already-loaded models without issuing
        // duplicate API requests or duplicating list rows.
        if (commentsScheduled && !commentModel.loading
                && commentModel.count > visibleCommentCount
                && !commentRevealTimer.running)
            commentRevealTimer.restart()
        if (relatedScheduled && !relatedModel.loading
                && relatedModel.count > visibleRelatedCount
                && !relatedRevealTimer.running)
            relatedRevealTimer.restart()
        console.log("native detail perf: supplementary content resumed", reason,
                    "comments", commentModel.count,
                    "visibleComments", visibleCommentCount,
                    "related", relatedModel.count,
                    "visibleRelated", visibleRelatedCount)
        compactRestorePending = false
        reportCompactRestoreContentReady()
    }

    function reportCompactRestoreContentReady() {
        if (!compactRestoreRecoveryActive || status !== PageStatus.Active
                || !commentRequestIssued || !relatedRequestIssued
                || commentModel.loading || relatedModel.loading
                || visibleCommentCount < Math.min(maxPreviewComments, commentModel.count)
                || visibleRelatedCount < Math.min(maxPreviewRelated, relatedModel.count))
            return
        compactRestoreRecoveryActive = false
        console.log("native detail perf: compact restore content ready",
                    "comments", commentModel.count,
                    "related", relatedModel.count,
                    "visibleComments", visibleCommentCount,
                    "visibleRelated", visibleRelatedCount,
                    "commentRequests", commentRequestCount,
                    "relatedRequests", relatedRequestCount,
                    "duplicateRequests", commentRequestCount > 1
                                         || relatedRequestCount > 1)
    }

    function updatePlayerSurface() {
        // When Sailfish activates the Cover, PageStatus may temporarily become
        // inactive. Retain the current main-window host while the application
        // is backgrounded; moving to the fallback host would tear down mpv's
        // active video output. Foreground PageStack changes still release it.
        if (wantsPlaybackSurface)
            playbackSession.claimSurface(inlineVideoHost)
        else
            playbackSession.releaseSurface(inlineVideoHost)
    }

    function openCommentDialog() {
        if (videoDetail.aid.length === 0)
            return
        commentLoadTimer.stop()
        commentsScheduled = true
        requestComments("comment-dialog")
        pageStack.push(Qt.resolvedUrl("CommentDialog.qml"), {
            commentModel: commentModel,
            playbackSurfaceOwner: page
        })
    }

    function openCommentReplyDialog(parentRpid, rootRpid, author) {
        if (videoDetail.aid.length === 0 || !accountService.loggedIn)
            return
        commentLoadTimer.stop()
        commentsScheduled = true
        requestComments("comment-reply-dialog")
        console.log("native comment action: reply editor opened",
                    "parent", parentRpid, "root", rootRpid, "author", author)
        pageStack.push(Qt.resolvedUrl("CommentDialog.qml"), {
            commentModel: commentModel,
            playbackSurfaceOwner: page,
            replyMode: true,
            parentRpid: parentRpid,
            rootRpid: rootRpid,
            replyAuthor: author
        })
    }

    function openAllComments() {
        if (videoDetail.aid.length === 0)
            return
        commentLoadTimer.stop()
        commentsScheduled = true
        pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
            commentAid: videoDetail.aid,
            contentTitle: videoDetail.title || videoTitle,
            sharedCommentModel: commentModel
        })
    }

    function requestAutoplay(cid, title) {
        pendingAutoplayCid = cid
        pendingAutoplayTitle = title || ""
        initialPlaybackTimer.restart()
    }

    function isNearFlickableItem(item, screensAhead) {
        if (!item || !detailFlickable || detailFlickable.height <= 0)
            return false
        return item.y - detailFlickable.contentY < detailFlickable.height * screensAhead
    }

    function markDetailExplored() {
        if (!userExploredDetails && detailFlickable.contentY > Theme.paddingMedium) {
            userExploredDetails = true
            console.log("native detail perf: user explored detail content")
        }
        maybeLoadSupplementaryContent()
    }

    function maybeLoadSupplementaryContent() {
        if (!detailReady || !playbackSettled || status !== PageStatus.Active)
            return
        if (!commentsScheduled) {
            if (videoDetail.aid.length > 0
                    && (userExploredDetails || isNearFlickableItem(commentsSection, 1.9))) {
                commentsScheduled = true
                commentLoadTimer.restart()
                console.log("native detail perf: scheduled lazy comments")
            }
        }
        if (!relatedScheduled) {
            if (userExploredDetails || isNearFlickableItem(relatedSection, 2.1)) {
                relatedScheduled = true
                relatedLoadTimer.restart()
                console.log("native detail perf: scheduled lazy related")
            }
        }
    }

    function markPlaybackSettled(reason) {
        if (playbackSettled)
            return
        playbackSettled = true
        supplementaryFallbackTimer.stop()
        console.log("native detail perf: playback settled", reason)
        maybeLoadSupplementaryContent()
    }

    function scrollToComments() {
        var target = Math.max(0, commentsSection.y - Theme.paddingLarge)
        detailFlickable.contentY = Math.min(target,
                                             Math.max(0, detailFlickable.contentHeight - detailFlickable.height))
    }

    function showInlineControls() {
        inlineControlsVisible = true
        if (inlinePlaying)
            inlineHideTimer.restart()
        else
            inlineHideTimer.stop()
    }

    function toggleInlineControls() {
        if (!isCurrentVideo || inlinePlayerLoading || inlinePlayerError.length > 0
                || playbackSession.paused || playbackSession.ended) {
            inlineControlsVisible = true
            inlineHideTimer.stop()
        } else if (inlineControlsVisible) {
            inlineControlsVisible = false
            inlineHideTimer.stop()
        } else {
            showInlineControls()
        }
    }

    function synchronizeInlineControls() {
        if (!isCurrentVideo || inlinePlayerLoading || inlinePlayerError.length > 0
                || playbackSession.paused || playbackSession.ended
                || status !== PageStatus.Active
                || !Qt.application.active) {
            inlineControlsVisible = true
            inlineHideTimer.stop()
        } else if (inlinePlaying && !wasInlinePlaying) {
            showInlineControls()
        }
        wasInlinePlaying = inlinePlaying
    }

    function reportInlineGestureGeometry(reason) {
        var point = inlineGestures.mapToItem(page, 0, 0)
        console.log("native detail controls: gesture geometry",
                    "reason", reason,
                    "x", Math.round(point.x),
                    "y", Math.round(point.y),
                    "width", Math.round(inlineGestures.width),
                    "height", Math.round(inlineGestures.height),
                    "pageWidth", Math.round(page.width),
                    "pageHeight", Math.round(page.height),
                    "systemControls", inlineGestures.systemController !== null)
    }

    Component.onCompleted: {
        if (videoCid.length > 0 && !initialPlaybackRequested) {
            initialPlaybackRequested = true
            requestAutoplay(videoCid, videoTitle)
            console.log("native detail perf: feed cid reused", videoBvid, videoCid)
        }
        videoDetail.load(videoBvid)
        updatePlayerSurface()
        wasInlinePlaying = inlinePlaying
        showInlineControls()
    }
    Component.onDestruction: playbackSession.releaseSurface(inlineVideoHost)
    onWantsPlaybackSurfaceChanged: updatePlayerSurface()
    onStatusChanged: {
        synchronizeInlineControls()
        if (status === PageStatus.Active) {
            initialPlaybackTimer.restart()
            resumeSupplementaryContent(compactRestorePending
                                       ? "compact-restore" : "page-active")
        }
    }
    onInlineTransportAvailableChanged: console.log(
        "native detail controls: transport available",
        inlineTransportAvailable,
        "loading", inlinePlayerLoading,
        "duration", Math.round(playbackSession.duration))
    onInlinePlayerLoadingChanged: {
        if (!inlinePlayerLoading && inlineTransportAvailable) {
            console.log("native detail controls: ready",
                        "loading", false,
                        "pauseVisible", inlinePauseButton.visible,
                        "fullscreenVisible", inlineFullscreenButton.visible,
                        "duration", Math.round(playbackSession.duration))
        }
    }

    // Keep the PageStack transition responsive: only detail + first playback
    // are allowed during page entry. Comments, recommendations, and Danmaku are
    // lazy/staggered so their JSON parsing and delegate/image creation cannot
    // compete with the transition and first video frame.
    Timer {
        id: initialPlaybackTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (page.status !== PageStatus.Active) {
                restart()
                return
            }
            if (pendingAutoplayCid.length > 0 && !isCurrentVideo)
                openPlayer(pendingAutoplayCid, pendingAutoplayTitle)
        }
    }
    Timer {
        id: supplementaryFallbackTimer
        interval: 3800
        repeat: false
        onTriggered: markPlaybackSettled("fallback")
    }
    Timer {
        id: playbackSettledTimer
        interval: 1400
        repeat: false
        onTriggered: markPlaybackSettled("playing")
    }
    Timer {
        id: detailRevealTimer
        interval: 140
        repeat: true
        onTriggered: {
            if (page.status !== PageStatus.Active)
                return
            var maxParts = Math.min(videoDetail.pages.length, 8)
            if (visibleDetailStage < 4) {
                ++visibleDetailStage
                return
            }
            if (visiblePartCount < maxParts) {
                ++visiblePartCount
                return
            }
            stop()
        }
    }
    Timer {
        id: commentLoadTimer
        // Keep initial metadata work away from the first decoded seconds. On
        // the phone, comment and recommendation JSON completing together was
        // enough to pull one 1080P60 presentation window below 45 FPS.
        interval: 3000
        repeat: false
        onTriggered: {
            if (page.status === PageStatus.Active) {
                requestComments("lazy")
            } else {
                commentsScheduled = false
            }
        }
    }
    Timer {
        id: commentRevealTimer
        interval: 320
        repeat: true
        onTriggered: {
            var target = Math.min(maxPreviewComments, commentModel.count)
            if (page.status !== PageStatus.Active || visibleCommentCount >= target) {
                stop()
                return
            }
            ++visibleCommentCount
            reportCompactRestoreContentReady()
        }
    }
    Timer {
        id: danmakuLoadTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (pendingDanmakuCid.length > 0 && page.status === PageStatus.Active) {
                console.log("native detail perf: loading delayed danmaku")
                danmakuModel.load(pendingDanmakuCid)
            }
        }
    }
    Timer {
        id: relatedLoadTimer
        // Stagger this from comments and danmaku so GUI-thread model updates
        // cannot all land in one frame-floor window.
        interval: 7000
        repeat: false
        onTriggered: {
            if (page.status === PageStatus.Active) {
                requestRelated("lazy")
            } else {
                relatedScheduled = false
            }
        }
    }
    Timer {
        id: relatedRevealTimer
        interval: 420
        repeat: true
        onTriggered: {
            var target = Math.min(maxPreviewRelated, relatedModel.count)
            if (page.status !== PageStatus.Active || visibleRelatedCount >= target) {
                stop()
                return
            }
            ++visibleRelatedCount
            reportCompactRestoreContentReady()
        }
    }

    Connections {
        target: videoDetail
        onChanged: {
            if (videoDetail.aid.length > 0)
                playbackSession.setVideoAid(page.videoBvid, videoDetail.aid)
            if (videoDetail.pages.length > 0)
                playbackSession.setVideoParts(page.videoBvid, videoDetail.pages)
            if (!videoDetail.loading && !detailReady) {
                detailReady = true
                visibleDetailStage = 0
                visiblePartCount = 0
                detailRevealTimer.restart()
                console.log("native detail perf: detail ready")
                maybeLoadSupplementaryContent()
                ensureCompactRestoreContent()
            }
            if (videoDetail.firstCid.length > 0 && !initialPlaybackRequested) {
                initialPlaybackRequested = true
                if (!isCurrentVideo)
                    requestAutoplay(videoDetail.firstCid, videoDetail.title)
            }
        }
    }

    Connections {
        target: playbackSession
        onChanged: {
            synchronizeInlineControls()
            if (isCurrentVideo && playbackSession.playing && !playbackSettled
                    && !playbackSettledTimer.running)
                playbackSettledTimer.restart()
            if (nativeTestContentMode === "system-volume-gesture"
                    && isCurrentVideo && playbackSession.playing
                    && page.video.presentedFrameSerial > 0
                    && !page.systemVolumeRegressionStopScheduled) {
                page.systemVolumeRegressionStopScheduled = true
                page.reportInlineGestureGeometry("system-volume-ready")
                systemVolumeRegressionStopTimer.restart()
                console.log("native system controls regression: gesture window ready",
                            "restoreDelayMs", systemVolumeRegressionStopTimer.interval)
            }
        }
    }

    Timer {
        id: systemVolumeRegressionStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            playbackSession.stop()
            console.log("native system controls regression: playback stopped for restore")
        }
    }

    Connections {
        target: commentModel
        onStateChanged: {
            if (!commentModel.loading && commentModel.count > visibleCommentCount
                    && !commentRevealTimer.running)
                commentRevealTimer.restart()
            reportCompactRestoreContentReady()
        }
    }

    Connections {
        target: relatedModel
        onStateChanged: {
            if (!relatedModel.loading && relatedModel.count > visibleRelatedCount
                    && !relatedRevealTimer.running)
                relatedRevealTimer.restart()
            reportCompactRestoreContentReady()
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            synchronizeInlineControls()
            updatePlayerSurface()
        }
    }

    DisplayBlanking {
        preventBlanking: inlinePlaying
    }

    PageHeader {
        id: fixedHeader
        anchors.top: parent.top
        width: parent.width
        title: qsTr("视频详情")
        description: videoBvid
    }

    Item {
        id: inlinePlayer
        anchors.top: fixedHeader.bottom
        anchors.left: parent.left
        width: page.landscapeLayout ? page.landscapePlayerWidth : parent.width
        height: page.landscapeLayout
                ? Math.max(1, page.height - fixedHeader.height)
                : Math.min(width * 9 / 16, page.height * 0.52)

        Rectangle { anchors.fill: parent; color: "black" }
        Image {
            id: inlineLoadingCover
            anchors.fill: parent
            // Keep the selected video's cover in front of the black player
            // host until the single mpv pipeline has decoded a real texture;
            // a new selection never exposes the previous frame or an empty
            // render target while software decoding starts.
            visible: !isCurrentVideo || playbackSession.loading
            source: videoDetail.cover || videoCover
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onVisibleChanged: console.log("native detail perf: loading cover",
                                          visible ? "visible" : "hidden",
                                          "loading", playbackSession.loading)
        }
        Item { id: inlineVideoHost; anchors.fill: parent }
        DanmakuOverlay {
            anchors.fill: parent
            active: page.status === PageStatus.Active
                    && isCurrentVideo
            z: 10
        }

        PlayerGestureArea {
            id: inlineGestures
            anchors.fill: parent
            z: 20
            controller: isCurrentVideo && inlinePlayerError.length === 0
                        ? playbackSession : null
            systemController: systemControls
            pressSpeedEnabled: inlinePlaybackReady
            onTapped: toggleInlineControls()
            onGestureStarted: {
                inlineControlsVisible = false
                inlineHideTimer.stop()
            }
            onInteraction: showInlineControls()
        }

        // A passive progress line stays visible after the playback controls
        // fade, so inline playback never loses its current-position feedback.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.paddingSmall
            visible: inlineTransportAvailable
            z: 25

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height / 2
                color: Theme.rgba("white", Theme.opacityLow)
            }
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height / 2
                width: parent.width * Math.max(0, Math.min(1,
                       playbackSession.position / Math.max(1, playbackSession.duration)))
                color: Theme.highlightColor
            }
        }

        Item {
            id: inlineControls
            anchors.fill: parent
            z: 30
            opacity: inlineControlsVisible ? 1.0 : 0.0
            visible: opacity > 0
            enabled: inlineControlsVisible

            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }

            IconButton {
                id: inlinePauseButton
                anchors.centerIn: parent
                visible: inlinePlayerError.length === 0
                icon.source: isCurrentVideo
                             ? (playbackSession.paused || playbackSession.ended
                                ? "image://theme/icon-l-play" : "image://theme/icon-l-pause")
                             : "image://theme/icon-l-play"
                onClicked: {
                    if (isCurrentVideo) {
                        if (playbackSession.ended) {
                            playbackSession.seek(0)
                            playbackSession.setPaused(false)
                        } else {
                            playbackSession.togglePaused()
                        }
                    } else {
                        openPlayer(videoDetail.firstCid, videoDetail.title)
                    }
                    showInlineControls()
                }
            }
            IconButton {
                id: inlineFullscreenButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingMedium
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.paddingMedium
                visible: isCurrentVideo && inlinePlayerError.length === 0
                icon.source: "image://theme/icon-m-scale"
                onClicked: openFullscreen()
                onVisibleChanged: if (visible) fullscreenGeometryTimer.restart()
            }

            Slider {
                anchors.left: parent.left
                anchors.leftMargin: inlineGestures.backSwipeCorridorWidth
                anchors.right: inlineFullscreenButton.left
                anchors.rightMargin: Theme.paddingSmall
                anchors.bottom: parent.bottom
                leftMargin: Theme.paddingMedium
                rightMargin: Theme.paddingMedium
                minimumValue: 0
                maximumValue: Math.max(1, playbackSession.duration)
                value: playbackSession.position
                valueText: formatTime(value) + " / " + formatTime(playbackSession.duration)
                visible: inlineTransportAvailable
                onPressed: inlineHideTimer.stop()
                onReleased: {
                    var nextPosition = value
                    playbackSession.seek(nextPosition)
                    value = Qt.binding(function() { return playbackSession.position })
                    showInlineControls()
                }
                onCanceled: {
                    value = Qt.binding(function() { return playbackSession.position })
                    showInlineControls()
                }
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            z: 28
            enabled: false
            running: inlinePlayerLoading
            size: BusyIndicatorSize.Large
        }

        Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            z: 40
            visible: inlinePlayerError.length > 0
            text: inlinePlayerError
            color: Theme.highlightColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }

    Timer {
        id: inlineHideTimer
        interval: 3200
        onTriggered: {
            if (inlinePlaying)
                inlineControlsVisible = false
        }
    }

    Timer {
        id: fullscreenGeometryTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (!inlineFullscreenButton.visible)
                return
            var point = inlineFullscreenButton.mapToItem(page, 0, 0)
            console.log("native detail perf: fullscreen button geometry",
                        "x", Math.round(point.x),
                        "y", Math.round(point.y),
                        "width", Math.round(inlineFullscreenButton.width),
                        "height", Math.round(inlineFullscreenButton.height))
        }
    }

    Timer {
        id: fullscreenRegressionTimer
        interval: 100
        repeat: true
        running: nativeTestContentMode === "fullscreen"
                 && page.status === PageStatus.Active
        property bool entered: false
        onTriggered: {
            if (entered || !isCurrentVideo || inlinePlayerLoading
                    || !inlineTransportAvailable)
                return
            entered = true
            stop()
            console.log("native player: deterministic fullscreen regression entry",
                        "bvid", videoBvid,
                        "quality", playbackSession.selectedQuality)
            openFullscreen()
        }
    }

    Timer {
        id: qualityMatrixRegressionTimer
        interval: 200
        repeat: true
        running: nativeTestContentMode === "quality-matrix"
                 && !page.qualityMatrixComplete
        onTriggered: {
            if (!page.isCurrentVideo || page.inlinePlayerLoading
                    || page.inlinePlayerError.length > 0
                    || page.video.presentedFrameSerial <= 0)
                return

            if (page.qualityMatrixIndex < 0) {
                var discovered = []
                for (var index = playbackSession.qualities.length - 1;
                     index >= 0; --index) {
                    var id = playbackSession.qualities[index].id
                    // 120/127 remain visible but are separately exercised by
                    // the UHD safety probe because this phone cannot allocate
                    // their real decoder surfaces without exhausting CMA.
                    if (id > 0 && id <= 116)
                        discovered.push(id)
                }
                if (discovered.length < 2)
                    return
                page.qualityMatrixIds = discovered
                page.qualityMatrixResolvedIds = []
                page.qualityMatrixIndex = 0
                console.log("native VOD quality matrix: catalog ready",
                            "ids", discovered.join(","),
                            "choices", playbackSession.qualities.length,
                            "initial", playbackSession.selectedQuality)
            }

            if (page.qualityMatrixAwaitingFrame) {
                if (page.video.loadSerial <= page.qualityMatrixPreviousLoadSerial
                        || playbackSession.selectedQuality
                           !== page.qualityMatrixRequestedId)
                    return
                page.qualityMatrixAwaitingFrame = false
                page.qualityMatrixSettledAtMs = Date.now()
                var resolved = page.qualityMatrixResolvedIds.slice(0)
                resolved.push(playbackSession.selectedQuality)
                page.qualityMatrixResolvedIds = resolved
                console.log("native VOD quality matrix: step ready",
                            "index", page.qualityMatrixIndex,
                            "requested", page.qualityMatrixRequestedId,
                            "resolved", playbackSession.selectedQuality,
                            "label", playbackSession.selectedQualityLabel,
                            "loadSerial", page.video.loadSerial,
                            "frameSerial", page.video.presentedFrameSerial,
                            "geometry", page.video.videoWidth + "x" + page.video.videoHeight)
                ++page.qualityMatrixIndex
                return
            }

            if (page.qualityMatrixSettledAtMs > 0
                    && Date.now() - page.qualityMatrixSettledAtMs < 1500)
                return
            if (page.qualityMatrixIndex >= page.qualityMatrixIds.length) {
                page.qualityMatrixComplete = true
                stop()
                console.log("native VOD quality matrix: complete",
                            "requested", page.qualityMatrixIds.join(","),
                            "resolved", page.qualityMatrixResolvedIds.join(","),
                            "loadSerial", page.video.loadSerial,
                            "frameSerial", page.video.presentedFrameSerial)
                // Finish through the production session stop path so the
                // final OMX generation participates in the same lifetime
                // audit as every preceding quality switch.
                playbackSession.stop()
                return
            }

            page.qualityMatrixRequestedId =
                    page.qualityMatrixIds[page.qualityMatrixIndex]
            if (playbackSession.selectedQuality
                    === page.qualityMatrixRequestedId) {
                var retained = page.qualityMatrixResolvedIds.slice(0)
                retained.push(playbackSession.selectedQuality)
                page.qualityMatrixResolvedIds = retained
                page.qualityMatrixSettledAtMs = Date.now()
                console.log("native VOD quality matrix: step ready",
                            "index", page.qualityMatrixIndex,
                            "requested", page.qualityMatrixRequestedId,
                            "resolved", playbackSession.selectedQuality,
                            "label", playbackSession.selectedQualityLabel,
                            "loadSerial", page.video.loadSerial,
                            "frameSerial", page.video.presentedFrameSerial,
                            "geometry", page.video.videoWidth + "x" + page.video.videoHeight,
                            "initialSession", true)
                ++page.qualityMatrixIndex
                return
            }

            page.qualityMatrixPreviousLoadSerial = page.video.loadSerial
            page.qualityMatrixAwaitingFrame = true
            console.log("native VOD quality matrix: step requested",
                        "index", page.qualityMatrixIndex,
                        "from", playbackSession.selectedQuality,
                        "to", page.qualityMatrixRequestedId,
                        "position", Math.round(playbackSession.position),
                        "loadSerial", page.video.loadSerial)
            playbackSession.requestQuality(page.qualityMatrixRequestedId)
        }
    }

    SilicaFlickable {
        id: detailFlickable
        anchors.top: page.landscapeLayout ? fixedHeader.bottom : inlinePlayer.bottom
        anchors.left: page.landscapeLayout ? inlinePlayer.right : parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentHeight: content.height
        onContentYChanged: markDetailExplored()
        onMovementEnded: markDetailExplored()
        onMovementStarted: markDetailExplored()
        PullDownMenu {
            MenuItem {
                text: accountService.loggedIn ? qsTr("发表评论") : qsTr("查看全部评论")
                enabled: videoDetail.aid.length > 0
                onClicked: accountService.loggedIn ? openCommentDialog() : openAllComments()
            }
            MenuItem {
                text: qsTr("查看全部评论（%1）").arg(commentModel.totalCount > 0 ? commentModel.totalCount : "…")
                enabled: videoDetail.aid.length > 0
                onClicked: openAllComments()
            }
            MenuItem {
                text: qsTr("全屏播放")
                enabled: videoDetail.firstCid.length > 0 || (playbackSession.active && playbackSession.bvid === videoBvid)
                onClicked: openFullscreen()
            }
            MenuItem {
                text: playbackSession.active && playbackSession.bvid === videoBvid ? qsTr("继续播放") : qsTr("页内播放")
                enabled: videoDetail.firstCid.length > 0
                onClicked: openPlayer(videoDetail.firstCid, videoDetail.title)
            }
        }
        Column {
            id: content; width: parent.width
            Item { width: 1; height: Theme.paddingLarge }
            Label { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: videoDetail.title || videoTitle; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeLarge, appSettings.fontSizeMode); wrapMode: Text.Wrap }
            BackgroundItem {
                width: parent.width
                height: ownerLabel.implicitHeight + 2 * Theme.paddingSmall
                visible: visibleDetailStage >= 1 && (videoDetail.owner.length > 0 || videoOwner.length > 0)
                onClicked: {
                    if (videoDetail.ownerMid.length > 0)
                        pageStack.push(Qt.resolvedUrl("AuthorSpacePage.qml"), {
                            authorMid: videoDetail.ownerMid,
                            initialName: videoDetail.owner || videoOwner
                        })
                }
                Label {
                    id: ownerLabel
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: (videoDetail.owner || videoOwner)
                          + (videoDetail.ownerMid.length > 0 ? qsTr(" · 查看 UP 主空间和动态 ›") : "")
                    color: parent.highlighted ? Theme.secondaryHighlightColor : Theme.highlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    truncationMode: TruncationMode.Fade
                }
            }
            Label { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: videoDetail.stats; color: Theme.secondaryColor; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode); wrapMode: Text.Wrap; visible: visibleDetailStage >= 2 }
            SectionHeader { text: qsTr("简介"); visible: visibleDetailStage >= 3 }
            Label { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: videoDetail.description || qsTr("加载中…"); color: Theme.secondaryColor; wrapMode: Text.Wrap; visible: visibleDetailStage >= 3 }
            SectionHeader { text: qsTr("分集") ; visible: visibleDetailStage >= 4 && videoDetail.pages.length > 1 }
            Repeater { model: videoDetail.pages.length > visiblePartCount ? videoDetail.pages.slice(0, visiblePartCount) : videoDetail.pages
                BackgroundItem {
                    width: content.width
                    visible: visibleDetailStage >= 4 && videoDetail.pages.length > 1
                    onClicked: openPlayer(modelData.cid, modelData.title)
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("P%1  %2").arg(modelData.page).arg(modelData.title)
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }
            SectionHeader {
                id: commentsSection
                text: commentModel.totalCount > 0 ? qsTr("评论 · %1 条").arg(commentModel.totalCount) : qsTr("评论")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: commentModel.totalCount > 0
                      ? qsTr("预览 %1 条主评论 / 共 %2 条（含回复），点按下方可查看全部")
                            .arg(commentRepeater.count).arg(commentModel.totalCount)
                      : commentModel.loading || commentsScheduled
                        ? qsTr("评论正在逐条载入，避免影响播放")
                        : qsTr("播放稳定后会按条数加载评论，避免和视频抢处理器")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: accountService.loggedIn ? qsTr("发表评论") : qsTr("登录后发表评论")
                enabled: accountService.loggedIn && !commentModel.posting
                onClicked: openCommentDialog()
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: commentModel.errorMessage.length > 0
                text: commentModel.errorMessage
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }
            Repeater {
                id: commentRepeater
                model: Math.min(visibleCommentCount, maxPreviewComments, commentModel.count)
                BackgroundItem {
                    id: commentItem
                    width: content.width
                    height: Math.max(avatarImage.height, commentColumn.height) + 2 * Theme.paddingLarge
                    // Depend on revision as well as the row index so a refresh
                    // updates the preview even when the row count stays stable.
                    property int modelRevision: commentModel.revision
                    property var commentData: {
                        var currentRevision = modelRevision
                        return commentModel.get(index)
                    }
                    property int repliesTotal: parseInt(commentData.replyCount) || 0

                    function openReplyThread() {
                        if (repliesTotal <= 0)
                            return
                        pageStack.push(Qt.resolvedUrl("ReplyThreadPage.qml"), {
                            commentAid: videoDetail.aid,
                            rootRpid: commentData.rpid,
                            rootAuthor: commentData.author,
                            rootAvatar: commentData.avatar,
                            rootMessage: commentData.messageText,
                            rootTime: commentData.commentTime,
                            rootLike: commentData.likeCount,
                            rootLiked: commentData.liked
                        })
                    }

                    onClicked: openReplyThread()

                    Rectangle {
                        id: avatarMask
                        x: Theme.horizontalPageMargin
                        y: Theme.paddingLarge
                        width: Theme.iconSizeMedium
                        height: width
                        radius: width / 2
                        color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                        clip: true

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: commentData.avatar
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    Column {
                        id: commentColumn
                        x: avatarMask.x + avatarMask.width + Theme.paddingMedium
                        y: Theme.paddingLarge
                        width: parent.width - x - Theme.horizontalPageMargin
                        spacing: Theme.paddingSmall

                        Label {
                            width: parent.width
                            text: commentData.pinned
                                  ? qsTr("置顶 · %1").arg(commentData.author)
                                  : commentData.author
                            color: Theme.highlightColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: commentData.messageText
                            font.pixelSize: appSettings.scaledFontSize(
                                                Theme.fontSizeSmall,
                                                appSettings.fontSizeMode)
                            wrapMode: Text.Wrap
                        }
                        Label {
                            width: parent.width
                            text: qsTr("%1  ·  赞 %2  ·  回复 %3")
                                  .arg(commentData.commentTime)
                                  .arg(commentData.likeCount)
                                  .arg(commentData.replyCount)
                            color: Theme.secondaryColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                        }
                        Row {
                            width: parent.width
                            spacing: Theme.paddingMedium
                            CommentActionButton {
                                iconSource: commentData.liked
                                            ? "image://theme/icon-m-like"
                                            : "image://theme/icon-m-outline-like"
                                label: commentData.likeCount > 0
                                       ? commentData.likeCount.toString()
                                       : qsTr("赞")
                                active: commentData.liked
                                enabled: accountService.loggedIn
                                         && !commentModel.actioning
                                onClicked: {
                                    console.log("native comment action: preview like control activated",
                                                "row", index,
                                                "rpid", commentData.rpid,
                                                "currentlyLiked", commentData.liked)
                                    commentModel.toggleLike(index)
                                }
                            }
                            CommentActionButton {
                                iconSource: "image://theme/icon-m-message-reply"
                                label: qsTr("回复")
                                enabled: accountService.loggedIn && !commentModel.posting
                                onClicked: openCommentReplyDialog(commentData.rpid,
                                                                  commentData.rpid,
                                                                  commentData.author)
                            }
                        }
                        Label {
                            width: parent.width
                            visible: commentItem.repliesTotal > 0
                            text: qsTr("查看全部 %1 条回复 ›").arg(commentItem.repliesTotal)
                            color: Theme.highlightColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                        }
                    }

                    ContextMenu {
                        MenuItem {
                            text: qsTr("查看 %1 条回复").arg(commentItem.repliesTotal)
                            enabled: commentItem.repliesTotal > 0
                            onClicked: commentItem.openReplyThread()
                        }
                        MenuItem {
                            text: commentData.liked ? qsTr("取消点赞") : qsTr("点赞")
                            enabled: accountService.loggedIn && !commentModel.actioning
                            onClicked: commentModel.toggleLike(index)
                        }
                        MenuItem {
                            text: qsTr("回复 @%1").arg(commentData.author)
                            enabled: accountService.loggedIn && !commentModel.posting
                            onClicked: openCommentReplyDialog(commentData.rpid,
                                                              commentData.rpid,
                                                              commentData.author)
                        }
                    }
                }
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: commentModel.loading || commentModel.posting
                         || commentModel.actioning
                size: BusyIndicatorSize.Medium
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: videoDetail.aid.length > 0
                text: commentModel.totalCount > 0
                      ? qsTr("查看全部 %1 条评论").arg(commentModel.totalCount)
                      : qsTr("查看全部评论")
                onClicked: openAllComments()
            }

            SectionHeader {
                id: relatedSection
                text: qsTr("相关推荐")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !relatedScheduled && !relatedModel.loading
                text: qsTr("继续下滑时再加载推荐，避免后台创建过多列表和图片")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }
            Repeater {
                id: relatedRepeater
                model: Math.min(visibleRelatedCount, relatedModel.count)
                BackgroundItem {
                    width: content.width
                    height: Theme.itemSizeHuge
                    property var relatedData: relatedModel.get(index)
                    onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                        videoTitle: relatedData.title,
                        videoOwner: relatedData.owner,
                        videoBvid: relatedData.bvid,
                        videoCover: relatedData.cover
                    })

                    Image {
                        id: relatedCover
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.36
                        height: width * 9 / 16
                        source: relatedData.cover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Column {
                        anchors.left: relatedCover.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall

                        Label {
                            width: parent.width
                            text: relatedData.title
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: relatedData.owner
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: qsTr("播放 %1").arg(relatedData.playCount)
                            color: Theme.secondaryColor
                            font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                        }
                    }
                }
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: relatedModel.loading
                size: BusyIndicatorSize.Medium
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
        BusyIndicator { anchors.centerIn: parent; running: videoDetail.loading; size: BusyIndicatorSize.Large }
        VerticalScrollDecorator {}
    }
}
