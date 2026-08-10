import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.player 1.0

CoverBackground {
    id: cover
    readonly property bool liveCoverVideo: systemPipController.backgroundPlaybackMode === "cover"

    // Settings uses a full-cover theme watermark. Keep the same quiet visual
    // hierarchy for SiliSili, but draw our own neutral diagonal texture rather
    // than reusing the Settings gear artwork.
    Item {
        id: idleWatermark
        anchors.fill: parent
        visible: !playbackSession.active
        clip: true

        Repeater {
            model: 12
            delegate: Rectangle {
                readonly property real diagonalWidth: Math.max(cover.width, cover.height) * 1.8
                width: diagonalWidth
                height: Math.max(2, Theme.paddingSmall / 2)
                x: (cover.width - width) / 2
                y: index * (cover.height / 8) - cover.height * 0.22
                rotation: -31
                transformOrigin: Item.Center
                color: Theme.rgba(Theme.highlightColor, Theme.opacityLow)
                opacity: 0.42
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium
        Item {
            id: idleArtwork
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, Theme.itemSizeHuge * 2.2)
            height: width * 9 / 16
            visible: !playbackSession.active

            Rectangle {
                anchors.fill: parent
                radius: Theme.paddingLarge
                color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityLow)
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor, Theme.opacityLow)
            }

            // The card sits above the diagonal watermark, retaining a small
            // brand anchor without competing with the native Cover backdrop.
            Rectangle {
                width: parent.width * 0.63
                height: parent.height * 0.63
                anchors.centerIn: parent
                radius: Theme.paddingMedium
                color: Theme.rgba(Theme.highlightColor, Theme.opacityLow)
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor, Theme.opacityLow)
            }
            Label {
                anchors.centerIn: parent
                text: "SiliSili"
                color: "white"
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.paddingMedium
                text: accountService.loggedIn ? qsTr("已登录 · 打开应用继续浏览")
                                               : qsTr("推荐 · 追番 · 直播")
                color: Theme.rgba("white", Theme.opacityHigh)
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
            }
        }
        Item {
            id: artwork
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: width * 9 / 16
            visible: playbackSession.active
            clip: true

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            // Mirror the persistent application-owned texture. The Cover does
            // not move, reload or seek the decoder and therefore cannot disturb
            // the foreground surface or the playback clock.
            MpvVideoMirrorItem {
                id: coverVideo
                anchors.fill: parent
                usage: "cover"
                // Disconnect the texture provider completely when system PiP
                // owns background presentation. Merely hiding this item still
                // lets an existing Cover scene graph request shared frames.
                source: cover.liveCoverVideo ? playbackVideo : null
                preserveAspectRatio: true
                visible: cover.liveCoverVideo
                         && playbackSession.active && !playbackSession.ended
            }

            // Keep artwork only while the selected source has not produced its
            // first frame. Once loading finishes, the mirror above is the real
            // moving video rather than a poster image.
            Image {
                anchors.fill: parent
                visible: playbackSession.cover.length > 0
                         && (!cover.liveCoverVideo || playbackSession.loading)
                source: playbackSession.cover
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Theme.rgba(Theme.highlightColor, Theme.opacityLow)
            }
        }
        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: playbackSession.active ? playbackSession.title : "SiliSili"; font.pixelSize: Theme.fontSizeLarge; color: Theme.highlightColor; wrapMode: Text.Wrap; maximumLineCount: 3; truncationMode: TruncationMode.Fade }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: playbackSession.active && playbackSession.mediaKind === "live"
                  ? qsTr("%1 · %2%3")
                    .arg(playbackSession.paused ? qsTr("直播已暂停") : qsTr("直播中"))
                    .arg(playbackSession.selectedQualityLabel)
                    .arg(cover.liveCoverVideo ? "" : qsTr(" · 系统小窗"))
                  : playbackSession.active
                  ? qsTr("%1 / %2 · %3%4")
                    .arg(Math.floor(playbackSession.position))
                    .arg(Math.floor(playbackSession.duration))
                    .arg(playbackSession.selectedQualityLabel)
                    .arg(cover.liveCoverVideo ? "" : qsTr(" · 系统小窗"))
                  : accountService.loggedIn
                    ? qsTr("从 Cover 操作或打开应用继续浏览")
                    : qsTr("下拉同步推荐，打开应用登录或观看")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
        }
    }
    CoverActionList {
        enabled: playbackSession.active
        CoverAction { iconSource: playbackSession.paused ? "image://theme/icon-cover-play" : "image://theme/icon-cover-pause"; onTriggered: playbackSession.togglePaused() }
        CoverAction {
            iconSource: "image://theme/icon-cover-cancel"
            onTriggered: playbackSession.stop()
        }
    }
    CoverActionList {
        enabled: !playbackSession.active
        CoverAction { iconSource: "image://theme/icon-cover-sync"; onTriggered: homeFeed.refresh() }
    }
}
