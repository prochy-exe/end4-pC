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

    // A persistent local `bw serve` API replaces spawning a fresh `bw` CLI
    // process (~2.8s Node startup) for every single status/vault check.
    // Once warm, checks are a ~10-20ms HTTP call instead. As a side effect
    // this also removes the interactive-prompt-hang bug class entirely: an
    // HTTP request always gets a response or a connection error, it can
    // never block on a stdin prompt the way a raw `bw` invocation could.
    readonly property int servePort: 25787
    readonly property string serveBaseUrl: `http://127.0.0.1:${root.servePort}`
    property bool serveReady: false
    property int serveFailStreak: 0

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

    // Unlock directly from a password typed into the shell's own search
    // field (or forwarded from the zenity/kdialog prompt in unlockFromMenu()
    // -- both funnel through here), via bw serve's /unlock endpoint instead
    // of spawning a fresh `bw unlock` CLI process.
    //
    // The password is passed via an environment variable, then written to a
    // private 0600 temp file (under XDG_RUNTIME_DIR, a tmpfs) for curl to
    // read as `-d @file`, deleted immediately after. Originally this wrote
    // the JSON body over stdin instead (`curl -d @-`), which avoided a temp
    // file, but that hung indefinitely in practice: Process.stdinEnabled set
    // to false *after* already-true did not reliably close/EOF the pipe, so
    // curl (reading -d @- fully before sending anything) blocked forever
    // waiting for more input that never came -- confirmed directly, found a
    // real curl process still alive and blocked on an open stdin pipe
    // minutes later. A real file has an unambiguous EOF at its actual end,
    // sidestepping that unreliable close-the-pipe mechanism entirely. An env
    // var doesn't show up in `ps`/cmdline for other processes either, same
    // exposure level bw's own --passwordenv already uses.
    function unlockWithPassword(password) {
        const pw = `${password ?? ""}`
        if (pw.length === 0) return
        // Diagnostic only, never logs the password itself: confirms whether
        // a stale "!" mode-switch prefix is still glued to the front of what
        // gets submitted (see the onTextChanged comment in SearchBar.qml).
        console.warn(`[BWDebug] unlock attempt: length=${pw.length} startsWithModePrefix=${pw.startsWith(Config.options.search.prefix.bitwarden)}`)
        if (!KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData()
        if (inlineUnlockProc.running) return

        inlineUnlockProc.buffer = ""
        root.status = "checking"
        inlineUnlockProc.exec({
            command: ["bash", "-c", [
                "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\")",
                "chmod 600 \"$f\"",
                "python3 -c \"import json,os; open('$f','w').write(json.dumps({'password': os.environ['BW_UNLOCK_PASSWORD']}))\"",
                `curl -s --max-time 10 -X POST -H 'Content-Type: application/json' -d @"$f" ${root.serveBaseUrl}/unlock`,
                "code=$?",
                "rm -f \"$f\"",
                "exit $code"
            ].join("\n")],
            environment: { BW_UNLOCK_PASSWORD: pw }
        })
    }

    function copyPassword(itemId) {
        if (!itemId || itemId.length === 0) {
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), Translation.tr("Missing item id"), "-a", "Shell"])
            return
        }
        // Via bw serve instead of a fresh `bw get password` CLI process --
        // instant instead of ~2.8s, and immune to the interactive-prompt hang
        // a stale session used to risk (see the note on servePort above).
        const item = StringUtils.shellSingleQuoteEscape(encodeURIComponent(itemId))
        Quickshell.execDetached(["bash", "-c",
            `curl -s --max-time 5 '${root.serveBaseUrl}/object/password/${item}' | jq -j '.data.data // empty' | wl-copy`])
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
        totpProc.exec({
            command: ["curl", "-s", "--max-time", "5", `${root.serveBaseUrl}/object/totp/${encodeURIComponent(itemId)}`]
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
        root.status = "searching"

        fetchProc.exec({
            command: ["curl", "-s", "--max-time", "5", `${root.serveBaseUrl}/list/object/items`]
        })
    }

    function prepareForBitwardenMode() {
        root.warmupRequested = true
        root.preflightAuth()
        if (root.authState === "unlocked") {
            root.fetchVaultItems(false)
        }
    }

    // Status checks are now a ~10-20ms local HTTP call (see servePort above),
    // so there's no longer a real cost to just always doing a fresh one --
    // the old 15s "is this still fresh" cache and its blind
    // trust-the-stored-token-without-checking fast path both existed
    // specifically to avoid paying bw's ~2.8s CLI startup on every check.
    // Removing the blind-trust path also closes the correctness gap that
    // caused the original endless-spinner bug: a stale token no longer skips
    // straight to fetchVaultItems() unverified.
    function preflightAuth() {
        if (authProc.running) return

        if (!root.serveReady) {
            root.status = "checking"
            serveAuthRetryTimer.restart()
            return
        }

        root.authGeneration += 1
        authProc.generation = root.authGeneration
        authProc.buffer = ""
        root.status = "checking"
        authProc.exec({
            command: ["curl", "-s", "--max-time", "5", `${root.serveBaseUrl}/status`]
        })
    }

    function startSearch() {
        const q = (root.searchQuery ?? "").trim()

        // Auth state must be checked before the empty-query shortcut, not
        // after: filterCachedItems("") unconditionally sets status="ready",
        // which would stomp a real "locked"/"unauthenticated"/etc status.
        // With bw serve's ~10-20ms checks, this debounced empty-query call
        // now regularly lands *after* preflightAuth() has already resolved
        // the real status (it used to always land first, back when a check
        // took ~2.8s) -- so the ordering here actually matters now.
        if (root.authState !== "unlocked") {
            root.preflightAuth()
            if (root.authState !== "unlocked") {
                if (q.length === 0)
                    root.items = []
                return
            }
        }

        if (q.length === 0) {
            root.filterCachedItems("")
            return
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

    Timer {
        id: serveAuthRetryTimer
        interval: 150
        repeat: false
        onTriggered: root.preflightAuth()
    }

    // Polls for an already-running `bw serve` first (e.g. left over from
    // before a config reload -- this whole singleton, including serveProc
    // below, gets torn down and recreated on every quickshell reload) and
    // only spawns a new one if nothing answers after ~800ms. Avoids ever
    // accumulating duplicate `bw serve` processes fighting over servePort.
    Timer {
        id: serveReadyPoll
        interval: 200
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            if (root.serveReady) {
                stop()
                return
            }
            ticks += 1
            if (ticks >= 4 && !serveProc.running)
                serveProc.running = true
            if (!serveProbe.running)
                serveProbe.running = true
        }
    }

    Process {
        id: serveProbe
        command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1", `${root.serveBaseUrl}/status`]
        stdout: StdioCollector {
            onStreamFinished: {
                const code = text.trim()
                if (code.length > 0 && code !== "000") {
                    root.serveReady = true
                    root.serveFailStreak = 0
                    serveReadyPoll.stop()
                }
            }
        }
    }

    Process {
        id: serveProc
        property string errBuffer: ""

        // If a still-valid session happens to already be saved (see
        // sessionToken above), bw appears to pick up a pre-set BW_SESSION
        // from its own environment at startup too (getSessionKey() in the
        // installed CLI's source reads process.env.BW_SESSION generically,
        // not just from the one-shot `bw <cmd>` path) -- not confirmed with
        // a real end-to-end unlock yet, but harmless if it turns out not to:
        // worst case we just start locked and the inline unlock prompt
        // handles it same as a first-ever unlock.
        environment: root.sessionToken.length > 0 ? ({ BW_SESSION: root.sessionToken }) : ({})
        // --hostname localhost resolved IPv6-only ([::1]) on this system,
        // while serveBaseUrl above (and every curl call using it) hits
        // 127.0.0.1 explicitly -- so the server was up and perfectly healthy
        // but genuinely unreachable at the address anything ever asked for.
        // Confirmed directly: `ss -tlnp` showed it bound to [::1] only, and
        // curl to 127.0.0.1 got connection-refused while curl to `localhost`
        // (which happened to resolve to ::1 first on this machine) worked --
        // which is exactly what made this so easy to miss while testing.
        command: ["bw", "serve", "--hostname", "127.0.0.1", "--port", `${root.servePort}`]

        stderr: SplitParser {
            onRead: data => {
                if (serveProc.errBuffer.length > 0)
                    serveProc.errBuffer += "\n"
                serveProc.errBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            const wasReady = root.serveReady
            root.serveReady = false

            const err = serveProc.errBuffer.toLowerCase()
            serveProc.errBuffer = ""
            if (err.includes("command not found") || err.includes("no such file") || err.includes("not found")) {
                root.authState = "missing-cli"
                root.status = "missing-cli"
                root.lastError = Translation.tr("Bitwarden CLI (bw) is not installed")
                root.revision += 1
                return
            }

            root.serveFailStreak = wasReady ? 0 : root.serveFailStreak + 1
            if (root.serveFailStreak > 3) {
                root.authState = "error"
                root.status = "error"
                root.lastError = Translation.tr("Bitwarden helper (bw serve) keeps failing to start")
                root.revision += 1
                return
            }
            serveRestartTimer.restart()
        }
    }

    Timer {
        id: serveRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            serveReadyPoll.ticks = 0
            serveReadyPoll.restart()
        }
    }

    Process {
        id: fetchProc
        property int generation: 0
        property string buffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (fetchProc.buffer.length > 0)
                    fetchProc.buffer += "\n"
                fetchProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (fetchProc.generation !== root.fetchGeneration)
                return

            if (exitCode !== 0) {
                root.items = []
                root.allItems = []
                root.status = "error"
                root.lastError = Translation.tr("Could not reach the local Bitwarden helper")
                root.revision += 1
                if (root.searchPending) {
                    root.searchPending = false
                    root.fetchVaultItems(true)
                }
                return
            }

            try {
                const response = JSON.parse(fetchProc.buffer.trim() || "{}")

                if (response.success === false) {
                    const message = `${response.message ?? ""}`
                    const messageLower = message.toLowerCase()
                    root.items = []
                    root.allItems = []
                    if (messageLower.includes("locked")) {
                        root.authState = "locked"
                        root.status = "locked"
                        root.lastError = Translation.tr("Vault is locked. Unlock to search Bitwarden.")
                        root.clearSessionToken(true)
                    } else if (messageLower.includes("not logged in") || messageLower.includes("unauthenticated")) {
                        root.authState = "unauthenticated"
                        root.status = "unauthenticated"
                        root.lastError = Translation.tr("Not logged in. Run bw login, then bw unlock.")
                        root.clearSessionToken(true)
                    } else {
                        root.status = "error"
                        root.lastError = message.length > 0 ? message : Translation.tr("Bitwarden command failed")
                    }
                    root.authLastCheckedMs = Date.now()
                    root.revision += 1
                    if (root.searchPending) {
                        root.searchPending = false
                        root.fetchVaultItems(true)
                    }
                    return
                }

                root.allItems = root.normalizeVaultItems(response.data?.data ?? [])
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

        stdout: SplitParser {
            onRead: data => {
                if (authProc.buffer.length > 0)
                    authProc.buffer += "\n"
                authProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (authProc.generation !== root.authGeneration)
                return

            root.authLastCheckedMs = Date.now()

            if (exitCode !== 0) {
                root.authState = "error"
                root.status = "error"
                root.lastError = Translation.tr("Could not reach the local Bitwarden helper")
                root.revision += 1
                return
            }

            let state = ""
            try {
                state = `${JSON.parse(authProc.buffer.trim() || "{}").data?.template?.status ?? ""}`.toLowerCase()
            } catch (e) {
                state = ""
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

            root.authState = "error"
            root.status = "error"
            root.lastError = Translation.tr("Unexpected Bitwarden status output")
            root.revision += 1
        }
    }

    Process {
        id: unlockProc
        property string buffer: ""
        // Only captures the password via an external GUI prompt now -- the
        // actual unlock is done by unlockWithPassword() below, over
        // bw serve, same as the inline field. Doing it there instead of a
        // separate `bw unlock` CLI call here keeps both unlock paths
        // consistent and means bw serve's own in-memory session actually
        // gets updated (a `bw unlock` run standalone here would only update
        // the saved session token, leaving the already-running serve
        // instance still thinking it's locked).
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
            "printf '%s' \"$pw\""
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
                root.unlockWithPassword(output)
                return
            }

            root.lastError = Translation.tr("Unlock failed")
            root.status = "error"
            root.reopenMenuAfterUnlock = false
            root.revision += 1
        }
    }

    Process {
        id: inlineUnlockProc
        property string buffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (inlineUnlockProc.buffer.length > 0)
                    inlineUnlockProc.buffer += "\n"
                inlineUnlockProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            const output = (inlineUnlockProc.buffer ?? "").trim()
            inlineUnlockProc.buffer = ""

            if (exitCode === 0) {
                try {
                    const response = JSON.parse(output || "{}")
                    const token = `${response.data?.raw ?? ""}`
                    if (response.success && token.length > 0) {
                        root.saveSessionToken(token)
                        root.authState = "unlocked"
                        root.authLastCheckedMs = Date.now()
                        root.lastError = ""
                        root.status = "idle"
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
                    root.authState = "locked"
                    root.status = "locked"
                    root.lastError = `${response.message ?? ""}`.length > 0
                        ? response.message
                        : Translation.tr("Unlock failed. Check your master password.")
                    root.reopenMenuAfterUnlock = false
                    root.revision += 1
                    Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), root.lastError, "-a", "Shell"])
                    return
                } catch (e) {
                    // fall through to the generic error below
                }
            }

            root.authState = "locked"
            root.status = "locked"
            root.lastError = Translation.tr("Unlock failed. Check your master password.")
            root.reopenMenuAfterUnlock = false
            root.revision += 1
            Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), root.lastError, "-a", "Shell"])
        }
    }

    Process {
        id: totpProc
        property string itemId: ""
        property string buffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (totpProc.buffer.length > 0)
                    totpProc.buffer += "\n"
                totpProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            let code = ""
            let errorMessage = ""
            if (exitCode === 0) {
                try {
                    const response = JSON.parse(totpProc.buffer.trim() || "{}")
                    if (response.success) code = `${response.data?.data ?? ""}`.trim()
                    else errorMessage = `${response.message ?? ""}`
                } catch (e) {
                    errorMessage = ""
                }
            }

            if (code.length === 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Bitwarden"), errorMessage.length > 0 ? errorMessage : Translation.tr("Failed to fetch verification code"), "-a", "Shell"])
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
