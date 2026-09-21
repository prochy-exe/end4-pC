pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: 310
    minimumHeight: 130

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 8
        ColumnLayout {
            id: contentColumn
            anchors.centerIn: parent
            spacing: 10

            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 10

                BigRecorderButton {
                    materialSymbol: "screenshot_region"
                    name: "Screenshot region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["bash", "-c", "pid=$(pgrep -x 'qs|quickshell' | head -n1) && exec qs ipc --pid \"$pid\" call region screenshot"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "photo_camera"
                    name: "Screenshot all monitors"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached([Directories.screenshotAllMonitorsScriptPath]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "screen_record"
                    name: "Record region"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Quickshell.execDetached(["bash", "-c", "pid=$(pgrep -x 'qs|quickshell' | head -n1) && exec qs ipc --pid \"$pid\" call region record"]);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "capture"
                    name: "Record screen"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        const command = [Directories.recordScriptPath, "--fullscreen", "--copy-after"];
                        if (Config.options.screenRecord.recordSystemAudio)
                            command.push("--system-audio");
                        if (Config.options.screenRecord.recordMicAudio)
                            command.push("--mic");
                        Quickshell.execDetached(command);
                    }
                }

                BigRecorderButton {
                    materialSymbol: "web_asset"
                    name: "Record all monitors"
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        const command = [Directories.recordScriptPath, "--all-monitors", "--copy-after"];
                        if (Config.options.screenRecord.recordSystemAudio)
                            command.push("--system-audio");
                        if (Config.options.screenRecord.recordMicAudio)
                            command.push("--mic");
                        Quickshell.execDetached(command);
                    }
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.fillWidth: false
                buttonRadius: height / 2
                colBackground: MonitorThemes.shellColorForItem(root, "colLayer3", Appearance.colors.colLayer3)
                colBackgroundHover: MonitorThemes.shellColorForItem(root, "colLayer3Hover", Appearance.colors.colLayer3Hover)
                colRipple: MonitorThemes.shellColorForItem(root, "colLayer3Active", Appearance.colors.colLayer3Active)
                onClicked: {
                    GlobalStates.overlayOpen = false;
                    Qt.openUrlExternally(`file://${Config.options.screenRecord.savePath}`);
                }
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "animated_images"
                        iconSize: 20
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Open recordings folder")
                    }
                }
            }
        }
    }

    component BigRecorderButton: RippleButton {
        id: bigButton
        required property string materialSymbol
        required property string name
        implicitHeight: 66
        implicitWidth: 66
        buttonRadius: height / 2

        colBackground: MonitorThemes.shellColorForItem(root, "colLayer3", Appearance.colors.colLayer3)
        colBackgroundHover: MonitorThemes.shellColorForItem(root, "colLayer3Hover", Appearance.colors.colLayer3Hover)
        colRipple: MonitorThemes.shellColorForItem(root, "colLayer3Active", Appearance.colors.colLayer3Active)

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: bigButton.materialSymbol
            iconSize: 28
        }

        StyledToolTip {
            text: bigButton.name
        }
    }
}
