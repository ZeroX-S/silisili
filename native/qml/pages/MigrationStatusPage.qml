import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    property string featureName
    allowedOrientations: Orientation.All
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height
        Column {
            id: content; width: parent.width
            PageHeader { title: featureName }
            ViewPlaceholder { enabled: true; text: qsTr("正在迁移"); hintText: qsTr("稳定版实现继续保留，直到本页面通过真机功能验收") }
        }
    }
}
