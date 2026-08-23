import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    id: page
    property bool settingsControlsReady: false
    allowedOrientations: Orientation.All

    Component.onCompleted: settingsControlsReady = true

    function selectMode(mode) {
        systemPipController.setBackgroundPlaybackMode(mode)
        console.log("native background presentation: settings selection handled",
                    "mode", mode,
                    "stored", systemPipController.backgroundPlaybackMode)
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: {
            var coverPoint = coverChoice.mapToItem(page, 0, 0)
            var pipPoint = pipChoice.mapToItem(page, 0, 0)
            console.log("native background presentation: choice geometry",
                        "coverX", Math.round(coverPoint.x),
                        "coverY", Math.round(coverPoint.y),
                        "coverWidth", Math.round(coverChoice.width),
                        "coverHeight", Math.round(coverChoice.height),
                        "pipX", Math.round(pipPoint.x),
                        "pipY", Math.round(pipPoint.y),
                        "pipWidth", Math.round(pipChoice.width),
                        "pipHeight", Math.round(pipChoice.height))
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: qsTr("播放与显示")
                description: qsTr("列表、页内小窗与后台播放")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("两种方式共用当前视频纹理和同一套解码，不会同时绘制。切换设置不会重新加载或重新定位视频。")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("后台显示方式") }

            BackgroundItem {
                id: coverChoice
                width: parent.width
                height: Theme.itemSizeHuge
                highlighted: systemPipController.backgroundPlaybackMode === "cover"
                onClicked: page.selectMode("cover")

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: selectedCover.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2
                    Label {
                        width: parent.width
                        text: qsTr("在 Cover 中播放")
                        color: coverChoice.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode)
                    }
                    Label {
                        width: parent.width
                        text: qsTr("进入主屏后，应用 Cover 显示实时视频画面")
                        color: Theme.secondaryColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    id: selectedCover
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.paddingLarge
                    height: width
                    radius: width / 2
                    border.width: 2
                    border.color: Theme.highlightColor
                    color: coverChoice.highlighted ? Theme.highlightColor : "transparent"
                }
            }

            BackgroundItem {
                id: pipChoice
                width: parent.width
                height: Theme.itemSizeHuge
                highlighted: systemPipController.backgroundPlaybackMode === "pip"
                enabled: systemPipController.available
                onClicked: page.selectMode("pip")

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: selectedPip.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2
                    Label {
                        width: parent.width
                        text: qsTr("在系统小窗中播放")
                        color: pipChoice.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode)
                    }
                    Label {
                        width: parent.width
                        text: systemPipController.available
                              ? qsTr("离开应用后显示可拖动小窗；点按小窗返回播放页")
                              : qsTr("当前系统未提供 Lipstick 小窗表面")
                        color: Theme.secondaryColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    id: selectedPip
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.paddingLarge
                    height: width
                    radius: width / 2
                    border.width: 2
                    border.color: Theme.highlightColor
                    color: pipChoice.highlighted ? Theme.highlightColor : "transparent"
                    opacity: pipChoice.enabled ? 1.0 : Theme.opacityLow
                }
            }

            SectionHeader { text: qsTr("应用内显示") }

            TextSwitch {
                width: parent.width
                text: qsTr("离开播放页后继续小窗播放")
                description: checked
                             ? qsTr("切换到应用内其他页面时保留可拖动视频小窗")
                             : qsTr("离开播放页时停止当前播放并释放视频资源")
                checked: appSettings.continueInAppMiniPlayer
                onCheckedChanged: {
                    if (page.settingsControlsReady)
                        appSettings.continueInAppMiniPlayer = checked
                }
            }

            SectionHeader { text: qsTr("内容列表") }

            ComboBox {
                width: parent.width
                label: qsTr("视频和直播列表")
                currentIndex: appSettings.contentColumns === 2 ? 1 : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("单列") }
                    MenuItem { text: qsTr("双列") }
                }
                onCurrentIndexChanged: {
                    if (page.settingsControlsReady)
                        appSettings.contentColumns = currentIndex === 1 ? 2 : 1
                }
            }

            SectionHeader { text: qsTr("字号") }

            ComboBox {
                width: parent.width
                label: qsTr("整体字号")
                currentIndex: appSettings.fontSizeMode
                menu: ContextMenu {
                    MenuItem { text: qsTr("小") }
                    MenuItem { text: qsTr("中") }
                    MenuItem { text: qsTr("大") }
                }
                onCurrentIndexChanged: {
                    if (page.settingsControlsReady)
                        appSettings.fontSizeMode = currentIndex
                }
            }

            SectionHeader { text: qsTr("播放手势") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("全屏播放时，左侧上下滑动调整系统全局亮度，右侧上下滑动调整系统媒体音量；应用会在播放开始保存原值，并在播放结束、停止或退出时恢复。")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("行为说明") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("锁屏、熄屏、停止播放或视频自然结束时，小窗会立即隐藏。系统小窗通过 Lipstick notification 表面显示，不会录制屏幕内容。")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }
        }

        VerticalScrollDecorator {}
    }
}
