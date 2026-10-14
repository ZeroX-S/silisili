import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Dialog {
    allowedOrientations: Orientation.All

    canAccept: true
    onAccepted: accountService.logout()

    Column {
        width: parent.width
        DialogHeader {
            title: qsTr("退出登录")
            acceptText: qsTr("退出")
        }
        AppLabel {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            text: qsTr("只清除原生开发版自己的登录会话。稳定版 1.0.0-7 的配置和登录信息不会被修改。")
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
        }
    }
}
