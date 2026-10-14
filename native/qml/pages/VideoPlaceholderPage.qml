import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    property string videoTitle
    property string videoOwner
    property string videoBvid
    property string videoCover
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height
        Column {
            id: content
            width: parent.width
            PageHeader { title: qsTr("视频详情"); description: videoBvid }
            Image { width: parent.width; height: width * 9 / 16; source: videoCover; fillMode: Image.PreserveAspectCrop }
            Item { width: 1; height: Theme.paddingLarge }
            AppLabel { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: videoTitle; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode); wrapMode: Text.Wrap }
            Item { width: 1; height: Theme.paddingMedium }
            AppLabel { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: videoOwner; color: Theme.secondaryColor; font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode) }
            SectionHeader { text: qsTr("迁移状态") }
            AppLabel { x: Theme.horizontalPageMargin; width: parent.width - 2 * Theme.horizontalPageMargin; text: qsTr("详情与播放器将在后续切片接入；本页用于验证原生 PageStack 与边缘滑动返回。") ; color: Theme.secondaryColor; wrapMode: Text.Wrap }
        }
        VerticalScrollDecorator {}
    }
}
