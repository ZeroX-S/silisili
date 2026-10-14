import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"
import "../components/ImageUrls.js" as ImageUrls

Page {
    id: page
    property var episodes: []
    property var detailPage
    property string seasonTitle
    property string selectedCid
    allowedOrientations: Orientation.All

    SilicaListView {
        id: episodeList
        anchors.fill: parent
        model: episodes || []
        header: PageHeader {
            title: qsTr("全部分集")
            description: seasonTitle
        }
        delegate: BackgroundItem {
            width: episodeList.width
            height: Math.max(episodeCover.height, episodeText.implicitHeight) + 2 * Theme.paddingMedium
            onClicked: {
                if (detailPage)
                    detailPage.selectEpisode(modelData, true)
                pageStack.pop()
            }

            Image {
                id: episodeCover
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.32, Theme.itemSizeHuge * 1.5)
                height: width * 9 / 16
                sourceSize.width: Math.max(1, width)
                sourceSize.height: Math.max(1, height)
                source: ImageUrls.thumbnail(modelData.cover, width)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Column {
                id: episodeText
                anchors.left: episodeCover.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall

                AppLabel {
                    width: parent.width
                    text: modelData.title
                    color: modelData.cid === selectedCid || parent.parent.highlighted
                           ? Theme.highlightColor : Theme.primaryColor
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                }
                AppLabel {
                    width: parent.width
                    text: modelData.duration > 0
                          ? qsTr("时长 %1 分钟").arg(Math.max(1, Math.round(modelData.duration / 60)))
                          : qsTr("点按播放")
                    color: Theme.secondaryColor
                    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
