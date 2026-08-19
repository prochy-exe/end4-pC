import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    // Keep clipboard service alive so Smart Paste auto-rewrite runs globally.
    readonly property var _cliphistBootstrap: Cliphist
    property bool barOpen: true
    property bool cheatsheetOpen: false
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool mediaTickerOpen: false
    property bool osdBrightnessOpen: false
    property bool settingsOpen: false
    property bool osdVolumeOpen: false
    property bool popupEditorOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property string settingsPage: ""
    property Item currentPageInstance: null
    property string sidebarLeftRequestedTab: ""
    property string sidebarLeftTranslatorPrefill: ""
    property int sidebarLeftTranslatorPrefillNonce: 0
    property bool sidebarLeftTranslatorPrefillArmed: false
    property int sidebarLeftTranslatorResetNonce: 0
    property bool ocrActionsPopupOpen: false
    property list<real> visualizerPoints: []
    property list<real> visualizerOutputPoints: []
    property list<real> visualizerInputPoints: []
    property string lastOcrText: ""
    property real lastOcrCapturedMs: 0
    property bool desktopWidgetKeyboardFocus: false
    property bool desktopMenuOpen: false
    property var desktopMenuScreen: null
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    property string wallpaperSelectorTarget: "wallpaper"
    property bool dropShelfOpen: false
    property real dropShelfX: 0
    property real dropShelfY: 0

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }

    IpcHandler {
        target: "background"
        function toggleCenteredWallpaper(): void {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }

    GlobalShortcut {
        name: "centeredWallpaperToggle"
        description: "Toggles centered wallpaper"
        onPressed: {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }
}