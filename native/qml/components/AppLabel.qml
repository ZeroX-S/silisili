import QtQuick 2.2
import Sailfish.Silica 1.0

// Content typography follows the user's size preference. Native page headers,
// form controls and video surfaces retain their own Silica presentation.
Label {
    font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
    lineHeight: 1.12
    lineHeightMode: Text.ProportionalHeight
    textFormat: Text.PlainText
    truncationMode: TruncationMode.Fade
}
