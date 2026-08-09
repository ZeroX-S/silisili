import QtQuick 2.2

Item {
    id: root
    property url source
    property string debugContext: "avatar"
    property int retryIndex: 0
    property bool terminalFailureLogged: false
    readonly property bool ready: image.status === Image.Ready
    readonly property string currentSource: candidateForRetry(retryIndex)

    function normalizedSource() {
        var value = String(source || "")
        if (value.indexOf("//") === 0)
            value = "https:" + value
        else if (value.indexOf("http://") === 0)
            value = "https://" + value.substring(7)
        return value
    }

    function optimizedSource() {
        var value = normalizedSource()
        if (value.length === 0 || value.indexOf("@") >= 0)
            return value
        var queryIndex = value.indexOf("?")
        var base = queryIndex >= 0 ? value.substring(0, queryIndex) : value
        var query = queryIndex >= 0 ? value.substring(queryIndex) : ""
        // Avatar originals are often multi-megabyte PNG/JPEG files. Ask the
        // image CDN for a small square WebP on the first attempt so a page does
        // not depend on a large original transfer before showing its author.
        return base + "@160w_160h_1c_1s.webp" + query
    }

    function candidateForRetry(index) {
        var value = optimizedSource()
        if (value.length === 0)
            return ""
        var match = value.match(/^https:\/\/i([0-2])\.hdslb\.com/)
        if (!match)
            return value
        // i0 is the primary cache key for every avatar; i1/i2 are bounded
        // failovers. This also lets identical avatars share one disk-cache URL
        // instead of starting from whichever CDN hostname happened to be in
        // an API response.
        var candidate = index % 3
        return value.replace(/^https:\/\/i[0-2]\.hdslb\.com/,
                             "https://i" + candidate + ".hdslb.com")
    }

    function currentHost() {
        var match = String(currentSource || "").match(/^https?:\/\/([^\/]+)/)
        return match ? match[1] : ""
    }

    onSourceChanged: {
        retryTimer.stop()
        loadWatchdog.stop()
        retryIndex = 0
        terminalFailureLogged = false
    }

    function reportExhausted(reason) {
        if (terminalFailureLogged)
            return
        terminalFailureLogged = true
        console.warn("native avatar: CDN retries exhausted",
                     "context", debugContext, "reason", reason,
                     normalizedSource())
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.currentSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: width
        sourceSize.height: height
        onStatusChanged: {
            if (status === Image.Loading)
                loadWatchdog.restart()
            else
                loadWatchdog.stop()
            if (status === Image.Error && root.currentSource.length > 0
                    && root.retryIndex < 2) {
                retryTimer.restart()
            } else if (status === Image.Error && root.currentSource.length > 0) {
                root.reportExhausted("network-error")
            } else if (status === Image.Ready) {
                root.terminalFailureLogged = false
                console.log("native avatar: ready",
                            "context", root.debugContext,
                            "host", root.currentHost(), "retry", root.retryIndex)
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 180 + root.retryIndex * 220
        repeat: false
        onTriggered: {
            if (root.retryIndex < 2) {
                ++root.retryIndex
                console.log("native avatar: retrying alternate CDN",
                            "context", root.debugContext,
                            "retry", root.retryIndex, root.currentSource)
            }
        }
    }

    Timer {
        id: loadWatchdog
        // Qt 5.6's image loader has no per-request transfer timeout. A stalled
        // CDN socket otherwise remains in Loading forever and never reaches
        // the alternate-host path.
        interval: 2600
        repeat: false
        onTriggered: {
            if (image.status !== Image.Loading || root.currentSource.length === 0)
                return
            if (root.retryIndex < 2) {
                ++root.retryIndex
                console.log("native avatar: retrying alternate CDN",
                            "context", root.debugContext,
                            "reason", "load-timeout",
                            "retry", root.retryIndex, root.currentSource)
            } else {
                root.reportExhausted("load-timeout")
            }
        }
    }
}
