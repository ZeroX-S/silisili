import QtQuick 2.2
import Sailfish.Silica 1.0

Dialog {
    id: dialog
    allowedOrientations: Orientation.All
    property var playbackSurfaceOwner
    property var qualities: []
    property int selectedQuality: -1
    property string selectedLabel

    canAccept: selectedQuality >= 0

    SilicaListView {
        id: qualityList
        anchors.fill: parent
        model: dialog.qualities
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 5000
        onMovementStarted: console.log("native player: quality dialog flick started",
                                       "contentY", Math.round(contentY),
                                       "contentHeight", Math.round(contentHeight),
                                       "viewportHeight", Math.round(height))
        onMovementEnded: console.log("native player: quality dialog flick ended",
                                     "contentY", Math.round(contentY),
                                     "atBeginning", atYBeginning,
                                     "atEnd", atYEnd)
        header: DialogHeader {
            title: qsTr("选择清晰度")
            acceptText: dialog.selectedLabel.length > 0 ? dialog.selectedLabel : qsTr("选择")
        }

        delegate: BackgroundItem {
            width: parent.width
            highlighted: dialog.selectedQuality === modelData.id
            onClicked: {
                console.log("native player: quality dialog row selected",
                            "id", modelData.id,
                            "label", modelData.label,
                            "index", index)
                dialog.selectedQuality = modelData.id
                dialog.selectedLabel = modelData.label
                dialog.accept()
            }

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.paddingMedium
                height: width
                radius: width / 2
                color: Theme.highlightColor
                visible: dialog.selectedQuality === modelData.id
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: {
        for (var index = 0; index < qualities.length; ++index) {
            if (qualities[index].id === selectedQuality) {
                qualityList.positionViewAtIndex(index, ListView.Contain)
                break
            }
        }
    }
}
