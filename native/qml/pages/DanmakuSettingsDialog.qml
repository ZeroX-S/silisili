import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Dialog {
    allowedOrientations: Orientation.All
    property var playbackSurfaceOwner

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: settings.height

        Column {
            id: settings
            width: parent.width
            DialogHeader { title: qsTr("弹幕设置"); acceptText: qsTr("完成") }
            TextSwitch {
                text: qsTr("显示弹幕")
                checked: danmakuModel.enabled
                onCheckedChanged: danmakuModel.enabled = checked
            }
            Slider {
                width: parent.width
                label: qsTr("不透明度")
                minimumValue: 0.2
                maximumValue: 1.0
                stepSize: 0.1
                value: danmakuModel.opacity
                valueText: Math.round(value * 100) + "%"
                onReleased: danmakuModel.opacity = value
            }
            Slider {
                width: parent.width
                label: qsTr("字号")
                minimumValue: 0.6
                maximumValue: 1.8
                stepSize: 0.1
                value: danmakuModel.fontScale
                valueText: value.toFixed(1) + "×"
                onReleased: danmakuModel.fontScale = value
            }
            Slider {
                width: parent.width
                label: qsTr("速度")
                minimumValue: 0.5
                maximumValue: 2.0
                stepSize: 0.1
                value: danmakuModel.speed
                valueText: value.toFixed(1) + "×"
                onReleased: danmakuModel.speed = value
            }
            AppLabel {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: danmakuModel.loading ? qsTr("正在加载弹幕…")
                                           : qsTr("已加载 %1 条弹幕").arg(danmakuModel.count)
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
            }
        }
        VerticalScrollDecorator {}
    }
}
