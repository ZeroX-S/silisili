import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property bool landscapeLayout: width > height
    property int tileColumns: landscapeLayout ? 2 : 1
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "account"
        columns: page.tileColumns
    }

    Component.onCompleted: console.log("native account page: ready loggedIn", accountService.loggedIn)

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: {
            var point = historyTile.mapToItem(page, 0, 0)
            console.log("native account page: history tile geometry",
                        "x", Math.round(point.x), "y", Math.round(point.y),
                        "width", Math.round(historyTile.width),
                        "height", Math.round(historyTile.height),
                        "pageWidth", Math.round(page.width),
                        "pageHeight", Math.round(page.height))
        }
    }

    function openQrLogin() {
        console.log("native account: opening QR login page")
        pageStack.push(Qt.resolvedUrl("QrLoginPage.qml"))
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: accountService.loggedIn ? qsTr("更换账户（二维码）") : qsTr("二维码登录")
                onClicked: openQrLogin()
            }
            MenuItem { text: qsTr("刷新账户状态"); onClicked: accountService.refresh() }
        }
        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("账户")
                description: accountService.loggedIn ? accountService.userId : qsTr("未登录")
            }

            Item {
                width: parent.width
                height: accountService.loggedIn ? Theme.itemSizeHuge + Theme.paddingLarge : Theme.paddingLarge

                AvatarImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.itemSizeHuge
                    height: width
                    visible: accountService.loggedIn && accountService.avatar.length > 0
                    source: accountService.avatar
                    debugContext: "account"
                }
            }

            AppLabel {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: accountService.loggedIn ? accountService.userName : qsTr("当前没有可用登录会话")
                font.pixelSize: appSettings.scaledFontSize(accountService.loggedIn
                                                           ? Theme.fontSizeLarge
                                                           : Theme.fontSizeMedium, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                truncationMode: TruncationMode.Fade
            }

            AppLabel {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: accountService.loggedIn ? accountService.levelText : qsTr("可使用哔哩哔哩客户端扫码登录")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                truncationMode: TruncationMode.Fade
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: accountService.loggedIn ? qsTr("更换账户") : qsTr("二维码登录")
                onClicked: openQrLogin()
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: accountService.loggedIn
                text: qsTr("退出原生开发版")
                onClicked: pageStack.push(Qt.resolvedUrl("LogoutDialog.qml"))
            }

            SectionHeader { text: qsTr("我的内容") }
            Grid {
                width: parent.width
                columns: page.tileColumns
                NavigationTile {
                    id: historyTile
                    width: parent.width / page.tileColumns
                    title: qsTr("历史记录")
                    description: accountService.loggedIn ? qsTr("继续看最近播放的内容") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "history", pageTitle: qsTr("历史记录")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("我的收藏")
                    description: accountService.loggedIn ? qsTr("收藏夹与其中的视频") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "favorites", pageTitle: qsTr("我的收藏")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("我的订阅")
                    description: accountService.loggedIn ? qsTr("订阅的收藏夹与视频合集") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "subscriptions", pageTitle: qsTr("我的订阅")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("我的追番")
                    description: accountService.loggedIn ? qsTr("已追番剧与观看进度") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "anime", pageTitle: qsTr("我的追番")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("我的追剧")
                    description: accountService.loggedIn ? qsTr("已追影视与观看进度") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "cinema", pageTitle: qsTr("我的追剧")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("稍后再看")
                    description: accountService.loggedIn ? qsTr("保存待看的视频") : qsTr("登录后查看")
                    enabled: accountService.loggedIn
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountLibraryPage.qml"), {
                        contentMode: "later", pageTitle: qsTr("稍后再看")
                    })
                }
            }

            BackgroundItem {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: accountError.visible ? accountError.implicitHeight + 2 * Theme.paddingMedium : 0
                visible: accountService.errorMessage.length > 0
                enabled: false

                AppLabel {
                    id: accountError
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.paddingMedium
                    }
                    text: accountService.errorMessage
                    color: Theme.highlightColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            SectionHeader { text: qsTr("配置迁移") }
            AppLabel {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("稳定版配置快照：%1。读取过程不会修改稳定版配置。").arg(configMigrationState)
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
            }
        }
        BusyIndicator { anchors.centerIn: parent; running: accountService.loading; size: BusyIndicatorSize.Large }
        VerticalScrollDecorator {}
    }
}
