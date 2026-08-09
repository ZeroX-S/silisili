import QtQuick 2.2
import Sailfish.Silica 1.0

Dialog {
    property var playbackSurfaceOwner
    id: dialog
    allowedOrientations: Orientation.All
    property var commentModel
    property bool replyMode: false
    property string parentRpid
    property string rootRpid
    property string replyAuthor
    property bool regressionPrepareText: false

    canAccept: commentText.text.trim().length > 0
               && !commentModel.loading && !commentModel.posting
    onAccepted: {
        if (replyMode)
            commentModel.postReply(commentText.text, parentRpid, rootRpid, replyAuthor)
        else
            commentModel.postComment(commentText.text)
    }
    onStatusChanged: {
        if (status === PageStatus.Active)
            focusTimer.restart()
    }

    Timer {
        id: focusTimer
        interval: 300
        repeat: false
        onTriggered: {
            commentText.forceActiveFocus()
            if (commentText.openSoftwareInputPanel)
                commentText.openSoftwareInputPanel()
            Qt.inputMethod.show()
            if (dialog.regressionPrepareText) {
                commentText.text = "SiliSili local-only reply regression"
                console.log("native comment action: reply editor regression text prepared",
                            "length", commentText.text.length)
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: form.height

        Column {
            id: form
            width: parent.width
            DialogHeader {
                title: replyMode
                       ? qsTr("回复 @%1").arg(replyAuthor) : qsTr("发表评论")
                acceptText: replyMode ? qsTr("回复") : qsTr("发表")
            }
            TextArea {
                id: commentText
                width: parent.width
                label: replyMode ? qsTr("回复内容") : qsTr("评论内容")
                placeholderText: replyMode
                                 ? qsTr("回复 @%1").arg(replyAuthor)
                                 : qsTr("友善交流，尊重不同观点")
                focus: true
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhMultiLine
                wrapMode: TextEdit.Wrap
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                onActiveFocusChanged: {
                    if (activeFocus) {
                        if (commentText.openSoftwareInputPanel)
                            commentText.openSoftwareInputPanel()
                        Qt.inputMethod.show()
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
