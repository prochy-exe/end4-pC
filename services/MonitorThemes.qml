pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    property var palettes: ({})
    property string wallpaperSignature: ""
    readonly property bool active: ((GlobalStates.screenLocked && Config.options.background.lockWallpaperMode === "perMonitor")
        || (!GlobalStates.screenLocked && Config.options.background.wallpaperMode === "perMonitor")
        || (GlobalStates.screenLocked && Config.options.background.lockWallpaperMode !== "perMonitor"
            && Config.options.background.wallpaperMode === "perMonitor"))
        && Object.keys(palettes).length > 1

    function color(monitorName, role, fallback) {
        const palette = root.palettes[monitorName] ?? root.palettes["__blended__"]
        return palette?.[role] ?? fallback
    }

    function applyComponentPalette(monitorOverride) {
        if (Config.options.background.useMonitorSpecificColors && !monitorOverride) return
        const monitorName = monitorOverride
            || (Config.options.background.blendMonitorColors ? "__blended__" : Config.options.background.componentColorMonitor)
            || "__blended__"
        const palette = root.palettes[monitorName]
        if (!palette) return
        const fields = {
            background: "m3background", on_background: "m3onBackground",
            surface: "m3surface", surface_dim: "m3surfaceDim", surface_bright: "m3surfaceBright",
            surface_container_lowest: "m3surfaceContainerLowest", surface_container_low: "m3surfaceContainerLow",
            surface_container: "m3surfaceContainer", surface_container_high: "m3surfaceContainerHigh",
            surface_container_highest: "m3surfaceContainerHighest", on_surface: "m3onSurface",
            surface_variant: "m3surfaceVariant", on_surface_variant: "m3onSurfaceVariant",
            inverse_surface: "m3inverseSurface", inverse_on_surface: "m3inverseOnSurface",
            outline: "m3outline", outline_variant: "m3outlineVariant", shadow: "m3shadow", scrim: "m3scrim",
            primary: "m3primary", on_primary: "m3onPrimary", primary_container: "m3primaryContainer",
            on_primary_container: "m3onPrimaryContainer", inverse_primary: "m3inversePrimary",
            secondary: "m3secondary", on_secondary: "m3onSecondary", secondary_container: "m3secondaryContainer",
            on_secondary_container: "m3onSecondaryContainer", tertiary: "m3tertiary", on_tertiary: "m3onTertiary",
            tertiary_container: "m3tertiaryContainer", on_tertiary_container: "m3onTertiaryContainer",
            error: "m3error", on_error: "m3onError", error_container: "m3errorContainer",
            on_error_container: "m3onErrorContainer"
        }
        for (const role in fields) {
            if (palette[role] !== undefined) Appearance.m3colors[fields[role]] = palette[role]
        }
    }

    function activateForSurface(surface) {
        if (!Config.options.background.useMonitorSpecificColors) applyComponentPalette()
    }

    function colorForItem(item, role, fallback) {
        let ownMonitor = item.monitorName ?? item.name ?? item.screen?.name ?? item.QsWindow?.window?.screen?.name ?? ""
        let ancestor = item
        while (!ownMonitor && ancestor) {
            ownMonitor = ancestor.monitorName ?? ancestor.name ?? ancestor.screen?.name ?? ""
            ancestor = ancestor.parent
        }
        const monitorName = Config.options.background.useMonitorSpecificColors
            ? (ownMonitor || "__blended__")
            : Config.options.background.blendMonitorColors
                ? "__blended__"
                : (Config.options.background.componentColorMonitor || ownMonitor || "__blended__")
        return root.color(monitorName, role, fallback)
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
            colLayer1Hover: "surface_container",
            colLayer1Active: "surface_container_high",
            colOnLayer1: "on_surface_variant",
            colLayer2: "surface_container",
            colLayer2Base: "surface_container",
            colLayer2Hover: "surface_container_high",
            colLayer2Active: "surface_container_highest",
            colOnLayer2: "on_surface",
            colLayer3: "surface_container_high",
            colLayer3Base: "surface_container_high",
            colLayer3Hover: "surface_container_highest",
            colLayer3Active: "surface_container_highest",
            colOnLayer3: "on_surface",
            colLayer4: "surface_container_highest",
            colLayer4Base: "surface_container_highest",
            colLayer4Hover: "surface_container_highest",
            colLayer4Active: "surface_container_highest",
            colOnLayer4: "on_surface",
            colPrimary: "primary",
            colOnPrimary: "on_primary",
            colPrimaryContainer: "primary_container",
            colPrimaryContainerHover: "primary_container",
            colPrimaryContainerActive: "primary_container",
            colOnPrimaryContainer: "on_primary_container",
            colSecondary: "secondary",
            colSecondaryHover: "secondary",
            colSecondaryActive: "secondary",
            colOnSecondary: "on_secondary",
            colSecondaryContainer: "secondary_container",
            colSecondaryContainerHover: "secondary_container",
            colSecondaryContainerActive: "secondary_container",
            colOnSecondaryContainer: "on_secondary_container",
            colTertiary: "tertiary",
            colTertiaryHover: "tertiary",
            colTertiaryActive: "tertiary",
            colOnTertiary: "on_tertiary",
            colTertiaryContainer: "tertiary_container",
            colTertiaryContainerHover: "tertiary_container",
            colTertiaryContainerActive: "tertiary_container",
            colOnTertiaryContainer: "on_tertiary_container",
            colOutlineVariant: "outline_variant",
            colOnSurface: "on_surface",
            colOnSurfaceVariant: "on_surface_variant",
            colSurfaceContainerLow: "surface_container_low",
            colSurfaceContainerHigh: "surface_container_high",
            colError: "error",
            colErrorHover: "error",
            colErrorActive: "error",
            colErrorContainer: "error_container",
            colErrorContainerHover: "error_container",
            colErrorContainerActive: "error_container",
            colOnError: "on_error",
            colScrim: "scrim",
            colShadow: "shadow"
        };
        if (!roles[name]) return fallback
        const value = root.colorForItem(item, roles[name], fallback)
        if (!Config.options.appearance.transparency.enable) return value

        const backgroundLayer = name === "colLayer0" || name === "colLayer0Base"
            || name === "colLayer0Hover" || name === "colLayer0Active"
        const percentage = backgroundLayer ? Appearance.backgroundTransparency : 0
        const color = Qt.color(value)
        return Qt.rgba(color.r, color.g, color.b, color.a * (1 - percentage))
    }

    function refresh() {
        if (generator.running) generator.running = false
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 100
        repeat: false
        onTriggered: generator.running = true
    }

    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            const entries = Config.options.background.wallpaperMode === "perMonitor"
                ? (Config.options.background.monitorWallpapers ?? [])
                : [];
            const signature = JSON.stringify({
                mode: Config.options.background.wallpaperMode,
                wallpapers: entries.map(entry => [entry.name, entry.path]),
                scheme: Config.options.appearance.palette.type,
                useWallpaperColorForApps: Config.options.appearance.wallpaperTheming.useWallpaperColorForApps,
                accentMonitor: Config.options.appearance.wallpaperTheming.accentMonitor,
                blend: Config.options.background.blendMonitorColors,
                transparency: {
                    enable: Config.options.appearance.transparency.enable,
                    automatic: Config.options.appearance.transparency.automatic,
                    background: Config.options.appearance.transparency.backgroundTransparency,
                    content: Config.options.appearance.transparency.contentTransparency
                },
                extraBackgroundTint: Config.options.appearance.extraBackgroundTint
            });
            if (root.wallpaperSignature === "") {
                root.wallpaperSignature = signature;
            } else if (root.wallpaperSignature !== signature) {
                root.wallpaperSignature = signature;
                root.refresh();
            }
        }
    }

    Process {
        id: generator
        command: ["python3", Quickshell.shellPath("scripts/colors/generate-monitor-themes.py")]
        onExited: (exitCode) => {
            if (exitCode === 0) {
                paletteFile.reload()
            } else {
                console.warn(`[MonitorThemes] palette generation failed with exit code ${exitCode}`)
            }
        }
    }

    FileView {
        id: paletteFile
        path: Qt.resolvedUrl(`${Directories.state}/user/generated/monitor-colors.json`)
        watchChanges: true
        onLoaded: {
            try { root.palettes = JSON.parse(text()); root.applyComponentPalette() } catch (error) { root.palettes = ({}) }
        }
        onFileChanged: reload()
    }

    Connections {
        target: Config.options.background
        function onWallpaperModeChanged() { root.refresh() }
        function onMonitorWallpapersChanged() { root.refresh() }
        function onUseMonitorSpecificColorsChanged() { root.refresh(); root.applyComponentPalette() }
        function onBlendMonitorColorsChanged() { root.applyComponentPalette() }
        function onComponentColorMonitorChanged() { root.applyComponentPalette() }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() { root.refresh() }
    }

    Connections {
        target: Config.options.appearance.transparency
        function onEnableChanged() { root.refresh() }
        function onAutomaticChanged() { root.refresh() }
        function onBackgroundTransparencyChanged() { root.refresh() }
        function onContentTransparencyChanged() { root.refresh() }
    }

    Connections {
        target: Config.options.appearance
        function onExtraBackgroundTintChanged() { root.refresh() }
    }

    Component.onCompleted: root.refresh()
}
