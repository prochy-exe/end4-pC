pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            id: lockSurfaceLoader
            active: GlobalStates.screenLocked
            anchors.fill: parent
            property var sessionScreen: sessionLockSurface.screen
            onLoaded: if (item) item.sessionScreen = sessionScreen
            onSessionScreenChanged: {
                if (item) item.sessionScreen = sessionScreen
            }
            opacity: active ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface
        }
        onScreenChanged: {
            lockSurfaceLoader.sessionScreen = screen
            if (lockSurfaceLoader.item) lockSurfaceLoader.item.sessionScreen = screen
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
            keyringDebugCheckProc.running = true;
        }
    }
    Process {
        id: keyringDebugCheckProc
        command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/is_unlocked.sh")]
        onExited: (exitCode, exitStatus) => {
        }
    }
    function unlockKeyring() {
        // Fingerprint unlock never sees a password (currentText is empty in that
        // case) - fall back to the last one typed successfully this session.
        const password = lockContext.currentText.length > 0
            ? lockContext.currentText
            : lockContext.lastKnownPassword
        if (password.length === 0) return
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": password
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            GlobalStates.screenLocked = false;

            // Reset
            lockContext.reset();

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
        onSecureChanged: {
            if (lock.secure) GlobalStates.startupLockPending = false;
        }
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    CompositorGlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    CompositorGlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
            // hypridle's after_sleep_cmd can fire before Hyprland has fully
            // re-initialized outputs that were powered off during sleep, so a
            // single immediate refocus can silently miss those - their lock
            // surface is left showing a stale buffer until something else (e.g.
            // a mouse move) nudges the compositor into recompositing them.
            // Retry once shortly after as a safety net.
            wakeRefocusRetryTimer.restart();
        }
    }

    Timer {
        id: wakeRefocusRetryTimer
        interval: 500
        onTriggered: {
            lockContext.shouldReFocus()
        }
    }

    Process {
        id: keyringLockedCheckProc
        command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/is_unlocked.sh")]
        onExited: (exitCode, exitStatus) => {
            // hyprlock has no wiring to KeyringStorage's unlock flow, so locking
            // via it here wouldn't actually unlock the keyring - skip in that
            // case rather than show a lock screen that doesn't help.
            if (exitCode !== 0 && !Config.options.lock.useHyprlock) {
                // Keyring is still locked and nothing else unlocked it (e.g. via
                // screen unlock) since this Hyprland instance started - show the
                // lock screen so entering the password also unlocks the keyring,
                // instead of leaving it to whichever app first queries a secret
                // (which would otherwise trigger gnome-keyring's own popup).
                GlobalStates.screenLocked = true;
            } else {
                KeyringStorage.fetchKeyringData();
            }
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else if (Config.options.lock.security.unlockKeyring && Persistent.isNewHyprlandInstance) {
            keyringLockedCheckProc.running = true;
        } else {
            KeyringStorage.fetchKeyringData();
            GlobalStates.startupLockPending = false;
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }

    Component.onCompleted: {
        root.initIfReady();
    }
}
