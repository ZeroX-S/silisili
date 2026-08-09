import QtQuick 2.2
import Sailfish.Silica 1.0

Item {
    id: root
    property var qualities: []
    property int selectedQuality: -1
    property string title: qsTr("选择清晰度")
    signal qualitySelected(int quality)

    anchors.fill: parent
    visible: false
    enabled: visible
    z: 90

    function qualityIdList() {
        var ids = []
        for (var index = 0; index < qualities.length; ++index)
            ids.push(qualities[index].id)
        return ids.join(",")
    }

    function open() {
        visible = true
        selectedPositionTimer.restart()
        console.log("native player: quality picker opened",
                    "choices", qualities.length,
                    "ids", qualityIdList(),
                    "selected", selectedQuality)
    }

    function close() {
        visible = false
    }

    function positionSelectedQuality() {
        console.log("native player: quality picker layout",
                    "panelX", Math.round(panel.x),
                    "panelY", Math.round(panel.y),
                    "panelWidth", Math.round(panel.width),
                    "panelHeight", Math.round(panel.height),
                    "headerHeight", Math.round(header.height),
                    "listY", Math.round(qualityList.mapToItem(root, 0, 0).y),
                    "listHeight", Math.round(qualityList.height),
                    "rowHeight", Math.round(Theme.itemSizeMedium),
                    "scrollable", qualityList.contentHeight > qualityList.height)
        for (var index = 0; index < qualities.length; ++index) {
            if (qualities[index].id === selectedQuality) {
                qualityList.positionViewAtIndex(index, ListView.Contain)
                console.log("native player: quality picker selected positioned",
                            "index", index,
                            "contentY", Math.round(qualityList.contentY))
                return
            }
        }
        qualityList.positionViewAtBeginning()
        console.log("native player: quality picker positioned at beginning",
                    "selectedMissing", selectedQuality)
    }

    Timer {
        id: selectedPositionTimer
        interval: 0
        repeat: false
        onTriggered: root.positionSelectedQuality()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba("black", Theme.opacityLow)
        opacity: root.visible ? 1.0 : 0.0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height * 0.72,
                         header.height + Theme.itemSizeMedium * Math.min(4, Math.max(1, root.qualities.length))
                         + Theme.paddingMedium)
        color: Theme.rgba("black", Theme.opacityHigh)

        Column {
            anchors.fill: parent

            Item {
                id: header
                width: parent.width
                height: Theme.itemSizeMedium

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: closeButton.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                    truncationMode: TruncationMode.Fade
                }

                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-close"
                    onClicked: root.close()
                }
            }

            SilicaListView {
                id: qualityList
                width: parent.width
                height: parent.height - header.height
                clip: true
                model: root.qualities
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 1800
                maximumFlickVelocity: 5000
                onMovementStarted: console.log("native player: quality picker flick started",
                                               "contentY", Math.round(contentY),
                                               "contentHeight", Math.round(contentHeight),
                                               "viewportHeight", Math.round(height))
                onMovementEnded: console.log("native player: quality picker flick ended",
                                             "contentY", Math.round(contentY),
                                             "atBeginning", atYBeginning,
                                             "atEnd", atYEnd)

                delegate: BackgroundItem {
                    width: parent.width
                    height: Theme.itemSizeMedium
                    highlighted: root.selectedQuality === modelData.id
                    onClicked: {
                        console.log("native player: quality picker row selected",
                                    "id", modelData.id,
                                    "label", modelData.label,
                                    "index", index)
                        root.selectedQuality = modelData.id
                        root.qualitySelected(modelData.id)
                        root.close()
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * Theme.horizontalPageMargin
                               - selectedMark.width - Theme.paddingMedium
                        text: modelData.label
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Rectangle {
                        id: selectedMark
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.paddingMedium
                        height: width
                        radius: width / 2
                        color: Theme.highlightColor
                        visible: root.selectedQuality === modelData.id
                    }
                }

                VerticalScrollDecorator {}
            }
        }
    }
}
