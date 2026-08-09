import QtQuick 2.2
import Sailfish.Silica 1.0
import cn.silisili.native.models 1.0
import "../components"

Page {
    id: page
    property string contentMode
    property string pageTitle
    property string folderId
    property int folderType: 1
    property bool initialized: false
    allowedOrientations: Orientation.All

    AccountLibraryModel {
        id: libraryModel
        mode: page.contentMode
        collectionId: page.folderId
        collectionType: page.folderType
    }

    ResponsivePageMetrics {
        target: page
        pageName: "account-library-" + page.contentMode
        columns: 1
    }

    function openItem(item) {
        if (item.folderId.length > 0) {
            pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                contentMode: "collection",
                pageTitle: item.title,
                folderId: item.folderId,
                folderType: item.folderType
            })
        } else if (item.bvid.length > 0) {
            console.log("native history resume: route requested",
                        "kind", "video", "bvid", item.bvid,
                        "cid", item.cid,
                        "position", Math.round(item.resumePosition),
                        "enabled", page.contentMode === "history")
            pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), {
                videoBvid: item.bvid,
                videoCid: item.cid,
                videoTitle: item.title,
                videoOwner: item.owner,
                videoCover: item.cover,
                historyResumeRequested: page.contentMode === "history",
                historyResumePosition: item.resumePosition
            })
        } else if (item.seasonId.length > 0 || item.episodeId.length > 0) {
            console.log("native history resume: route requested",
                        "kind", "pgc", "episodeId", item.episodeId,
                        "cid", item.cid,
                        "position", Math.round(item.resumePosition),
                        "enabled", page.contentMode === "history")
            pageStack.push(Qt.resolvedUrl("PgcDetailPage.qml"), {
                seasonId: item.seasonId,
                episodeId: item.episodeId,
                initialTitle: item.title,
                initialCover: item.cover,
                historyResumeRequested: page.contentMode === "history",
                historyResumePosition: item.resumePosition
            })
        } else if (item.roomId.length > 0) {
            pageStack.push(Qt.resolvedUrl("LivePlayerPage.qml"), {
                roomId: item.roomId,
                roomTitle: item.title,
                roomOwner: item.owner
            })
        }
    }

    Component.onCompleted: {
        initialized = true
        libraryModel.refresh()
    }
    onContentModeChanged: if (initialized) libraryModel.refresh()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: libraryModel
        clip: true
        spacing: Theme.paddingSmall

        onContentYChanged: {
            if (libraryModel.hasMore && !libraryModel.loading
                    && contentY + height >= contentHeight - Theme.itemSizeHuge * 2)
                libraryModel.loadMore()
        }

        PullDownMenu {
            MenuItem { text: qsTr("刷新"); onClicked: libraryModel.refresh() }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: page.pageTitle
                description: !accountService.loggedIn ? qsTr("需要登录")
                             : list.count === 0 ? accountService.userName
                             : libraryModel.totalCount > list.count
                               && page.contentMode !== "history"
                               ? qsTr("%1 项").arg(libraryModel.totalCount)
                               : qsTr("已加载 %1 项").arg(list.count)
            }
        }

        delegate: BackgroundItem {
            id: card
            width: list.width
            height: Math.max(coverFrame.height, details.implicitHeight) + 2 * Theme.paddingMedium
            enabled: canOpen

            function openCurrent() {
                if (!canOpen)
                    return
                page.openItem({
                    title: title,
                    cover: cover,
                    owner: owner,
                    bvid: bvid,
                    cid: cid,
                    seasonId: seasonId,
                    episodeId: episodeId,
                    roomId: roomId,
                    folderId: folderId,
                    folderType: folderType,
                    resumePosition: resumePosition
                })
            }

            onClicked: openCurrent()

            Rectangle {
                id: coverFrame
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: Math.min(parent.width * 0.34, Theme.itemSizeHuge * 1.7)
                height: width * 9 / 16
                radius: Theme.paddingSmall / 2
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                clip: true

                Image {
                    anchors.fill: parent
                    source: cover
                    visible: cover.length > 0
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: width
                    sourceSize.height: height
                }
                Label {
                    anchors.centerIn: parent
                    visible: cover.length === 0
                    text: kindLabel.length > 0 ? kindLabel : qsTr("内容")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Theme.paddingSmall
                    visible: progressRatio >= 0
                    color: Theme.rgba("black", Theme.opacityLow)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, progressRatio))
                        height: parent.height
                        color: Theme.highlightColor
                    }
                }
            }

            Column {
                id: details
                anchors.left: coverFrame.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: coverFrame.verticalCenter
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    text: title
                    color: card.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    visible: subtitle.length > 0
                    text: subtitle
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    visible: progressText.length > 0 || badge.length > 0 || kindLabel.length > 0
                    text: (progressText.length > 0 ? progressText : kindLabel)
                          + (badge.length > 0 ? "  ·  " + badge : "")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    visible: !canOpen
                    text: qsTr("当前类型暂不支持打开")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }

        footer: Item {
            width: list.width
            height: libraryModel.loading || libraryModel.hasMore
                    ? Theme.itemSizeHuge : Theme.itemSizeLarge
            BusyIndicator {
                anchors.centerIn: parent
                running: libraryModel.loading && list.count > 0
                size: BusyIndicatorSize.Medium
            }
            Button {
                anchors.centerIn: parent
                visible: libraryModel.hasMore && !libraryModel.loading
                text: qsTr("加载更多")
                onClicked: libraryModel.loadMore()
            }
            Label {
                anchors.centerIn: parent
                visible: !libraryModel.loading && !libraryModel.hasMore && list.count > 0
                text: qsTr("已加载全部内容")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: libraryModel.loading && list.count === 0
            size: BusyIndicatorSize.Large
        }
        ViewPlaceholder {
            enabled: !libraryModel.loading && list.count === 0
            text: libraryModel.errorMessage.length > 0
                  ? libraryModel.errorMessage : qsTr("暂无内容")
            hintText: accountService.loggedIn ? qsTr("从顶部下拉可重试")
                                               : qsTr("请返回账户页登录")
        }
        VerticalScrollDecorator {}
    }
}
