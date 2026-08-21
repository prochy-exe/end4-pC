pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: root

    function themeColor(role, fallback) {
        const targetScreen = GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
        const shellRoles = {
            surface_container_low: "colLayer1",
            surface_container: "colLayer2",
            surface_container_high: "colLayer2Hover",
            primary_container: "colPrimaryContainer",
            on_surface_variant: "colOnLayer1"
        }
        return MonitorThemes.shellColorForItem(targetScreen, shellRoles[role] ?? role, fallback)
    }

    function openCentered(shouldOpen) {
        if (!shouldOpen) {
            GlobalStates.desktopMenuOpen = false
            return
        }
        const focusedName = Hyprland.focusedMonitor?.name
        const screen = Quickshell.screens.find(s => s.name === focusedName) ?? Quickshell.screens[0]
        GlobalStates.desktopMenuScreen = screen
        GlobalStates.desktopMenuX = screen.width / 2
        GlobalStates.desktopMenuY = screen.height / 2
        GlobalStates.desktopMenuOpen = true
    }

    function displayPathFor(path) {
        if (!path) return path
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    function wallpaperPathForScreen(screen) {
        if (Config.options.background.wallpaperMode === "perMonitor") {
            const override = (Config.options.background.monitorWallpapers ?? [])
                .find(entry => entry.name === screen?.name)?.path;
            if (override) {
                console.warn(`[DesktopMenu DEBUG] wallpaper override screen=${screen?.name ?? "null"} path=${override}`)
                return override;
            }
        }
        console.warn(`[DesktopMenu DEBUG] shared wallpaper screen=${screen?.name ?? "null"} path=${Config.options.background.wallpaperPath}`)
        return Config.options.background.wallpaperPath;
    }

    // Keep the carousel's random choices as state rather than a binding. The
    // config adapter notifies all background properties on any background
    // write; shuffling from a binding would therefore change these previews
    // when an unrelated widget switch is toggled.
    property string carouselWallpaperPath: FileUtils.trimFileProtocol(
        root.wallpaperPathForScreen(GlobalStates.desktopMenuScreen))
    property string carouselFolderPath: {
        if (!root.carouselWallpaperPath) return ""
        const lastSlash = root.carouselWallpaperPath.lastIndexOf("/")
        return lastSlash >= 0 ? root.carouselWallpaperPath.substring(0, lastSlash) : ""
    }

    // Wallpaper folder images
    FolderListModel {
        id: wallpaperFolder
        folder: root.carouselFolderPath ? "file://" + root.carouselFolderPath : ""
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        onCountChanged: root.refreshCarouselWallpapers()
    }

    property int carouselExtraCount: 5
    property bool useDarkMode: Appearance.m3colors.darkmode
    property var randomWallpapers: []
    property var carouselModel: []

    function updateCarouselModel() {
        const current = root.carouselWallpaperPath
        root.carouselModel = !current || current.length === 0
            ? root.randomWallpapers.map(path => root.displayPathFor(path))
            : [root.displayPathFor(current), ...root.randomWallpapers.map(path => root.displayPathFor(path))]
    }

    function refreshCarouselWallpapers() {
        const current = root.carouselWallpaperPath
        let all = []
        for (let i = 0; i < wallpaperFolder.count; i++) {
            const fp = FileUtils.trimFileProtocol(wallpaperFolder.get(i, "filePath").toString())
            if (fp !== current) all.push(fp)
        }
        for (let i = all.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [all[i], all[j]] = [all[j], all[i]]
        }
        root.randomWallpapers = all.slice(0, root.carouselExtraCount)
        console.warn(`[DesktopMenu DEBUG] carousel current=${current} folder=${root.carouselFolderPath} random=${JSON.stringify(root.randomWallpapers)}`)
        root.updateCarouselModel()
    }

    onCarouselWallpaperPathChanged: root.refreshCarouselWallpapers()
    onCarouselFolderPathChanged: {
        root.randomWallpapers = []
        root.updateCarouselModel()
        Qt.callLater(() => root.refreshCarouselWallpapers())
    }
    Component.onCompleted: root.refreshCarouselWallpapers()

    // Menu window
    Loader {
        active: GlobalStates.desktopMenuOpen
        sourceComponent: PanelWindow {
            id: menuWindow

            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
            readonly property string monitorWallpaperPath: root.wallpaperPathForScreen(menuWindow.screen)

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay

            Component.onCompleted: {}
            onScreenChanged: {}
            onVisibleChanged: {
                if (visible) {
                    MonitorThemes.debugSelection("desktop-menu", menuWindow)
                    console.warn(`[DesktopMenu DEBUG] palette surface=${root.themeColor("surface_container_low", "fallback")} primary=${root.themeColor("primary_container", "fallback")}`)
                    console.warn(`[DesktopMenu DEBUG] visible monitor=${menuWindow.screen?.name ?? "null"} wallpaper=${menuWindow.monitorWallpaperPath}`)
                    console.warn(`[DesktopMenu DEBUG] global target=${GlobalStates.desktopMenuScreen?.name ?? "null"} x=${GlobalStates.desktopMenuX} y=${GlobalStates.desktopMenuY} mode=${Config.options.background.wallpaperMode} monitorWallpapers=${JSON.stringify(Config.options.background.monitorWallpapers ?? [])}`)
                }
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            property Component openSubmenuComponent: null
            property real submenuAnchorY: 0
            property real submenuWidth: 284

            Timer {
                id: submenuCloseTimer
                interval: 250
                onTriggered: menuWindow.openSubmenuComponent = null
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: GlobalStates.desktopMenuOpen = false
            }

            // Menu card
            Rectangle {
                id: menuCard
                width: 348
                implicitHeight: menuCol.implicitHeight + 16
                x: Math.min(Math.max(GlobalStates.desktopMenuX - width / 2, 8), menuWindow.width - width - 8)
                y: Math.min(Math.max(GlobalStates.desktopMenuY - implicitHeight / 2, 8), menuWindow.height - implicitHeight - 8)
                radius: Appearance.rounding.verylarge
                color: root.themeColor("surface_container_low", Appearance.colors.colLayer0)

                scale: 0.85
                opacity: 0
                transformOrigin: Item.Center

                Component.onCompleted: {
                    scale = 1.0
                    opacity = 1.0
                }

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 160
                        radius: Appearance.rounding.verylarge
                        color: root.themeColor("surface_container", Appearance.colors.colLayer2)
                        clip: true

                        Carousel {
                            anchors.fill: parent
                            anchors.margins: 10
                            model: [
                                root.displayPathFor(menuWindow.monitorWallpaperPath),
                                ...root.randomWallpapers.map(path => root.displayPathFor(path))
                            ]
                            Component.onCompleted: console.warn(`[DesktopMenu DEBUG] carousel instantiated monitor=${menuWindow.screen?.name ?? "null"} source=${JSON.stringify(model)}`)
                            onWallpaperSelected: (path) => {
                                console.warn(`[DesktopMenu DEBUG] wallpaper selected path=${path} target=${GlobalStates.desktopMenuScreen?.name ?? "null"} perMonitor=${Config.options.background.wallpaperMode === "perMonitor"}`)
                                // The menu already opens on/for the monitor that
                                // was right-clicked (see desktopMenuScreen, set
                                // from Background.qml's per-screen click area) -
                                // in perMonitor mode a pick needs to go to that
                                // monitor's own override, same as the full
                                // wallpaper selector's "monitor:" target, or it
                                // silently lands on the shared path instead,
                                // which only shows on monitors with no override
                                // of their own (not necessarily the one clicked).
                                if (Config.options.background.wallpaperMode === "perMonitor") {
                                    const monitorName = GlobalStates.desktopMenuScreen?.name ?? ""
                                    Wallpapers.select(path, Appearance.m3colors.darkmode, finalPath => {
                                        const list = (Config.options.background.monitorWallpapers ?? []).slice()
                                        const index = list.findIndex(m => m.name === monitorName)
                                        const entry = { name: monitorName, path: finalPath }
                                        if (index >= 0) list[index] = entry; else list.push(entry)
                                        Config.options.background.monitorWallpapers = list
                                    })
                                } else {
                                    Wallpapers.select(path, Appearance.m3colors.darkmode)
                                }
                                GlobalStates.desktopMenuOpen = false
                            }
                        }
                    }

                    GroupedList {
                        Layout.fillWidth: true
                        itemVerticalPadding: 16
                        bgcolor: "transparent"

                        // Wallpapers
                        RippleButton {
                            id: wallpaperRow
                            implicitHeight: 40
                            rippleEnabled: false
                            colBackground: "transparent"
                            colBackgroundHover: root.themeColor("primary_container", Appearance.colors.colPrimaryContainer)
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "format_paint"; iconSize: Appearance.font.pixelSize.larger; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText { Layout.fillWidth: true; text: "Wallpaper & style"; font.pixelSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1); opacity: 0.4 }
                            }
                            Component {
                                id: wallpaperSubmenu
                                WallpaperSubmenu {
                                    monitorName: menuWindow.screen?.name ?? ""
                                }
                            }
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        submenuCloseTimer.stop()
                                        menuWindow.submenuAnchorY = menuCard.y + wallpaperRow.mapToItem(menuCard, 0, 0).y
                                        menuWindow.openSubmenuComponent = wallpaperSubmenu
                                    } else {
                                        submenuCloseTimer.restart()
                                    }
                                }
                            }
                            onClicked: GlobalStates.desktopMenuOpen = false
                        }

                        // Widgets
                        RippleButton {
                            id: widgetsRow
                            implicitHeight: 40
                            rippleEnabled: false
                            colBackground: "transparent"
                            colBackgroundHover: root.themeColor("primary_container", Appearance.colors.colPrimaryContainer)
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "widgets"; iconSize: Appearance.font.pixelSize.larger; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText { Layout.fillWidth: true; text: "Widgets"; font.pixelSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1); opacity: 0.4 }
                            }

                            Component {
                                id: widgetsSubmenu
                                WidgetsSubmenu {
                                    monitorName: menuWindow.screen?.name ?? ""
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        submenuCloseTimer.stop()
                                        menuWindow.submenuAnchorY = menuCard.y + widgetsRow.mapToItem(menuCard, 0, 0).y
                                        menuWindow.openSubmenuComponent = widgetsSubmenu
                                    } else {
                                        submenuCloseTimer.restart()
                                    }
                                }
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            rippleEnabled: false
                            colBackground: "transparent"
                            colBackgroundHover: root.themeColor("primary_container", Appearance.colors.colPrimaryContainer)
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "stacks"; iconSize: Appearance.font.pixelSize.larger; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText { Layout.fillWidth: true; text: "DropShelf"; font.pixelSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText {
                                    visible: DropShelf.items.length > 0
                                    text: DropShelf.items.length
                                    font.pixelSize: Appearance.font.pixelSize.small
 color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1)
                                    opacity: 0.6
                                }
                                MaterialSymbol {
                                    visible: DropShelf.items.length === 0
                                    text: "chevron_right"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1)
                                    opacity: 0.4
                                }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.dropShelfX = GlobalStates.desktopMenuX
                                GlobalStates.dropShelfY = GlobalStates.desktopMenuY
                                GlobalStates.dropShelfOpen = true
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            rippleEnabled: false
                            colBackground: "transparent"
                            colBackgroundHover: root.themeColor("primary_container", Appearance.colors.colPrimaryContainer)
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "video_template"; iconSize: Appearance.font.pixelSize.larger; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText { Layout.fillWidth: true; text: "Live Wallpaper"; font.pixelSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                MaterialSymbol {
                                    visible: DropShelf.items.length === 0
                                    text: "chevron_right"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1)
                                    opacity: 0.4
                                }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                Wallpapers.openFallbackPicker(
                                    Appearance.m3colors.darkmode,
                                    Config.options.wallpaperSelector.liveWallpapersPath ?? ""
                                )
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            rippleEnabled: false
                            colBackground: "transparent"
                            colBackgroundHover: root.themeColor("primary_container", Appearance.colors.colPrimaryContainer)
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "settings"; iconSize: Appearance.font.pixelSize.larger; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                StyledText { Layout.fillWidth: true; text: "Settings"; font.pixelSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1) }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: root.themeColor("on_surface_variant", Appearance.colors.colOnLayer1); opacity: 0.4 }
                            }
                            onClicked: {
                                GlobalStates.desktopMenuOpen = false
                                GlobalStates.settingsOpen = true
                            }
                        }
                    }
                }
            }

            // SubMenu
            Loader {
                id: submenuLoader
                active: menuWindow.openSubmenuComponent !== null
                width: menuWindow.submenuWidth
                sourceComponent: menuWindow.openSubmenuComponent

                x: (menuCard.x + menuCard.width + 8 + menuWindow.submenuWidth > menuWindow.width)
                    ? menuCard.x - menuWindow.submenuWidth - 8
                    : menuCard.x + menuCard.width + 8

                y: Math.min(
                    Math.max(menuWindow.submenuAnchorY, 8),
                    menuWindow.height - (item?.implicitHeight ?? 0) - 8
                )

                scale: active ? 1.0 : 0.9
                opacity: active ? 1.0 : 0.0
                transformOrigin: Item.Center

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) submenuCloseTimer.stop()
                        else submenuCloseTimer.restart()
                    }
                }
            }
        }
    }
}
