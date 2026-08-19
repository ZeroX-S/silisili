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
        pageName: "navigation"
        columns: page.tileColumns
    }

    Component.onCompleted: console.log("native navigation: page ready")

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: {
            var point = accountTile.mapToItem(page, 0, 0)
            console.log("native navigation: account tile geometry",
                        "x", Math.round(point.x), "y", Math.round(point.y),
                        "width", Math.round(accountTile.width),
                        "height", Math.round(accountTile.height),
                        "pageWidth", Math.round(page.width),
                        "pageHeight", Math.round(page.height))
            var videoPoint = videoDynamicTile.mapToItem(page, 0, 0)
            console.log("native navigation: dynamic tile geometry section video",
                        "x", Math.round(videoPoint.x), "y", Math.round(videoPoint.y),
                        "width", Math.round(videoDynamicTile.width),
                        "height", Math.round(videoDynamicTile.height))
            var nonVideoPoint = nonVideoDynamicTile.mapToItem(page, 0, 0)
            console.log("native navigation: dynamic tile geometry section nonvideo",
                        "x", Math.round(nonVideoPoint.x), "y", Math.round(nonVideoPoint.y),
                        "width", Math.round(nonVideoDynamicTile.width),
                        "height", Math.round(nonVideoDynamicTile.height))
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: qsTr("更多内容")
                description: qsTr("浏览与账户")
            }

            SectionHeader { text: qsTr("浏览内容") }

            Grid {
                width: parent.width
                columns: page.tileColumns
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("搜索")
                    description: qsTr("视频标题、UP 主或关键词")
                    onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("分区排行榜")
                    description: qsTr("动画、音乐、游戏、知识与影视")
                    onClicked: pageStack.push(Qt.resolvedUrl("RegionPage.qml"), {
                        regionId: 1,
                        regionTitle: qsTr("动画排行")
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("番剧与影视")
                    description: qsTr("番剧和影视内容")
                    onClicked: pageStack.push(Qt.resolvedUrl("PgcFeedPage.qml"))
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("直播")
                    description: qsTr("推荐直播间")
                    onClicked: pageStack.push(Qt.resolvedUrl("LiveFeedPage.qml"))
                }
            }

            SectionHeader { text: qsTr("我的") }

            Grid {
                width: parent.width
                columns: page.tileColumns
                NavigationTile {
                    id: videoDynamicTile
                    width: parent.width / page.tileColumns
                    title: qsTr("视频动态")
                    description: qsTr("关注 UP 主发布的视频")
                    onClicked: pageStack.push(Qt.resolvedUrl("DynamicPage.qml"), {
                        feedSection: "video"
                    })
                }
                NavigationTile {
                    id: nonVideoDynamicTile
                    width: parent.width / page.tileColumns
                    title: qsTr("图文与转发")
                    description: qsTr("图文、专栏、转发与其他非视频动态")
                    onClicked: pageStack.push(Qt.resolvedUrl("DynamicPage.qml"), {
                        feedSection: "nonvideo"
                    })
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("消息")
                    description: qsTr("回复、提及与收到的赞")
                    onClicked: pageStack.push(Qt.resolvedUrl("InboxPage.qml"))
                }
                NavigationTile {
                    id: accountTile
                    width: parent.width / page.tileColumns
                    title: qsTr("账户")
                    description: accountService.loggedIn
                                 ? accountService.userName : qsTr("登录与配置迁移")
                    onClicked: pageStack.push(Qt.resolvedUrl("AccountPage.qml"))
                }
            }

            SectionHeader { text: qsTr("应用") }

            Grid {
                width: parent.width
                columns: page.tileColumns
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("播放与显示")
                    description: qsTr("列表布局、页内小窗与后台显示")
                    onClicked: pageStack.push(Qt.resolvedUrl("PlaybackPresentationPage.qml"))
                }
                NavigationTile {
                    width: parent.width / page.tileColumns
                    title: qsTr("关于 silisili")
                    description: qsTr("版本、交互与兼容性说明")
                    onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
