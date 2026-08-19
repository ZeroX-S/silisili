import QtQuick 2.2

Item {
    id: root
    property Item target
    property string pageName
    property int columns: 1
    property real primaryExtent: target ? target.width : 0
    property real secondaryExtent: 0
    property bool landscape: target ? target.width > target.height : false

    width: 0
    height: 0
    visible: false

    function schedule() {
        geometryTimer.restart()
    }

    function report() {
        if (!target || target.width <= 0 || target.height <= 0)
            return
        console.log("native layout: page", pageName,
                    "orientation", landscape ? "landscape" : "portrait",
                    "width", Math.round(target.width),
                    "height", Math.round(target.height),
                    "columns", columns,
                    "primary", Math.round(primaryExtent),
                    "secondary", Math.round(secondaryExtent))
    }

    Component.onCompleted: schedule()
    onColumnsChanged: schedule()

    Connections {
        target: root.target
        onWidthChanged: root.schedule()
        onHeightChanged: root.schedule()
    }

    Timer {
        id: geometryTimer
        interval: 180
        repeat: false
        onTriggered: root.report()
    }
}
