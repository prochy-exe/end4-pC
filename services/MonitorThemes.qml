pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var palettes: ({})
    readonly property bool active: Config.options.background.wallpaperMode === "perMonitor"
        && Object.keys(palettes).length > 1

    function color(monitorName, role, fallback) {
        return root.active ? (root.palettes[monitorName]?.[role] ?? fallback) : fallback
    }

    function colorForItem(item, role, fallback) {
        return root.color(item.QsWindow?.window?.screen?.name ?? "", role, fallback)
    }

    function m3ColorForItem(item, name, fallback) {
        const role = name.slice(2).replace(/([A-Z])/g, "_$1").toLowerCase()
        return root.colorForItem(item, role, fallback)
    }

    function shellColorForItem(item, name, fallback) {
        const roles = {
            colSubtext: "outline",
            colLayer0: "surface_container_low",
            colLayer0Base: "background",
            colOnLayer0: "on_background",
            colLayer0Border: "outline_variant",
            colLayer1: "surface_container_low",
            colLayer1Base: "surface_container_low",
            colOnLayer1: "on_surface_variant",
            colLayer2: "surface_container",
            colLayer2Base: "surface_container",
            colOnLayer2: "on_surface",
            colLayer3: "surface_container_high",
            colLayer3Base: "surface_container_high",
            colOnLayer3: "on_surface",
            colLayer4: "surface_container_highest",
            colLayer4Base: "surface_container_highest",
            colOnLayer4: "on_surface",
            colPrimary: "primary",
            colOnPrimary: "on_primary",
            colPrimaryContainer: "primary_container",
            colOnPrimaryContainer: "on_primary_container",
            colSecondary: "secondary",
            colOnSecondary: "on_secondary",
            colSecondaryContainer: "secondary_container",
            colOnSecondaryContainer: "on_secondary_container",
            colTertiary: "tertiary",
            colOnTertiary: "on_tertiary",
            colTertiaryContainer: "tertiary_container",
            colOnTertiaryContainer: "on_tertiary_container",
            colOutlineVariant: "outline_variant",
            colOnSurface: "on_surface",
            colOnSurfaceVariant: "on_surface_variant",
            colSurfaceContainerLow: "surface_container_low",
            colSurfaceContainerHigh: "surface_container_high",
            colError: "error",
            colOnError: "on_error",
            colScrim: "scrim",
            colShadow: "shadow"
        };
        return roles[name] ? root.colorForItem(item, roles[name], fallback) : fallback
    }

    function refresh() { refreshTimer.restart() }

    Timer {
        id: refreshTimer
        interval: 250
        repeat: false
        onTriggered: generator.running = true
    }

    Process {
        id: generator
        command: ["python3", Quickshell.shellPath("scripts/colors/generate-monitor-themes.py")]
    }

    FileView {
        id: paletteFile
        path: Qt.resolvedUrl(`${Directories.state}/user/generated/monitor-colors.json`)
        watchChanges: true
        onLoadedChanged: {
            try { root.palettes = JSON.parse(text()) } catch (error) { root.palettes = ({}) }
        }
        onFileChanged: reload()
    }

    Connections {
        target: Config.options.background
        function onWallpaperModeChanged() { root.refresh() }
        function onMonitorWallpapersChanged() { root.refresh() }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() { root.refresh() }
    }

    Component.onCompleted: root.refresh()
}
