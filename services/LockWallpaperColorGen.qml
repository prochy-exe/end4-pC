pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    function regenerate() {
        if (!Config.options.background.lockWall || Config.options.background.lockWall.length === 0) return
        genProc.command = ["bash", Directories.wallpaperSwitchScriptPath,
            "--lock-colors-only", FileUtils.trimFileProtocol(Config.options.background.lockWall)]
        genProc.environment = ({ "II_LOCK_COLORS": "1" })
        genProc.running = true
    }

    Connections {
        target: Config.options.background
        function onLockWallChanged() {
            root.regenerate()
        }
        function onLockMonitorWallpapersChanged() {
            if (Config.options.background.lockWallpaperMode === "perMonitor") root.regenerate()
        }
        function onLockWallpaperModeChanged() {
            if (Config.options.background.lockWallpaperMode === "perMonitor") root.regenerate()
        }
    }

    Process {
        id: genProc
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("[LockWallpaperColorGen] switchwall.sh --lock-colors-only failed")
                return
            }
            if (Config.options.background.lockWallpaperMode === "perMonitor") {
                Quickshell.execDetached(["bash", "-c", `II_LOCK_COLORS=1 python3 '${Quickshell.shellPath("scripts/colors/generate-monitor-themes.py")}'`])
            }
        }
    }
}
