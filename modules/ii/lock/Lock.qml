pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

LockScreen {
    id: root

    property var savedWorkspaces: ({})
    property string lastProcessedLockWall: ""
    property bool lastProcessedDarkmode: Appearance.m3colors.darkmode
    property int layoutBeforeLock: -1

    function applyLockKeyboardLayout() {
        const requested = Config.options.lock.keyboardLayout
        if (!requested || requested.length === 0) return
        const index = HyprlandXkb.layoutCodes.indexOf(requested)
        if (index >= 0) HyprlandXkb.switchLayout(index)
    }

    function restoreKeyboardLayout() {
        if (root.layoutBeforeLock >= 0) HyprlandXkb.switchLayout(root.layoutBeforeLock)
        root.layoutBeforeLock = -1
    }

    // Captures which layout is active (by its raw index, e.g. `hyprctl devices`'
    // active_layout_index) right before we force-switch to the lock layout, so
    // it can be restored on unlock. Queried fresh via hyprctl rather than
    // derived from HyprlandXkb's cached name/code, because that mapping goes
    // through base.lst's layout descriptions and breaks for layout variants
    // (e.g. a "qwerty" kb_variant resolves to a code like "sk:qwerty" that
    // never matches the plain "sk" in the configured layout list) -- silently
    // leaving layoutBeforeLock at -1, so the layout never gets restored.
    Process {
        id: captureKeyboardLayoutProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: captureKeyboardLayoutCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(captureKeyboardLayoutCollector.text)
                    const kb = parsed.keyboards.find(k => k.main === true)
                    root.layoutBeforeLock = kb ? kb.active_layout_index : -1
                } catch (e) {
                    root.layoutBeforeLock = -1
                }
                root.applyLockKeyboardLayout()
            }
        }
    }

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            var batch = ""
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${monName}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${wsId}})';`
                }
            }
            if (batch.length > 0) {
                Quickshell.execDetached(["bash", "-c", batch])
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    Process {
        id: lockThemeProc
        command: ["bash", "-c",
            `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "dark" : "light"} --colors_lock --image '${Config.options.background.lockWall}'`
        ]
        onExited: {
            MaterialThemeLoader.useLockTheme()
            root.lastProcessedLockWall = Config.options.background.lockWall
            root.lastProcessedDarkmode = Appearance.m3colors.darkmode
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                captureKeyboardLayoutProc.running = true
                var wallChanged = Config.options.background.lockWall !== root.lastProcessedLockWall
                var modeChanged = Appearance.m3colors.darkmode !== root.lastProcessedDarkmode

                if (Config.options.background.lockWall !== "" && (wallChanged || modeChanged)) {
                    lockThemeProc.running = true
                } else if (Config.options.background.lockWall !== "") {
                    MaterialThemeLoader.useLockTheme()
                }
                
                if (WM.compositor === "niri") {
                    return;
                }

                var next = {}
                var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            } else {
                root.restoreKeyboardLayout()
                if (Config.options.background.lockWall !== "") {
                    MaterialThemeLoader.useLiveTheme()
                    MonitorThemes.refresh()
                }
                if (WM.compositor !== "niri") {
                    restoreTimer.start()
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}
