import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.iconPicker

Item {
    id: root
    property string monitorName: ""
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property bool showIconPickerDialog: false

    function clearDialogs() {
        root.showAudioOutputDialog = false
        root.showAudioInputDialog = false
        root.showBluetoothDialog = false
        root.showNightLightDialog = false
        root.showWifiDialog = false
        root.showIconPickerDialog = false
    }

    function showDialog(dialogName) {
        root.clearDialogs()
        if (dialogName === "audioOutput") root.showAudioOutputDialog = true
        else if (dialogName === "audioInput") root.showAudioInputDialog = true
        else if (dialogName === "bluetooth") root.showBluetoothDialog = true
        else if (dialogName === "nightLight") root.showNightLightDialog = true
        else if (dialogName === "wifi") root.showWifiDialog = true
        else if (dialogName === "iconPicker") root.showIconPickerDialog = true
    }

    function wallpaperPathForScreen() {
        const screenName = root.QsWindow?.window?.screen?.name ?? "";
        if (Config.options.background.wallpaperMode === "perMonitor") {
            const override = (Config.options.background.monitorWallpapers ?? [])
                .find(entry => entry.name === screenName)?.path;
            if (override) return override;
        }
        return Config.options.background.wallpaperPath;
    }

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    Connections {
        target: GlobalStates
        function onSidebarRightDialogRequestChanged() {
            if (!GlobalStates.sidebarRightRequestedDialog) return;
            GlobalStates.sidebarRightOpen = true;
            root.showDialog(GlobalStates.sidebarRightRequestedDialog);
        }

        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.clearDialogs();
            }
        }
    }

    Process {
        id: fileChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        
        stdout: StdioCollector {
            id: fileChooserOutput
        }
        
        onExited: (code) => {
            if (code === 0) {
                const path = fileChooserOutput.text.trim()
                if (path !== "") {
                    Config.options.sidebar.bannerImage = path
                }
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
        border.width: 1
        border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            // Banner
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: false
                sourceComponent: Config.options.sidebar.banner ? bannerComponent : normalComponent

                Component {
                    id: bannerComponent
                    Item {
                        implicitHeight: 180
                        implicitWidth: parent?.width ?? 0

                        Rectangle {
                            id: sysRect
                            anchors.fill: parent
                            radius: Config.options.hyprland.decoration.rounding - 2
                            color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)

                            Rectangle {
                                id: wallpaperRect
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    topMargin: 2
                                    leftMargin: 2
                                    rightMargin: 2
                                }
                                height: 120
                                radius: sysRect.radius
                                color: "transparent"

                                StyledImage {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: Config.options.sidebar.bannerImage !== "" 
                                        ? Config.options.sidebar.bannerImage 
                                        : root.wallpaperPathForScreen()
                                    cache: false
                                    antialiasing: true
                                    sourceSize.width: wallpaperRect.width * 2
                                    sourceSize.height: wallpaperRect.height * 2
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: wallpaperRect.width
                                            height: wallpaperRect.height
                                            radius: wallpaperRect.radius
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (event) => {
                                        if (event.button === Qt.LeftButton) {
                                            fileChooser.running = true
                                            GlobalStates.sidebarRightOpen = false
                                        } else if (event.button === Qt.RightButton) {
                                            Config.options.sidebar.bannerImage = ""
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    bottom: parent.bottom
                                    leftMargin: 13
                                    bottomMargin: 8
                                }
                                spacing: 1

                                Rectangle {
                                    id: avatarRect
                                    width: 48; height: 48; radius: width / 2
                                    color: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)

                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: Config.options.profile.avatarPicture !== "" 
                                            ? "file://" + Config.options.profile.avatarPicture 
                                            : ""
                                        sourceSize.width: avatarImage.width * 2
                                        sourceSize.height: avatarImage.height * 2
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: avatarRect.width
                                                height: avatarRect.height
                                                radius: avatarRect.radius
                                            }
                                        }
                                        onStatusChanged: {
                                            if (status === Image.Error) visible = false
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "account_circle"
                                        iconSize: 32
                                        color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                                        visible: avatarImage.status !== Image.Ready
                                    }
                                }

                                StyledText {
                                    text: Config.options.profile.displayName === ""
                                        ? SystemInfo.usernameDisplay
                                        : Config.options.profile.displayName
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                                }

                                StyledText {
                                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                                    opacity: 0.6
                                }
                            }

                            ButtonGroup {
                                anchors {
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 4
                                }
                                color: "transparent"
                                padding: 4

                                QuickToggleButton {
                                    toggled: root.editMode
                                    visible: Config.options.sidebar.quickToggles.style === "android"
                                    buttonIcon: "edit"
                                    onClicked: root.editMode = !root.editMode
                                    StyledToolTip {
                                        text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "restart_alt"
                                    onClicked: {
                                        Quickshell.execDetached(["hyprctl", "reload"])
                                        Quickshell.reload(true);
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Reload Hyprland & Quickshell")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: GlobalStates.settingsOpen
                                    buttonIcon: "settings"
                                    onClicked: {
                                        GlobalStates.sidebarRightOpen = false;
                                        GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Settings")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "mode_off_on"
                                    onClicked: GlobalStates.sessionOpen = true
                                    StyledToolTip {
                                        text: Translation.tr("Session")
                                    }
                                }
                            }
                        }
                    }
                }

                Component {
                    id: normalComponent
                    SystemButtonRow {}
                }
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
            }

            Loader {
                active: root.activePlayer !== null && GlobalStates.sidebarRightOpen && Config.options.sidebar.mediaPlayer
                visible: active
                Layout.fillWidth: true
                Layout.topMargin: -10
                Layout.bottomMargin: -10
                Layout.leftMargin: -10
                Layout.rightMargin: -10
                sourceComponent: Player {
                    id: sidebarPlayerCard
                    player: root.activePlayer
                    property AppAudioTap tap: AppAudioTap {
                        player: root.activePlayer
                        active: GlobalStates.sidebarRightOpen
                    }
                    visualizerPoints: sidebarPlayerCard.tap.points
                    implicitHeight: 160
                    radius: Appearance.rounding.normal
                }
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
            }

            BottomWidgetGroup {
                visible: Config.options.sidebar.bottomGroup
                id: bottomWidgetGroup
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
            showScrim: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
            showScrim: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog { showScrim: false }
        onShownChanged: {
            const adapter = Bluetooth.defaultAdapter;
            if (!adapter) return;
            if (!shown) {
                adapter.discovering = false;
            } else {
                adapter.enabled = true;
                adapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog { showScrim: false }
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog { showScrim: false }
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showIconPickerDialog"
        dialog: IconPickerDialog { showScrim: false }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (toggleDialogLoader.item && !toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() { root.showDialog("audioOutput"); }
            function onOpenAudioInputDialog() { root.showDialog("audioInput"); }
            function onOpenBluetoothDialog() { root.showDialog("bluetooth"); }
            function onOpenNightLightDialog() { root.showDialog("nightLight"); }
            function onOpenWifiDialog() { root.showDialog("wifi"); }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
            radius: Appearance.rounding.normal
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25

                    CustomIcon {
                        id: distroIcon
                        anchors.fill: parent
                        source: Config.options.custom.distroIcon || SystemInfo.distroIcon
                        colorize: Config.options.custom.colorizeIcon
                        color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showIconPickerDialog = true
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    if (WM.compositor === "niri") {
                        Quickshell.execDetached(["niri", "msg", "action", "reload-config"]);
                    } else {
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    }
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: WM.compositor === "niri"
                        ? Translation.tr("Reload Niri & Quickshell")
                        : Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: GlobalStates.settingsOpen
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "mode_off_on"
                onClicked: GlobalStates.sessionOpen = true
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
