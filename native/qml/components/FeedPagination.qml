import QtQuick 2.2

// Coalesce layout/model/scroll notifications into one event-loop turn. Fetch
// one viewport ahead, including after rotation and short first-page responses.
Item {
    id: root
    visible: false
    property var view
    property var feed
    property bool pageActive: false
    property bool loading: false
    property bool hasMore: false
    property int itemCount: 0
    property string errorMessage: ""

    function shouldLoadMore() {
        if (!pageActive || !Qt.application.active || !view || !feed
                || loading || !hasMore || itemCount <= 0 || errorMessage.length > 0
                || view.height <= 0 || view.contentHeight <= 0)
            return false
        var origin = typeof view.originY === "number" ? view.originY : 0
        return view.contentY + view.height * 2 >= origin + view.contentHeight
    }
    function schedule() { checkTimer.restart() }
    onPageActiveChanged: schedule()
    onLoadingChanged: schedule()
    onHasMoreChanged: schedule()
    onItemCountChanged: schedule()
    onErrorMessageChanged: schedule()
    Connections {
        target: root.view
        onContentYChanged: root.schedule()
        onContentHeightChanged: root.schedule()
        onHeightChanged: root.schedule()
    }
    Connections {
        target: Qt.application
        onStateChanged: root.schedule()
    }
    Timer {
        id: checkTimer
        interval: 0
        repeat: false
        onTriggered: if (root.shouldLoadMore()) root.feed.loadMore()
    }
}
