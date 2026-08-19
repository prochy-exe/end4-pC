pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
        signal reopenRequested()

    property string searchQuery: ""
    property list<var> items: []
    property int revision: 0
    property string status: "idle" // idle | checking | searching | ready | error | locked | unauthenticated | missing-cli | timeout
    property string lastError: ""
    property int searchGeneration: 0
    property int fetchGeneration: 0
    property int authGeneration: 0
    property string authState: "unknown" // unknown | unlocked | locked | unauthenticated | missing-cli | timeout | error
    property real authLastCheckedMs: 0
    property real vaultCacheLastFetchedMs: 0
    property bool searchPending: false
    property bool warmupRequested: false
    property var lastInteractedItem: ({})
    property list<var> allItems: []
    property string runtimeSessionToken: ""
    property bool reopenMenuAfterUnlock: false
    property real clipboardLastChangedMs: 0
    property real lastBitwardenClipboardWriteMs: 0
    property string lastBitwardenClipboardText: ""
    property string pendingTotpClipboardText: ""
    property int totpSecondsRemaining: 30
    readonly property string sessionToken: root.runtimeSessionToken.length > 0
        ? root.runtimeSessionToken
        : (KeyringStorage.keyringData?.bitwarden?.session ?? "")

    readonly property var totpConfig: Config.options.search.bitwardenTotp

    function updateTotpCountdown() {
        const now = Math.floor(Date.now() / 1000)
        const remainder = now % 30
        const remaining = remainder === 0 ? 30 : (30 - remainder)
        root.totpSecondsRemaining = remaining
    }

    function canOverwriteClipboardForTotp() {
        if (!(root.totpConfig?.protectRecentClipboard ?? true))
            return true

        const thresholdSec = Math.max(1, root.totpConfig?.protectRecentClipboardSeconds ?? 8)
        const elapsedMs = Date.now() - root.clipboardLastChangedMs
        if (elapsedMs >= thresholdSec * 1000)
            return true

        const current = `${Quickshell.clipboardText ?? ""}`
        const recentlyBitwardenOwned = (Date.now() - root.lastBitwardenClipboardWriteMs) < thresholdSec * 1000
            && current === root.lastBitwardenClipboardText
        return recentlyBitwardenOwned || current.length === 0
    }

    function trackBitwardenClipboardWrite(text) {
        const safe = `${text ?? ""}`
        root.lastBitwardenClipboardText = safe
        root.lastBitwardenClipboardWriteMs = Date.now()
        root.clipboardLastChangedMs = root.lastBitwardenClipboardWriteMs
    }

    function copyText(text, fromBitwarden) {
        const safe = `${text ?? ""}`
        if (!!fromBitwarden)
            root.trackBitwardenClipboardWrite(safe)
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(safe)}' | wl-copy`])
    }

    function showHelpForCurrentState() {
        switch (root.status) {
        case "locked":
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Vault is locked. Run <tt>bw unlock</tt> in a terminal, then retry search."), "-a", "Shell"])
            break
        case "unauthenticated":
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Not logged in. Run <tt>bw login</tt> (or <tt>bw login --apikey</tt>), then <tt>bw unlock</tt>."), "-a", "Shell"])
            break
        case "missing-cli":
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Bitwarden CLI not found. Install <tt>bw</tt> and try again."), "-a", "Shell"])
            break
        case "timeout":
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Bitwarden command timed out. If waiting for input, run <tt>bw unlock</tt> in a terminal and retry."), "-a", "Shell"])
            break
        default:
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), root.lastError.length > 0 ? root.lastError : Translation.tr("Bitwarden search failed"), "-a", "Shell"])
            break
        }
    }

    function copyUnlockCommand() {
        root.copyText("bw unlock", false)
        Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Copied: bw unlock"), "-a", "Shell"])
    }

    function copyLoginCommand() {
        root.copyText("bw login", false)
        Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Copied: bw login"), "-a", "Shell"])
    }

    function copyUsername(username) {
        root.copyText(username, false)
    }

    function setLastInteracted(item) {
        if (!item) return
        const normalized = {
            id: `${item.id ?? ""}`,
            name: `${item.name ?? "(unnamed)"}`,
            username: `${item.username ?? ""}`,
            hasTotp: !!item.hasTotp,
        }
        if (normalized.id.length === 0)
            return
        root.lastInteractedItem = normalized
        root.revision += 1
    }

    function saveSessionToken(token) {
        const clean = `${token ?? ""}`.trim()
        root.runtimeSessionToken = clean
        KeyringStorage.setNestedField(["bitwarden", "session"], clean)
    }

    function clearSessionToken(silent) {
        const quiet = !!silent
        root.runtimeSessionToken = ""
        root.saveSessionToken("")
        if (!quiet)
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Stored Bitwarden session cleared"), "-a", "Shell"])
    }

    function unlockFromMenu(reopenMenu) {
        root.reopenMenuAfterUnlock = !!reopenMenu
        if (!KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData()

        if (unlockProc.running) return
        unlockProc.buffer = ""
        unlockProc.running = true
    }

    function copyPassword(itemId) {
        if (!itemId || itemId.length === 0) {
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Missing item id"), "-a", "Shell"])
            return
        }
        const sid = StringUtils.shellSingleQuoteEscape(root.sessionToken)
        const item = StringUtils.shellSingleQuoteEscape(itemId)
        const cmd = root.sessionToken.length > 0
            ? `export BW_SESSION='${sid}'; bw get password '${item}' | wl-copy`
            : `bw get password '${item}' | wl-copy`
        Quickshell.execDetached(["bash", "-c", cmd])
    }

    function copyTotp(itemId, hasTotp) {
        if (!hasTotp) {
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("No verification code on this item"), "-a", "Shell"])
            return
        }
        if (!itemId || itemId.length === 0) {
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Missing item id"), "-a", "Shell"])
            return
        }
        if (!root.canOverwriteClipboardForTotp()) {
            const protectWindow = Math.max(1, root.totpConfig?.protectRecentClipboardSeconds ?? 8)
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Clipboard was updated recently (< %1s). TOTP copy skipped.").arg(protectWindow), "-a", "Shell"])
            return
        }

        if (totpProc.running) {
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Already fetching verification code"), "-a", "Shell"])
            return
        }

        totpProc.itemId = itemId
        totpProc.buffer = ""
        totpProc.errBuffer = ""
        const envObject = root.sessionToken.length > 0 ? ({ BW_SESSION: root.sessionToken }) : ({})
        totpProc.exec({
            command: ["bw", "get", "totp", itemId],
            environment: envObject
        })
    }

    function triggerSearch(query) {
        if ((query ?? "") === root.searchQuery) return
        root.searchQuery = query ?? ""
    }

    function normalizeVaultItems(parsed) {
        return Array.isArray(parsed) ? parsed.map(item => {
            const login = item?.login ?? {}
            return {
                id: item?.id ?? "",
                name: item?.name ?? "(unnamed)",
                username: login?.username ?? "",
                hasTotp: !!login?.totp,
            }
        }) : []
    }

    function filterCachedItems(query) {
        const q = `${query ?? ""}`.trim().toLowerCase()
        if (q.length === 0) {
            root.items = []
            root.status = "ready"
            root.lastError = ""
            root.revision += 1
            return
        }

        const tokens = q.split(/\s+/).filter(Boolean)
        const filtered = root.allItems.filter(item => {
            const haystack = `${item?.name ?? ""} ${item?.username ?? ""}`.toLowerCase()
            for (const token of tokens) {
                if (!haystack.includes(token)) return false
            }
            return true
        })

        root.items = filtered
        root.status = "ready"
        root.lastError = ""
        root.revision += 1
    }

    function vaultCacheFresh() {
        return (Date.now() - root.vaultCacheLastFetchedMs) < 120000
    }

    function fetchVaultItems(force) {
        const mustForce = !!force
        if (root.authState !== "unlocked") return
        if (fetchProc.running) {
            root.searchPending = true
            return
        }
        if (!mustForce && root.allItems.length > 0 && root.vaultCacheFresh()) {
            root.filterCachedItems(root.searchQuery)
            return
        }

        root.fetchGeneration += 1
        fetchProc.generation = root.fetchGeneration
        fetchProc.buffer = ""
        fetchProc.errBuffer = ""
        root.status = "searching"

        const envObject = root.sessionToken.length > 0 ? ({ BW_SESSION: root.sessionToken }) : ({})
        fetchProc.exec({
            command: ["bw", "list", "items"],
            environment: envObject
        })
    }

    function prepareForBitwardenMode() {
        root.warmupRequested = true
        root.preflightAuth(false)
        if (root.authState === "unlocked") {
            root.fetchVaultItems(false)
        }
    }

    function authIsFresh() {
        return (Date.now() - root.authLastCheckedMs) < 15000
    }

    function preflightAuth(force) {
        const mustForce = !!force
        if (authProc.running) return
        if (root.sessionToken.length > 0) {
            root.authState = "unlocked"
            root.status = "idle"
            root.lastError = ""
            root.authLastCheckedMs = Date.now()
            root.revision += 1
            if (root.warmupRequested) {
                root.warmupRequested = false
                root.fetchVaultItems(false)
            }
            return
        }
        if (!mustForce && root.authIsFresh()) return

        root.authGeneration += 1
        authProc.generation = root.authGeneration
        authProc.buffer = ""
        authProc.errBuffer = ""
        root.status = "checking"

        const envObject = root.sessionToken.length > 0 ? ({ BW_SESSION: root.sessionToken }) : ({})
        authProc.exec({
            command: ["bw", "status", "--raw"],
            environment: envObject
        })
    }

    function startSearch() {
        const q = (root.searchQuery ?? "").trim()
        if (q.length === 0) {
            root.filterCachedItems("")
            return
        }

        if (root.authState !== "unlocked") {
            root.preflightAuth(false)
            if (root.authState !== "unlocked") {
                return
            }
        }

        if (root.allItems.length === 0 || !root.vaultCacheFresh()) {
            root.fetchVaultItems(false)
            return
        }

        root.filterCachedItems(q)
    }

    Component.onCompleted: {
        if (!KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData()
        root.clipboardLastChangedMs = Date.now()
        root.updateTotpCountdown()
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            root.clipboardLastChangedMs = Date.now()
        }
    }

    Timer {
        id: totpCountdownTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.updateTotpCountdown()
    }

    Timer {
        id: totpAutoClearTimer
        interval: 20000
        repeat: false
        onTriggered: {
            const clipboardNow = `${Quickshell.clipboardText ?? ""}`
            if (clipboardNow === root.pendingTotpClipboardText && clipboardNow.length > 0) {
                root.copyText("", true)
                Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Cleared copied verification code from clipboard"), "-a", "Shell"])
            }
            root.pendingTotpClipboardText = ""
        }
    }

    Timer {
        id: debounceTimer
        interval: 90
        repeat: false
        onTriggered: root.startSearch()
    }

    onSearchQueryChanged: debounceTimer.restart()

    Process {
        id: fetchProc
        property int generation: 0
        property string buffer: ""
        property string errBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (fetchProc.buffer.length > 0)
                    fetchProc.buffer += "\n"
                fetchProc.buffer += data
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (fetchProc.errBuffer.length > 0)
                    fetchProc.errBuffer += "\n"
                fetchProc.errBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (fetchProc.generation !== root.fetchGeneration)
                return

            const stderrText = (fetchProc.errBuffer ?? "").trim().toLowerCase()

            if (stderrText.includes("not logged in") || stderrText.includes("unauthenticated")) {
                root.items = []
                root.allItems = []
                root.authState = "unauthenticated"
                root.status = "unauthenticated"
                root.lastError = Translation.tr("Not logged in. Run bw login, then bw unlock.")
                root.clearSessionToken(true)
                root.authLastCheckedMs = Date.now()
                root.revision += 1
                if (root.searchPending) {
                    root.searchPending = false
                    root.fetchVaultItems(true)
                }
                return
            }

            if (stderrText.includes("locked")) {
                root.items = []
                root.allItems = []
                root.authState = "locked"
                root.status = "locked"
                root.lastError = Translation.tr("Vault is locked. Run bw unlock in a terminal, then retry.")
                root.clearSessionToken(true)
                root.authLastCheckedMs = Date.now()
                root.revision += 1
                if (root.searchPending) {
                    root.searchPending = false
                    root.fetchVaultItems(true)
                }
                return
            }

            if (exitCode !== 0) {
                root.items = []
                root.allItems = []
                root.status = "error"
                root.lastError = fetchProc.errBuffer.trim().length > 0
                    ? fetchProc.errBuffer.trim()
                    : Translation.tr("Bitwarden command failed")
                root.revision += 1
                if (root.searchPending) {
                    root.searchPending = false
                    root.fetchVaultItems(true)
                }
                return
            }

            try {
                const parsed = JSON.parse(fetchProc.buffer.trim() || "[]")
                root.allItems = root.normalizeVaultItems(parsed)
                root.authState = "unlocked"
                root.status = "searching"
                root.lastError = ""
                root.authLastCheckedMs = Date.now()
                root.vaultCacheLastFetchedMs = Date.now()
                root.revision += 1

                root.filterCachedItems(root.searchQuery)

                if (root.searchPending) {
                    root.searchPending = false
                    root.filterCachedItems(root.searchQuery)
                }
            } catch (e) {
                root.items = []
                root.allItems = []
                root.status = "error"
                root.lastError = Translation.tr("Failed to parse Bitwarden output")
                root.revision += 1

                if (root.searchPending) {
                    root.searchPending = false
                    root.fetchVaultItems(true)
                }
            }
        }
    }

    Process {
        id: authProc
        property int generation: 0
        property string buffer: ""
        property string errBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (authProc.buffer.length > 0)
                    authProc.buffer += "\n"
                authProc.buffer += data
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (authProc.errBuffer.length > 0)
                    authProc.errBuffer += "\n"
                authProc.errBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (authProc.generation !== root.authGeneration)
                return

            const output = (authProc.buffer ?? "").trim()
            const err = (authProc.errBuffer ?? "").trim().toLowerCase()
            root.authLastCheckedMs = Date.now()

            if (err.includes("command not found") || err.includes("no such file") || err.includes("not found")) {
                root.authState = "missing-cli"
                root.status = "missing-cli"
                root.lastError = Translation.tr("Bitwarden CLI (bw) is not installed")
                root.revision += 1
                return
            }

            let state = ""
            try {
                state = (JSON.parse(output || "{}").status ?? "").toLowerCase()
            } catch (e) {
                const text = (output + "\n" + err).toLowerCase()
                if (text.includes("locked")) state = "locked"
                else if (text.includes("not logged in") || text.includes("unauthenticated")) state = "unauthenticated"
                else if (text.includes("unlocked")) state = "unlocked"
            }

            if (state === "unlocked") {
                root.authState = "unlocked"
                if (root.status === "checking")
                    root.status = "idle"
                root.lastError = ""
                root.revision += 1
                if (root.warmupRequested) {
                    root.warmupRequested = false
                    root.fetchVaultItems(false)
                }
                if ((root.searchQuery ?? "").trim().length > 0) {
                    root.startSearch()
                }
                return
            }

            if (state === "locked") {
                root.authState = "locked"
                root.status = "locked"
                root.lastError = Translation.tr("Vault is locked. Unlock to search Bitwarden.")
                root.revision += 1
                return
            }

            if (state === "unauthenticated") {
                root.authState = "unauthenticated"
                root.status = "unauthenticated"
                root.lastError = Translation.tr("Not logged in. Run bw login, then unlock.")
                root.revision += 1
                return
            }

            if (exitCode !== 0) {
                root.authState = "error"
                root.status = "error"
                root.lastError = err.length > 0 ? err : Translation.tr("Bitwarden status check failed")
                root.revision += 1
                return
            }

            root.authState = "error"
            root.status = "error"
            root.lastError = Translation.tr("Unexpected Bitwarden status output")
            root.revision += 1
        }
    }

    Process {
        id: unlockProc
        property string buffer: ""
        command: ["bash", "-c", [
            "set -e",
            "if command -v zenity >/dev/null 2>&1; then",
            "  pw=$(zenity --password --title='Bitwarden Unlock') || exit 22",
            "elif command -v kdialog >/dev/null 2>&1; then",
            "  pw=$(kdialog --password 'Bitwarden master password') || exit 22",
            "else",
            "  echo '__error__::No GUI password prompt found (zenity/kdialog)'",
            "  exit 0",
            "fi",
            "if [ -z \"$pw\" ]; then exit 22; fi",
            "if ! session=$(BW_PASSWORD=\"$pw\" bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); then",
            "  echo '__error__::Unlock failed. Check password or run bw login first.'",
            "  exit 0",
            "fi",
            "printf '%s' \"$session\""
        ].join("\n")]

        stdout: SplitParser {
            onRead: data => {
                unlockProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            const output = (unlockProc.buffer ?? "").trim()
            unlockProc.buffer = ""

            if (exitCode === 22) {
                root.reopenMenuAfterUnlock = false
                root.lastError = Translation.tr("Unlock cancelled")
                root.status = "locked"
                root.revision += 1
                return
            }

            if (output.startsWith("__error__::")) {
                root.reopenMenuAfterUnlock = false
                root.lastError = output.slice("__error__::".length)
                root.status = "error"
                root.revision += 1
                Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), root.lastError, "-a", "Shell"])
                return
            }

            if (output.length > 0) {
                root.saveSessionToken(output)
                root.authState = "unlocked"
                root.authLastCheckedMs = Date.now()
                root.lastError = ""
                root.status = "ready"
                root.revision += 1
                Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Vault unlocked for this shell session"), "-a", "Shell"])
                if (root.reopenMenuAfterUnlock) {
                    root.reopenMenuAfterUnlock = false
                    Qt.callLater(() => root.reopenRequested())
                }
                root.fetchVaultItems(true)
                root.startSearch()
                return
            }

            root.lastError = Translation.tr("Unlock failed")
            root.status = "error"
            root.reopenMenuAfterUnlock = false
            root.revision += 1
        }
    }

    Process {
        id: totpProc
        property string itemId: ""
        property string buffer: ""
        property string errBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (totpProc.buffer.length > 0)
                    totpProc.buffer += "\n"
                totpProc.buffer += data
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (totpProc.errBuffer.length > 0)
                    totpProc.errBuffer += "\n"
                totpProc.errBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            const code = `${totpProc.buffer ?? ""}`.trim()
            const err = `${totpProc.errBuffer ?? ""}`.trim()

            if (exitCode !== 0 || code.length === 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), err.length > 0 ? err : Translation.tr("Failed to fetch verification code"), "-a", "Shell"])
                return
            }

            root.copyText(code, true)

            if (root.totpConfig?.autoClearClipboard ?? false) {
                const clearSeconds = Math.max(1, root.totpConfig?.autoClearSeconds ?? 20)
                root.pendingTotpClipboardText = code
                totpAutoClearTimer.interval = clearSeconds * 1000
                totpAutoClearTimer.restart()
            }
        }
    }
}
