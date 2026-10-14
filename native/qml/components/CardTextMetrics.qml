import QtQuick 2.2
import Sailfish.Silica 1.0

// Measure real font line boxes instead of reserving fixed pixels in a grid.
Item {
    visible: false
    readonly property real titleHeight: titleMeasure.implicitHeight
    readonly property real metadataHeight: metadataMeasure.implicitHeight
    AppLabel { id: titleMeasure; text: "Ag国\nAg国" }
    AppLabel {
        id: metadataMeasure
        text: "Ag国"
        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeExtraSmall, appSettings.fontSizeMode)
    }
}
