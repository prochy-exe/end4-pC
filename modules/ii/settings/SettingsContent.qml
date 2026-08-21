import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: 8
    property string monitorName: ""
    property int currentPage: 0
    property bool showingProfile: false

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return
            
            let parts = GlobalStates.settingsPage.split(":");
            let pageName = parts[0];
            let searchTerm = parts.length > 1 ? parts[1] : "";

            const idx = root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase());
            
            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;
                
                if (searchTerm !== "") {
                    let loader = pagesRepeater.itemAt(idx);
                    if (loader && loader.item && typeof loader.item.goTo === "function") {
                        loader.item.goTo(searchTerm);
                    } else if (loader) {
                        loader.onLoaded.connect(function() {
                            if (loader.item && typeof loader.item.goTo === "function") {
                                loader.item.goTo(searchTerm);
                            }
                        });
                    }
                }
            }
            GlobalStates.settingsPage = "";
        }
    }

    onCurrentPageChanged: {
        if (root.pages[currentPage]?.name === Translation.tr("About")) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            Updates.refresh()
        }
    }
    
    property var pages: [
        { name: Translation.tr("Quick"),      icon: "instant_mix",    component: Qt.resolvedUrl("pages/QuickConfig.qml") },
        { name: Translation.tr("General"),    icon: "browse",         component: Qt.resolvedUrl("pages/GeneralConfig.qml") },
        { name: Translation.tr("Appearance"), icon: "palette",        component: Qt.resolvedUrl("pages/AppearanceConfig.qml") },
        { name: Translation.tr("Wallpaper effects"), icon: "blur_on", component: Qt.resolvedUrl("pages/WallpaperEffectsConfig.qml") },
        { name: Translation.tr("Interface"),  icon: "bottom_app_bar", component: Qt.resolvedUrl("pages/InterfaceConfig.qml") },
        { name: Translation.tr("Services"),   icon: "settings",       component: Qt.resolvedUrl("pages/ServicesConfig.qml") },
        { name: Translation.tr("Windows"),    icon: "select_window_2", component: Qt.resolvedUrl("pages/WindowsConfig.qml") },
        { name: Translation.tr("Keybinds"),   icon: "keyboard",       component: Qt.resolvedUrl("pages/KeybindsConfig.qml") },
        { name: Translation.tr("About"),      icon: "info",           component: Qt.resolvedUrl("pages/About.qml") }
    ]

    Component.onCompleted: {
        Config.readWriteDelay = 0
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            Rectangle {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 0
                implicitWidth: navRail.expanded ? 240 : fab.baseSize
                color: MonitorThemes.colorForItem(root, "surface_container_low", Appearance.m3colors.m3surfaceContainerLow)
                radius: Appearance.rounding.normal

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: navRail.expanded ? 20 : 0
                    }
                    spacing: 10
                    expanded: root.width > 900

                    RowLayout {
                        visible: navRail.expanded
                        spacing: 10
                        Layout.fillWidth: true
                        Layout.margins: 5
                        Layout.topMargin: 15

                        Rectangle {
                            id: avatarRect
                            width: 48
                            height: 48
                            radius: width / 2
                            color: MonitorThemes.colorForItem(root, "primary_container", Appearance.colors.colPrimaryContainer)

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
                                    if (status === Image.Error)
                                        visible = false
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "account_circle"
                                iconSize: 32
                                color: MonitorThemes.colorForItem(root, "on_primary_container", Appearance.colors.colOnPrimaryContainer)
                                visible: avatarImage.status !== Image.Ready
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            StyledText {
                                text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100
                            }

                            StyledText {
                                id: distroText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100

                                text: {
                                    const d = Config.options.profile.descriptionText
                                    if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                    return SystemInfo.distroName
                                }
                            }
                        }

                            TapHandler {
                                onTapped: root.showingProfile = !root.showingProfile
                            }
                    }

                    Rectangle {
                        width: 160
                        Layout.topMargin: -5
                        height: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.2; color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutline) }
                            GradientStop { position: 0.8; color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutline) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.15
                    }

                    FloatingActionButton {
                        id: fab
                        Layout.bottomMargin: -25
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }
                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: fab.justCopied = false
                        }
                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    StyledFlickable {
                        id: navRailScroll
                        Layout.topMargin: 25
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: tabArray.implicitHeight

                        NavigationRailTabArray {
                            id: tabArray
                            width: navRailScroll.width
                            currentIndex: root.currentPage
                            expanded: navRail.expanded
                            colToggled: root.showingProfile ? "transparent" : MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
                            Repeater {
                                model: root.pages
                                NavigationRailButton {
                                    required property var index
                                    required property var modelData
                                    toggled: root.currentPage === index && !root.showingProfile
                                    onPressed: {
                                        root.currentPage = index
                                        root.showingProfile = false
                                    }
                                    expanded: navRail.expanded
                                    buttonIcon: modelData.icon
                                    buttonIconRotation: modelData.iconRotation || 0
                                    buttonText: modelData.name
                                    showToggledHighlight: false
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut

                Item {
                    anchors.fill: parent

                    Repeater {
                        id: pagesRepeater
                        model: root.pages
                        Loader {
                            id: pageLoader
                            required property var modelData
                            required property var index
                            source: modelData.component

                            active: Config.ready && (root.currentPage === index || item !== null)

                            anchors.fill: parent

                            property bool isActive: root.currentPage === index && !root.showingProfile
                            opacity: isActive ? 1 : 0
                            enabled: isActive
                            visible: isActive
                            anchors.topMargin: isActive ? 0 : 12

                            onLoaded: {
                                if (root.currentPage === index) {
                                    GlobalStates.currentPageInstance = item;
                                }
                            }

                            onIsActiveChanged: {
                                if (isActive && item) {
                                    GlobalStates.currentPageInstance = item;
                                } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                    GlobalStates.currentPageInstance = null;
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Loader {
                        id: profileLoader
                        active: Config.ready && (root.showingProfile || item !== null)
                        anchors.fill: parent
                        source: Qt.resolvedUrl("pages/Profile.qml")

                        property bool isActive: root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }
}
