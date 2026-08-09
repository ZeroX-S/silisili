import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("二维码登录") }
            ViewPlaceholder {
                enabled: true
                text: qsTr("系统缺少二维码生成组件")
                hintText: qsTr("当前设备需要 Sailfish OS 5.1 的系统分享二维码组件。现有账户和稳定版配置没有被修改。")
            }
        }
    }
}
