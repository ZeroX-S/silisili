import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All
    property bool completed: false
    property real qrScale: 1.0
    property string qrRenderError: ""
    property string qrRenderer: ""
    property string qrRendererProperty: ""
    property var qrImageItem: null
    property string renderedQrSource: ""
    property int qrImageRebuildCount: 0

    ResponsivePageMetrics {
        target: page
        pageName: "qr-login"
        columns: 1
        primaryExtent: page.qrSize()
    }

    function baseQrSize() {
        return Math.min(width - 4 * Theme.horizontalPageMargin,
                        height - 2 * Theme.itemSizeHuge,
                        Theme.itemSizeHuge * 4.5)
    }

    function qrSize() {
        return Math.max(Theme.itemSizeHuge * 2.4,
                        Math.min(width - 2 * Theme.horizontalPageMargin,
                                 baseQrSize() * qrScale))
    }

    function amberPreferred() {
        // The module probe is authoritative when present. The version check
        // also puts 5.2+ images on the Amber path when their QML directory is
        // exposed through a vendor-specific Qt import root.
        return qrBarcodeAvailable
                || qrSailfishVersionMajor > 5
                || (qrSailfishVersionMajor === 5 && qrSailfishVersionMinor >= 2)
    }

    function createQrRenderer(candidate, source) {
        try {
            var qml = 'import QtQuick 2.2; import ' + candidate.module
                    + ' 1.0; ' + candidate.type + ' { anchors.fill: parent; '
                    + candidate.initializer + ' }'
            var item = Qt.createQmlObject(qml, qrContainer,
                                          "RuntimeQr" + candidate.type)
            // Both supported system components expose sourceText. Set that
            // exact declared property only: QQuickItem's inherited `data`
            // list accepts an assignment but is not barcode payload data and
            // leaves Amber.Barcode showing its "No data" error.
            item.sourceText = source
            qrRenderer = candidate.module + "." + candidate.type
            qrRendererProperty = "sourceText"
            return item
        } catch (error) {
            console.log("native account: QR renderer unavailable",
                        candidate.module, candidate.type, String(error))
            return null
        }
    }

    function rendererCandidates() {
        var amber = [
            { module: "Amber.Barcode", type: "BarcodeImage",
              initializer: "format: BarcodeImage.QRCode;" }
        ]
        var qrShare = [
            { module: "QrShareImage", type: "QrShareImage",
              initializer: "" }
        ]
        return amberPreferred() ? amber.concat(qrShare) : qrShare.concat(amber)
    }

    function qrItemError(item) {
        if (!item)
            return ""
        try {
            return String(item.error || "")
        } catch (error) {
            return ""
        }
    }

    function rebuildQrImage(reason) {
        var nextSource = accountService.qrUrl || ""
        // AccountService emits changed() for every polling transition. Keep
        // the live QR item and its painted surface stable across those status
        // updates; only a genuinely different URL (the explicit regenerate
        // action) is allowed to replace the image.
        if (nextSource === renderedQrSource && qrImageItem) {
            console.log("native account: QR image retained",
                        "reason", reason || "unchanged",
                        "sourceLength", nextSource.length,
                        "rebuildCount", qrImageRebuildCount)
            return
        }
        if (qrImageItem) {
            qrImageItem.destroy()
            qrImageItem = null
        }
        qrRenderError = ""
        qrRenderer = ""
        qrRendererProperty = ""
        renderedQrSource = nextSource
        if (!qrContainer || nextSource.length === 0)
            return

        var candidates = rendererCandidates()
        for (var i = 0; i < candidates.length; ++i) {
            qrImageItem = createQrRenderer(candidates[i], nextSource)
            if (qrImageItem)
                break
        }
        if (qrImageItem) {
            ++qrImageRebuildCount
            console.log("native account: QR renderer selected",
                        qrRenderer,
                        "property", qrRendererProperty,
                        "reason", reason || "source-changed",
                        "sourceLength", nextSource.length,
                        "rebuildCount", qrImageRebuildCount,
                        "sailfishRelease", qrSailfishRelease)
        } else {
            qrRenderError = qsTr("二维码组件加载失败（系统 %1）")
                    .arg(qrSailfishRelease || qsTr("版本未知"))
        }
    }

    Component.onCompleted: {
        console.log("native account: QR login page completed")
        accountService.startQrLogin()
        rebuildQrImage("initial")
    }
    Component.onDestruction: {
        if (qrImageItem) {
            qrImageItem.destroy()
            qrImageItem = null
        }
        if (!completed)
            accountService.cancelQrLogin()
    }

    Connections {
        target: accountService
        onQrLoginSucceeded: {
            page.completed = true
            closeTimer.start()
        }
        onChanged: {
            // Polling changes qrLoading/qrStatus but must not refresh the QR.
            // The explicit generate/regenerate button changes qrUrl and is the
            // only normal path that replaces the painted item.
            if ((accountService.qrUrl || "") !== page.renderedQrSource)
                page.rebuildQrImage("qr-url-changed")
            else
                console.log("native account: QR status changed without refresh",
                            "loading", accountService.qrLoading,
                            "active", accountService.qrActive,
                            "sourceLength", page.renderedQrSource.length,
                            "rebuildCount", page.qrImageRebuildCount)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: page.status === PageStatus.Active && accountService.qrActive
        onTriggered: accountService.pollQrLogin()
    }

    Timer {
        id: closeTimer
        interval: 1200
        repeat: false
        onTriggered: pageStack.pop()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("重置二维码大小")
                onClicked: page.qrScale = 1.0
            }
            MenuItem {
                text: qsTr("放大二维码")
                onClicked: page.qrScale = Math.min(1.6, page.qrScale + 0.1)
            }
            MenuItem {
                text: qsTr("缩小二维码")
                onClicked: page.qrScale = Math.max(0.7, page.qrScale - 0.1)
            }
            MenuItem {
                text: qsTr("刷新二维码")
                enabled: !accountService.qrLoading
                onClicked: accountService.startQrLogin()
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("二维码登录")
                description: qsTr("哔哩哔哩")
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: page.qrSize()
                height: width
                color: "black"
                radius: Theme.paddingSmall
                visible: accountService.qrUrl.length > 0

                Item {
                    id: qrContainer
                    anchors.fill: parent
                    anchors.margins: Theme.paddingMedium

                    Component.onCompleted: page.rebuildQrImage("container-ready")
                }
            }

            Slider {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                label: qsTr("二维码大小")
                minimumValue: 0.7
                maximumValue: 1.6
                stepSize: 0.1
                value: page.qrScale
                valueText: Math.round(value * 100) + "%"
                visible: accountService.qrUrl.length > 0
                onValueChanged: page.qrScale = value
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text.length > 0
                text: page.qrRenderError.length > 0
                      ? page.qrRenderError
                      : page.qrItemError(page.qrImageItem)
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: accountService.qrLoading && accountService.qrUrl.length === 0
                size: BusyIndicatorSize.Large
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: accountService.qrStatus
                color: accountService.qrActive ? Theme.highlightColor : Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("使用另一台已登录哔哩哔哩的设备扫码并确认。扫码成功前不会替换当前账户；稳定版配置始终只读。")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: accountService.qrActive ? qsTr("重新生成") : qsTr("生成二维码")
                enabled: !accountService.qrLoading && !completed
                onClicked: accountService.startQrLogin()
            }
        }
        VerticalScrollDecorator {}
    }
}
