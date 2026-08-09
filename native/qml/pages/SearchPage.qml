import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All

    ResponsivePageMetrics {
        target: page
        pageName: "search"
        columns: 1
    }

    SilicaListView {
        id: results
        anchors.fill: parent
        model: searchModel
        onAtYEndChanged: if (atYEnd && count > 0) searchModel.loadMore()
        PullDownMenu { MenuItem { text: qsTr("清除搜索历史"); enabled: searchModel.history.length > 0; onClicked: searchModel.clearHistory() } }
        header: Column {
            id: searchHeader
            width: results.width
            function showSearchKeyboard() {
                searchField.forceActiveFocus()
                if (searchField.openSoftwareInputPanel)
                    searchField.openSoftwareInputPanel()
                Qt.inputMethod.show()
                console.log("native search page: field focused")
            }
            Timer {
                interval: 250
                // Do not steal focus and resize the whole application merely
                // because SearchPage was opened behind a playing compact
                // window. The field still opens the keyboard on an explicit
                // tap, while passive page navigation keeps video cadence.
                running: searchModel.query.length === 0
                         && !playbackSession.compact
                repeat: false
                onTriggered: searchHeader.showSearchKeyboard()
            }
            PageHeader { title: qsTr("搜索") }
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("视频标题、UP 主或关键词")
                inputMethodHints: Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: { focus = false; searchModel.search(text) }
                onActiveFocusChanged: {
                    if (activeFocus)
                        Qt.inputMethod.show()
                }
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: searchHeader.showSearchKeyboard()
                }
            }
            SectionHeader { text: searchModel.query.length ? qsTr("“%1”的结果").arg(searchModel.query) : qsTr("输入关键词开始搜索") }
            Repeater {
                model: searchModel.query.length ? [] : searchModel.history
                BackgroundItem { width: results.width; Label { x: Theme.horizontalPageMargin; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor } onClicked: { searchField.text = modelData; searchModel.search(modelData) } }
            }
        }
        delegate: BackgroundItem {
            width: results.width
            // `cover` is a model URL, not an item.  Reading cover.height made
            // the delegate height NaN on real search results, which in turn
            // stacked labels on top of each other.
            height: Math.max(coverImage.height, labels.implicitHeight) + 2 * Theme.paddingMedium
            onClicked: pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { videoBvid: bvid, videoTitle: title, videoOwner: owner, videoCover: cover })
            Image {
                id: coverImage
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: Math.min(parent.width * 0.36, Theme.itemSizeHuge * 2.2)
                height: width * 9 / 16
                source: cover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: width
                sourceSize.height: height
            }
            Column { id: labels; anchors.left: coverImage.right; anchors.leftMargin: Theme.paddingMedium; anchors.right: parent.right; anchors.rightMargin: Theme.horizontalPageMargin; anchors.verticalCenter: coverImage.verticalCenter; spacing: Theme.paddingSmall
                Label { width: parent.width; text: title; wrapMode: Text.Wrap; maximumLineCount: 2; truncationMode: TruncationMode.Fade; color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor }
                Label { width: parent.width; text: owner; color: Theme.secondaryColor; truncationMode: TruncationMode.Fade }
                Label { width: parent.width; text: qsTr("播放 %1 · %2").arg(playCount).arg(duration); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor; truncationMode: TruncationMode.Fade }
            }
        }
        BusyIndicator { anchors.centerIn: parent; running: searchModel.loading; size: BusyIndicatorSize.Large }
        ViewPlaceholder { enabled: searchModel.errorMessage.length > 0; text: searchModel.errorMessage; hintText: qsTr("修改关键词后重试") }
        VerticalScrollDecorator {}
    }
}
