import QtQuick 2.2
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    Component.onCompleted: console.log(
        "native about: ready",
        "package", nativePackageName,
        "version", nativePackageVersion,
        "sailfish", nativeSailfishVersion,
        "architecture", nativeBuildArchitecture,
        "qt", nativeQtVersion,
        "mpvApi", nativeMpvApiVersion)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: qsTr("关于 silisili")
                description: qsTr("为 Sailfish OS 打造的原生客户端")
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: identityColumn.height + 2 * Theme.paddingLarge
                radius: Theme.paddingMedium
                color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityLow)

                Column {
                    id: identityColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.paddingLarge
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        text: "silisili"
                        color: Theme.highlightColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeHuge, appSettings.fontSizeMode)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        width: parent.width
                        text: qsTr("原生开发版  %1").arg(nativePackageVersion)
                        color: Theme.primaryColor
                        font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeMedium, appSettings.fontSizeMode)
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        width: parent.width
                        text: qsTr("视频、直播、动态与个人内容，使用 Sailfish Silica 交互重新实现")
                        color: Theme.secondaryColor
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            SectionHeader { text: qsTr("版本与运行环境") }
            DetailItem { label: qsTr("应用版本"); value: nativeAppVersion }
            DetailItem { label: qsTr("软件包修订"); value: nativePackageRelease }
            DetailItem { label: qsTr("软件包"); value: nativePackageName }
            DetailItem { label: qsTr("系统"); value: "Sailfish OS " + nativeSailfishVersion }
            DetailItem { label: qsTr("架构"); value: nativeBuildArchitecture }
            DetailItem { label: qsTr("运行库"); value: "Qt " + nativeQtVersion + " · libmpv API " + nativeMpvApiVersion }
            DetailItem {
                label: qsTr("视频解码")
                value: nativeHardwareDecodeAvailable
                       ? qsTr("droidmedia · Android OMX 硬件")
                       : qsTr("libmpv · FFmpeg 软件兼容")
            }
            DetailItem {
                label: qsTr("后台显示")
                value: systemPipController.backgroundPlaybackMode === "pip"
                       ? qsTr("Lipstick 系统小窗") : qsTr("Sailfish Cover 视频")
            }

            SectionHeader { text: qsTr("播放与兼容性") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("视频优先由 FFmpeg 解复用并通过 droidmedia 送入 Android OMX 硬件解码器；解码后的 gralloc 帧使用 EGLImage 在 GPU 内写入应用共享纹理。全屏、详情页、应用内小窗、Cover 与可选系统小窗复用同一视频会话，切换时不重新定位。清晰度菜单保留当前视频接口实际返回的全部可用档位。")
                color: Theme.primaryColor
                wrapMode: Text.Wrap
            }
            Item { width: 1; height: Theme.paddingMedium }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: nativeHardwareDecodeAvailable
                      ? qsTr("当前设备已通过硬件能力探测。音频与主时钟仍由 libmpv 管理，快进使用 OMX 原地刷新；若硬件解码或 EGL 输出失败，会从当前位置自动降级到完整软件解码。")
                      : qsTr("当前系统没有提供可用的 droidmedia 硬件通路，已自动采用 libmpv/FFmpeg 软件解码；播放、快进、倍速、Cover 和前后台恢复功能保持一致。")
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("版本说明") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("这是可与旧版并行安装的原生开发包。登录信息保存在应用自己的配置目录中；卸载或升级不会主动修改旧版软件包。")
                color: Theme.primaryColor
                wrapMode: Text.Wrap
            }

            SectionHeader { text: qsTr("开源与许可") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("silisili 基于开源项目持续开发，应用代码采用 GPL-3.0-or-later；直接硬解架构参考并改造自 RooTheater-SailfishOS，Lipstick notification 小窗表面与输入区域机制参考 screentapshot-lipstick。系统小窗直接显示应用共享纹理，不使用其整屏录制协议。随包媒体运行库及上游署名文件安装在系统标准 licenses 目录。项目与哔哩哔哩官方无隶属关系。")
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeLarge
                onClicked: Qt.openUrlExternally("https://github.com/ZeroX-S/silisili")

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: sourceIcon.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("查看源代码与更新记录")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Image {
                    id: sourceIcon
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-right"
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("感谢所有上游项目贡献者与真机测试者。")
                color: Theme.secondaryColor
                font.pixelSize: appSettings.scaledFontSize(Theme.fontSizeSmall, appSettings.fontSizeMode)
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        VerticalScrollDecorator {}
    }
}
