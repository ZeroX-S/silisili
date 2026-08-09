import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property bool landscapeLayout: width > height
    property real landscapePlayerWidth: Math.round(width * 0.64)
    property string seasonId
    property string episodeId
    property string initialTitle
    property string initialCover
    property bool historyResumeRequested: false
    property real historyResumePosition: 0
    property bool historyResumeConsumed: false
    property var selectedEpisode: null
    property string selectedAid: selectedEpisode && selectedEpisode.aid ? selectedEpisode.aid : ""
    property string selectedBvid: selectedEpisode && selectedEpisode.bvid ? selectedEpisode.bvid : ""
    property string selectedCid: selectedEpisode && selectedEpisode.cid ? selectedEpisode.cid : ""
    property string selectedEpId: selectedEpisode && selectedEpisode.epId ? selectedEpisode.epId : ""
    property string selectedTitle: selectedEpisode && selectedEpisode.title ? selectedEpisode.title : ""
    property bool inlineControlsVisible: true
    property bool wasInlinePlaying: false
    property bool initialPlaybackRequested: false
    property string pendingDanmakuCid
    property bool retainedByDialog: pageStack.currentPage
                                    && pageStack.currentPage !== page
                                    && typeof pageStack.currentPage.playbackSurfaceOwner !== "undefined"
                                    && pageStack.currentPage.playbackSurfaceOwner === page
    property bool inlinePlayerLoading: isCurrentEpisode() && playbackSession.loading
                                       && playbackSession.errorMessage.length === 0
    property string inlinePlayerError: isCurrentEpisode() ? playbackSession.errorMessage : ""
    property bool inlinePlaybackReady: isCurrentEpisode() && !inlinePlayerLoading
                                        && inlinePlayerError.length === 0
                                        && playbackSession.duration > 0
    property bool inlinePlaying: Qt.application.active && status === PageStatus.Active
                                 && isCurrentEpisode() && playbackSession.playing
    property bool wantsPlaybackSurface: (status === PageStatus.Active || retainedByDialog)
                                        && playbackSession.active
                                        && selectedCid.length > 0
                                        && playbackSession.cid === selectedCid
    allowedOrientations: Orientation.All

    PgcDetailModel { id: pgcDetail }

    ResponsivePageMetrics {
        target: page
        pageName: "pgc-detail"
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

    function isCurrentEpisode() {
        return playbackSession.active && selectedCid.length > 0
               && playbackSession.cid === selectedCid
    }

    function selectEpisode(episode, playNow) {
        if (!episode || !episode.cid)
            return
        selectedEpisode = episode
        if (playNow)
            playSelected()
    }

    function playSelected() {
        if (!selectedEpisode || selectedCid.length === 0)
            return
        playbackSession.claimSurface(inlineVideoHost)
        var useHistoryResume = historyResumeRequested && !historyResumeConsumed
                               && (episodeId.length === 0 || selectedEpId === episodeId)
        if (useHistoryResume) {
            historyResumeConsumed = true
            var startPosition = Math.max(0, historyResumePosition)
            console.log("native history resume: detail accepted",
                        "kind", "pgc", "episodeId", selectedEpId,
                        "cid", selectedCid,
                        "position", Math.round(startPosition))
            playbackSession.playPgcAt(selectedAid, selectedBvid, selectedCid, selectedEpId,
                                      (pgcDetail.title || initialTitle) + " · " + selectedTitle,
                                      selectedEpisode.cover || pgcDetail.cover || initialCover,
                                      startPosition, 80)
        } else {
            playbackSession.playPgc(selectedAid, selectedBvid, selectedCid, selectedEpId,
                                    (pgcDetail.title || initialTitle) + " · " + selectedTitle,
                                    selectedEpisode.cover || pgcDetail.cover || initialCover, 80)
        }
        pendingDanmakuCid = selectedCid
        danmakuLoadTimer.restart()
        updatePlayerSurface()
    }

    function openFullscreen() {
        if (!isCurrentEpisode())
            playSelected()
        if (playbackSession.active) {
            playbackSession.beginSurfaceTransition(inlineVideoHost)
            pageStack.push(Qt.resolvedUrl("PlayerPage.qml"))
        }
    }

    function restorePlaybackSurface() {
        return isCurrentEpisode()
    }

    function openComments() {
        if (selectedAid.length === 0)
            return
        pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
            commentAid: selectedAid,
            contentTitle: (pgcDetail.title || initialTitle) + " · " + selectedTitle
        })
    }

    function updatePlayerSurface() {
        if (wantsPlaybackSurface)
            playbackSession.claimSurface(inlineVideoHost)
        else
            playbackSession.releaseSurface(inlineVideoHost)
    }

    function showInlineControls() {
        inlineControlsVisible = true
        if (inlinePlaying)
            inlineHideTimer.restart()
        else
            inlineHideTimer.stop()
    }

    function toggleInlineControls() {
        if (!isCurrentEpisode() || inlinePlayerLoading || inlinePlayerError.length > 0
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
        if (!isCurrentEpisode() || inlinePlayerLoading || inlinePlayerError.length > 0
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

    Component.onCompleted: {
        if (seasonId.length > 0)
            pgcDetail.load(seasonId)
        else
            pgcDetail.loadEpisode(episodeId)
        updatePlayerSurface()
        wasInlinePlaying = inlinePlaying
        showInlineControls()
    }
    Component.onDestruction: playbackSession.releaseSurface(inlineVideoHost)
    onWantsPlaybackSurfaceChanged: updatePlayerSurface()
    onStatusChanged: {
        synchronizeInlineControls()
    }

    Timer {
        id: danmakuLoadTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (pendingDanmakuCid.length > 0)
                danmakuModel.load(pendingDanmakuCid)
        }
    }

    Connections {
        target: pgcDetail
        onChanged: {
            if (!pgcDetail.loading && pgcDetail.episodes.length > 0
                    && (!selectedEpisode || !selectedEpisode.cid)
                    && !initialPlaybackRequested) {
                initialPlaybackRequested = true
                var episode = pgcDetail.episodes[0]
                if (episodeId.length > 0) {
                    for (var requestedIndex = 0; requestedIndex < pgcDetail.episodes.length; ++requestedIndex) {
                        if (pgcDetail.episodes[requestedIndex].epId === episodeId) {
                            episode = pgcDetail.episodes[requestedIndex]
                            break
                        }
                    }
                }
                if (playbackSession.active) {
                    for (var index = 0; index < pgcDetail.episodes.length; ++index) {
                        if (pgcDetail.episodes[index].cid === playbackSession.cid) {
                            episode = pgcDetail.episodes[index]
                            break
                        }
                    }
                }
                selectEpisode(episode, !playbackSession.active
                              || playbackSession.cid !== episode.cid)
            }
        }
    }
    Connections {
        target: playbackSession
        onChanged: {
            synchronizeInlineControls()
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
        title: qsTr("番剧详情")
        description: pgcDetail.title || initialTitle
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
            anchors.fill: parent
            visible: !isCurrentEpisode()
            source: (selectedEpisode && selectedEpisode.cover) || pgcDetail.cover || initialCover
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Item { id: inlineVideoHost; anchors.fill: parent }
        DanmakuOverlay {
            anchors.fill: parent
            active: page.status === PageStatus.Active && isCurrentEpisode()
            z: 10
        }

        PlayerGestureArea {
            id: inlineGestures
            anchors.fill: parent
            z: 20
            controller: inlinePlaybackReady ? playbackSession : null
            pressSpeedEnabled: inlinePlaybackReady
            onTapped: toggleInlineControls()
            onGestureStarted: {
                inlineControlsVisible = false
                inlineHideTimer.stop()
            }
            onInteraction: showInlineControls()
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.paddingSmall
            visible: inlinePlaybackReady
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
                anchors.centerIn: parent
                visible: !inlinePlayerLoading && inlinePlayerError.length === 0
                icon.source: isCurrentEpisode()
                             ? (playbackSession.paused || playbackSession.ended
                                ? "image://theme/icon-l-play" : "image://theme/icon-l-pause")
                             : "image://theme/icon-l-play"
                onClicked: {
                    if (isCurrentEpisode()) {
                        if (playbackSession.ended) {
                            playbackSession.seek(0)
                            playbackSession.setPaused(false)
                        } else {
                            playbackSession.togglePaused()
                        }
                    } else {
                        playSelected()
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
                visible: isCurrentEpisode() && !inlinePlayerLoading
                         && inlinePlayerError.length === 0
                icon.source: "image://theme/icon-m-scale"
                onClicked: openFullscreen()
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
                visible: inlinePlaybackReady
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
            z: 40
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

    SilicaFlickable {
        id: detailFlickable
        anchors.top: page.landscapeLayout ? fixedHeader.bottom : inlinePlayer.bottom
        anchors.left: page.landscapeLayout ? inlinePlayer.right : parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentHeight: detailColumn.height

        PullDownMenu {
            MenuItem {
                text: accountService.loggedIn ? qsTr("评论与发表") : qsTr("查看全部评论")
                enabled: selectedAid.length > 0
                onClicked: accountService.loggedIn
                           ? pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), {
                                 commentAid: selectedAid,
                                 contentTitle: (pgcDetail.title || initialTitle) + " · " + selectedTitle
                             })
                           : openComments()
            }
            MenuItem {
                text: qsTr("全屏播放")
                enabled: selectedCid.length > 0
                onClicked: openFullscreen()
            }
            MenuItem {
                text: isCurrentEpisode() ? qsTr("继续页内播放") : qsTr("页内播放当前分集")
                enabled: selectedCid.length > 0
                onClicked: isCurrentEpisode() ? updatePlayerSurface() : playSelected()
            }
        }

        Column {
            id: detailColumn
            width: parent.width
            Item { width: 1; height: Theme.paddingLarge }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: pgcDetail.title || initialTitle
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.Wrap
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: selectedTitle.length > 0
                text: selectedTitle
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: pgcDetail.ratingText
                      + (pgcDetail.ratingText.length > 0 && pgcDetail.stats.length > 0 ? "\n" : "")
                      + pgcDetail.stats
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            SectionHeader {
                text: pgcDetail.episodes.length > 0
                      ? qsTr("分集 · %1").arg(pgcDetail.episodes.length)
                      : qsTr("分集")
            }
            Repeater {
                model: pgcDetail.episodes.length > 6 ? pgcDetail.episodes.slice(0, 6) : pgcDetail.episodes
                BackgroundItem {
                    width: detailColumn.width
                    onClicked: selectEpisode(modelData, true)
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        text: modelData.title
                        color: modelData.cid === selectedCid || parent.highlighted
                               ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }
            BackgroundItem {
                width: detailColumn.width
                visible: pgcDetail.episodes.length > 6
                onClicked: pageStack.push(Qt.resolvedUrl("PgcEpisodePage.qml"), {
                    episodes: pgcDetail.episodes,
                    detailPage: page,
                    seasonTitle: pgcDetail.title || initialTitle,
                    selectedCid: page.selectedCid
                })
                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("查看全部 %1 集 ›").arg(pgcDetail.episodes.length)
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            SectionHeader { text: qsTr("评论") }
            BackgroundItem {
                width: detailColumn.width
                enabled: selectedAid.length > 0
                onClicked: openComments()
                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: qsTr("查看当前分集的全部评论并参与讨论 ›")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("播放会继续留在应用内小窗，可一边观看一边浏览或发表评论。")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("简介") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: pgcDetail.description || qsTr("加载中…")
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: pgcDetail.errorMessage.length > 0
                text: pgcDetail.errorMessage
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }
            Item { width: 1; height: Theme.paddingLarge }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: pgcDetail.loading
            size: BusyIndicatorSize.Large
        }
        VerticalScrollDecorator {}
    }
}
