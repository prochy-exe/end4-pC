pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property bool videoProcessingEnabled: Config.options?.search?.clipboardVideoProcessing ?? true
    property list<string> rawEntries: []
    property list<string> entries: []
    property int pinRevision: 0
    property int videoMetadataRevision: 0
    property real suppressAutoRewriteUntilMs: 0
    property string lastObservedClipboardText: ""
    property var videoMetadataByEntryKey: ({})
    readonly property list<string> pinnedEntryKeys: Config.options?.search?.clipboardPinnedEntries ?? []
    readonly property var smartPasteConfig: Config.options?.search?.clipboardSmartPaste ?? ({})
    readonly property bool smartPasteEnabled: root.smartPasteConfig.enable ?? true
    readonly property bool smartPasteStripTrackingParams: root.smartPasteConfig.stripTrackingParams ?? true
    readonly property bool smartPasteRewriteSocialEmbeds: root.smartPasteConfig.rewriteSocialEmbeds ?? true
    readonly property bool smartPasteAutoRewriteClipboardOnCopy: root.smartPasteConfig.autoRewriteClipboardOnCopy ?? true
    readonly property bool smartPasteRewriteXTwitter: root.smartPasteConfig.rewriteXTwitter ?? true
    readonly property bool smartPasteRewriteInstagram: root.smartPasteConfig.rewriteInstagram ?? true
    readonly property string smartPasteXTwitterReplacementDomain: root.smartPasteConfig.xTwitterReplacementDomain ?? "fxtwitter.com"
    readonly property string smartPasteInstagramReplacementDomain: root.smartPasteConfig.instagramReplacementDomain ?? "vxinstagram.com"
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    readonly property list<string> knownTrackingParams: [
        "fbclid", "gclid", "dclid", "igshid", "mc_cid", "mc_eid", "ref_src", "ref_url", "si"
    ]

    Component.onCompleted: {
        root.lastObservedClipboardText = `${Quickshell.clipboardText ?? ""}`
        root.maybeRewriteClipboardText()
        if (root.autoRewriteEnabled() && !clipboardReadProc.running) {
            clipboardReadProc.command = ["bash", "-c", "wl-paste -n --type text 2>/dev/null || true"]
            clipboardReadProc.running = true
        }
    }

    function shouldApplySmartPaste(entry) {
        return root.smartPasteEnabled && !root.entryIsFileUri(entry) && !root.entryIsImage(entry)
    }

    function autoRewriteEnabled() {
        return root.smartPasteEnabled && root.smartPasteAutoRewriteClipboardOnCopy
    }

    function suspendAutoRewrite(durationMs = 1200) {
        root.suppressAutoRewriteUntilMs = Math.max(root.suppressAutoRewriteUntilMs, Date.now() + durationMs)
    }

    function stripTrailingPunctuation(urlToken) {
        const match = urlToken.match(/([.,!?;:)\]]+)$/)
        if (!match) {
            return { core: urlToken, suffix: "" }
        }
        const suffix = match[1]
        return {
            core: urlToken.slice(0, urlToken.length - suffix.length),
            suffix: suffix,
        }
    }

    function removeTrackingParams(queryString) {
        if (!root.smartPasteStripTrackingParams || queryString.length === 0) {
            return queryString
        }

        const kept = queryString.split("&").filter(part => {
            if (part.length === 0) return false
            const eqIndex = part.indexOf("=")
            const rawKey = eqIndex >= 0 ? part.slice(0, eqIndex) : part
            const key = decodeURIComponent(rawKey).toLowerCase()
            if (key.startsWith("utm_")) return false
            if (root.knownTrackingParams.includes(key)) return false
            return true
        })
        return kept.join("&")
    }

    function rewriteSocialHost(hostname) {
        if (!root.smartPasteRewriteSocialEmbeds) {
            return hostname
        }

        const sanitizeDomain = (value, fallbackValue) => {
            const candidate = `${value ?? ""}`.trim().toLowerCase()
            if (/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(candidate)) {
                return candidate
            }
            return fallbackValue
        }
        const twitterTarget = sanitizeDomain(root.smartPasteXTwitterReplacementDomain, "fxtwitter.com")
        const instagramTarget = sanitizeDomain(root.smartPasteInstagramReplacementDomain, "vxinstagram.com")

        const host = hostname.toLowerCase()
        if (root.smartPasteRewriteXTwitter && (
            host === "twitter.com" || host === "www.twitter.com" || host === "mobile.twitter.com"
            || host === "x.com" || host === "www.x.com" || host === "mobile.x.com"
        )) {
            return twitterTarget
        }

        if (root.smartPasteRewriteInstagram && (
            host === "instagram.com" || host === "www.instagram.com" || host === "m.instagram.com"
        )) {
            return instagramTarget
        }

        return hostname
    }

    function rewriteUrlToken(urlToken) {
        const parsed = root.stripTrailingPunctuation(urlToken)
        const core = parsed.core
        const suffix = parsed.suffix

        const match = core.match(/^(https?):\/\/([^\/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$/i)
        if (!match) {
            return urlToken
        }

        const scheme = match[1]
        const host = match[2]
        const path = match[3] ?? ""
        const queryPart = match[4] ? match[4].slice(1) : ""
        const fragment = match[5] ?? ""

        const rewrittenHost = root.rewriteSocialHost(host)
        const cleanedQuery = root.removeTrackingParams(queryPart)
        const finalQuery = cleanedQuery.length > 0 ? `?${cleanedQuery}` : ""
        return `${scheme}://${rewrittenHost}${path}${finalQuery}${fragment}${suffix}`
    }

    function rewriteBareSocialToken(urlToken) {
        const parsed = root.stripTrailingPunctuation(urlToken)
        const core = parsed.core
        const suffix = parsed.suffix

        const match = core.match(/^([^\/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$/i)
        if (!match) {
            return urlToken
        }

        const host = match[1]
        const path = match[2] ?? ""
        const queryPart = match[3] ? match[3].slice(1) : ""
        const fragment = match[4] ?? ""
        const rewrittenHost = root.rewriteSocialHost(host)
        const cleanedQuery = root.removeTrackingParams(queryPart)
        const finalQuery = cleanedQuery.length > 0 ? `?${cleanedQuery}` : ""
        return `${rewrittenHost}${path}${finalQuery}${fragment}${suffix}`
    }

    function applySmartPasteTransforms(text) {
        if (!root.smartPasteEnabled || text === undefined || text === null) {
            return text
        }
        let transformed = `${text}`.replace(/https?:\/\/[^\s<>"'\])}]+/g, matched => root.rewriteUrlToken(matched))
        transformed = transformed.replace(/(^|[\s(])((?:www\.|mobile\.|m\.)?(?:x\.com|twitter\.com|instagram\.com)(?:\/[^\s<>"'\])}]*)?)/gi,
            (matched, prefix, token) => `${prefix}${root.rewriteBareSocialToken(token)}`)
        return transformed
    }

    function maybeRewriteClipboardText() {
        if (!root.autoRewriteEnabled()) {
            return
        }

        const current = `${Quickshell.clipboardText ?? ""}`
        if (current.length === 0) {
            return
        }

        root.maybeRewriteClipboardValue(current)
    }

    function maybeRewriteClipboardValue(current) {
        if (!root.autoRewriteEnabled()) {
            return
        }

        if (Date.now() < root.suppressAutoRewriteUntilMs) {
            return
        }

        const currentText = `${current ?? ""}`
        if (currentText.length === 0) {
            return
        }

        const transformed = root.applySmartPasteTransforms(currentText)
        if (transformed === currentText) {
            return
        }

        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(transformed)}' | wl-copy`])
        root.lastObservedClipboardText = transformed
    }

    function toArray(value) {
        if (Array.isArray(value)) return value.slice();
        if (value === undefined || value === null) return [];
        if (typeof value.length === "number") {
            let out = [];
            for (let i = 0; i < value.length; i++) out.push(value[i]);
            return out;
        }
        return [];
    }

    function historyIdentityKey(entry) {
        const clean = StringUtils.cleanCliphistEntry(entry)
        if (root.entryIsFileUri(entry)) {
            return `file:${clean}`
        }
        if (root.entryIsImage(entry)) {
            return `image:${clean}`
        }
        if (!root.autoRewriteEnabled()) {
            return `text:${clean}`
        }
        return `text:${root.applySmartPasteTransforms(clean)}`
    }

    function dedupeHistoryEntries(entriesList) {
        const seen = new Set()
        const deduped = []
        entriesList.forEach(entry => {
            const key = root.historyIdentityKey(entry)
            if (seen.has(key)) {
                return
            }
            seen.add(key)
            deduped.push(entry)
        })
        return deduped
    }

    function entryKey(entry) {
        return StringUtils.cleanCliphistEntry(entry);
    }

    function normalizedPinnedEntryKeys() {
        const values = root.toArray(root.pinnedEntryKeys)
            .map(v => `${v}`.trim())
            .filter(v => v.length > 0);
        const seen = new Set();
        const unique = [];
        values.forEach(value => {
            if (!seen.has(value)) {
                seen.add(value);
                unique.push(value);
            }
        });
        return unique;
    }

    function setPinnedEntryKeys(values) {
        Config.options.search.clipboardPinnedEntries = values;
        root.pinRevision += 1;
    }

    function isPinned(entry) {
        const key = root.entryKey(entry);
        return root.normalizedPinnedEntryKeys().includes(key);
    }

    function pinEntry(entry) {
        const key = root.entryKey(entry);
        if (key.length === 0) return;
        const pins = root.normalizedPinnedEntryKeys();
        if (!pins.includes(key)) {
            pins.push(key);
            root.setPinnedEntryKeys(pins);
        }
    }

    function unpinEntry(entry) {
        const key = root.entryKey(entry);
        const pins = root.normalizedPinnedEntryKeys().filter(pin => pin !== key);
        root.setPinnedEntryKeys(pins);
    }

    function togglePinEntry(entry) {
        if (root.isPinned(entry)) root.unpinEntry(entry);
        else root.pinEntry(entry);
    }

    function sortPinnedFirst(list) {
        const values = root.toArray(list);
        const pins = root.normalizedPinnedEntryKeys();
        const pinIndex = new Map();
        pins.forEach((key, index) => pinIndex.set(key, index));

        const pinned = [];
        const rest = [];

        values.forEach(entry => {
            if (root.isPinned(entry)) pinned.push(entry);
            else rest.push(entry);
        });

        pinned.sort((a, b) => {
            const aIdx = pinIndex.has(root.entryKey(a)) ? pinIndex.get(root.entryKey(a)) : Number.MAX_SAFE_INTEGER;
            const bIdx = pinIndex.has(root.entryKey(b)) ? pinIndex.get(root.entryKey(b)) : Number.MAX_SAFE_INTEGER;
            return aIdx - bIdx;
        });

        return pinned.concat(rest);
    }

    function rebuildPinsFromCurrentEntries() {
        // Keep persisted pins stable across boots/restarts even when cliphist
        // temporarily reports an empty or partial list during startup.
        const currentPins = root.toArray(root.pinnedEntryKeys)
            .map(v => `${v}`.trim())
            .filter(v => v.length > 0);
        const normalized = root.normalizedPinnedEntryKeys();
        if (normalized.length !== currentPins.length) {
            root.setPinnedEntryKeys(normalized);
        }
    }

    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return root.sortPinnedFirst(entries);
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return root.sortPinnedFirst(results.map(item => item.entry))
        }

        return root.sortPinnedFirst(Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        }));
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function entryIsFileUri(entry) {
        return !!(/^\d+\tfile:\/\/\S+/.test(entry))
    }

    function entryIsVideoFileUri(entry) {
        if (!root.videoProcessingEnabled) return false
        if (!root.entryIsFileUri(entry)) return false
        const clean = StringUtils.cleanCliphistEntry(entry).toLowerCase().split(/[?#]/)[0]
        return /\.(mp4|mkv|webm|mov|avi|m4v|wmv|flv|mpg|mpeg|ts|m2ts|3gp|ogv)$/.test(clean)
    }

    function fileUriFromEntry(entry) {
        return StringUtils.cleanCliphistEntry(entry)
    }

    function decodedPathFromFileUri(fileUri) {
        if (!fileUri || !fileUri.startsWith("file://")) return ""
        return decodeURIComponent(fileUri.slice("file://".length))
    }

    function extensionFromEntry(entry) {
        const uri = root.fileUriFromEntry(entry)
        const path = root.decodedPathFromFileUri(uri).toLowerCase()
        const dot = path.lastIndexOf(".")
        if (dot < 0 || dot === path.length - 1) return "video"
        return path.slice(dot + 1)
    }

    function getVideoEntryDisplay(entry) {
        // Tie this binding to metadata updates.
        const _videoRev = root.videoMetadataRevision
        if (!root.entryIsVideoFileUri(entry))
            return root.fileUriFromEntry(entry)

        const key = root.entryKey(entry)
        const meta = root.videoMetadataByEntryKey[key]
        if (meta) {
            return `[[binary data ${meta.sizeLabel} ${meta.ext} ${meta.width}x${meta.height}]]`
        }
        return `[[binary data ? ${root.extensionFromEntry(entry)} ?x?]]`
    }

    function formatBinarySize(bytesValue) {
        const bytes = Number(bytesValue)
        if (!Number.isFinite(bytes) || bytes < 0) return "?"
        const kib = 1024
        const mib = 1024 * 1024
        if (bytes >= mib) {
            return `${(bytes / mib).toFixed(1)}MiB`
        }
        return `${Math.max(1, Math.round(bytes / kib))}KiB`
    }

    function refreshVideoMetadataQueue() {
        if (!root.videoProcessingEnabled) {
            videoMetadataProbeProc.queue = []
            return
        }

        const queue = root.entries
            .filter(entry => root.entryIsVideoFileUri(entry))
            .filter(entry => root.videoMetadataByEntryKey[root.entryKey(entry)] === undefined)

        if (queue.length === 0) return
        const existing = videoMetadataProbeProc.queue ?? []
        const seen = new Set(existing.map(item => root.entryKey(item)))
        const merged = existing.slice()
        queue.forEach(item => {
            const key = root.entryKey(item)
            if (!seen.has(key)) {
                seen.add(key)
                merged.push(item)
            }
        })
        videoMetadataProbeProc.queue = merged
        if (!videoMetadataProbeProc.running)
            videoMetadataProbeProc.runNext()
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        root.suspendAutoRewrite()
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            const copyType = root.entryIsFileUri(entry) ? "--type text/uri-list" : ""
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy ${copyType}`]);
        }
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function pasteText(text, applySmartTransform = false) {
        root.suspendAutoRewrite()
        const outputText = applySmartTransform ? root.applySmartPasteTransforms(text) : text
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(outputText)}' | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
    }

    function pasteWithoutTransforms(entry) {
        root.suspendAutoRewrite()
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            const copyType = root.entryIsFileUri(entry) ? "--type text/uri-list" : ""
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy ${copyType} && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
        }
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
        }
    }

    function paste(entry) {
        // Pasting from the clipboard menu should preserve selected item as-is.
        root.pasteWithoutTransforms(entry)
    }

    function superpaste(count, isImage = false) {
        root.suspendAutoRewrite()
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(deleteProc.entry)}' | ${root.cliphistBinary} delete`]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
            deleteProc.entry = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        const targetIdentity = root.historyIdentityKey(entry)
        const semanticTargets = root.rawEntries.filter(item => root.historyIdentityKey(item) === targetIdentity)

        if (semanticTargets.length <= 1) {
            deleteProc.deleteEntry(entry)
            return
        }

        const deleteCommands = semanticTargets.map(item =>
            `printf '%s\n' '${StringUtils.shellSingleQuoteEscape(item)}' | ${root.cliphistBinary} delete || true`
        )
        deleteSemanticProc.command = ["bash", "-c", deleteCommands.join(";")]
        deleteSemanticProc.running = true
    }

    Process {
        id: deleteSemanticProc
        command: ["bash", "-c", "true"]
        onExited: (exitCode, exitStatus) => {
            root.refresh()
        }
    }

    Process {
        id: wipeProc
        command: ["bash", "-c", `${root.cliphistBinary} wipe; rm -rf ~/.cache/cliphist/db`]
        onExited: (exitCode, exitStatus) => {
            root.entries = [];
            root.refresh();
        }
    }

    Process {
        id: wipeKeepPinnedProc
        command: ["bash", "-c", "true"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        // Delete from raw history using semantic identities so rewritten/original
        // variants are removed together.
        const pinnedIdentityKeys = new Set(
            root.entries
                .filter(entry => root.isPinned(entry))
                .map(entry => root.historyIdentityKey(entry))
        )

        const targets = root.rawEntries.filter(entry =>
            !pinnedIdentityKeys.has(root.historyIdentityKey(entry))
        )

        if (targets.length === 0) {
            return;
        }

        const deleteCommands = targets.map(entry =>
            `printf '%s\n' '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} delete || true`
        );

        wipeKeepPinnedProc.command = ["bash", "-c", deleteCommands.join(";")];
        wipeKeepPinnedProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            const current = `${Quickshell.clipboardText ?? ""}`
            if (current !== root.lastObservedClipboardText) {
                root.maybeRewriteClipboardValue(current)
            }
            root.lastObservedClipboardText = current
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: clipboardRewriteFallbackPoll
        interval: 350
        repeat: true
        running: root.autoRewriteEnabled()
        onTriggered: {
            if (!root.autoRewriteEnabled() || clipboardReadProc.running) {
                return
            }
            clipboardReadProc.command = ["bash", "-c", "wl-paste -n --type text 2>/dev/null || true"]
            clipboardReadProc.running = true
        }
    }

    Process {
        id: clipboardReadProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            id: clipboardReadCollector
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.autoRewriteEnabled()) {
                return
            }

            const current = `${clipboardReadCollector.text ?? ""}`
            if (current === root.lastObservedClipboardText) {
                return
            }

            root.maybeRewriteClipboardValue(current)
            root.lastObservedClipboardText = current

            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.rawEntries = readProc.buffer
                root.entries = root.dedupeHistoryEntries(root.rawEntries)
                root.rebuildPinsFromCurrentEntries()
                root.refreshVideoMetadataQueue()
            } else {
                root.entries = []
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    Process {
        id: videoMetadataProbeProc
        property list<string> queue: []
        property string currentEntry: ""
        property string buffer: ""

        function runNext() {
            if (videoMetadataProbeProc.queue.length === 0) return

            videoMetadataProbeProc.currentEntry = videoMetadataProbeProc.queue.shift()
            const fileUri = root.fileUriFromEntry(videoMetadataProbeProc.currentEntry)
            const decodedPath = root.decodedPathFromFileUri(fileUri)
            if (decodedPath.length === 0) {
                runNext()
                return
            }

            const pyScript = [
                "import json, os, pathlib, subprocess, sys",
                "p = sys.argv[1]",
                "ext = pathlib.Path(p).suffix.lower().lstrip('.') or 'video'",
                "size_bytes = int(os.path.getsize(p)) if os.path.exists(p) else 0",
                "width = '?'",
                "height = '?'",
                "try:",
                "    out = subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', p], text=True).strip()",
                "    if out and 'x' in out:",
                "        w, h = out.split('x', 1)",
                "        if w.isdigit() and h.isdigit():",
                "            width, height = w, h",
                "except Exception:",
                "    pass",
                "print(json.dumps({'sizeBytes': size_bytes, 'ext': ext, 'width': width, 'height': height}))"
            ].join("\n")

            videoMetadataProbeProc.buffer = ""
            videoMetadataProbeProc.command = ["python3", "-c", pyScript, decodedPath]
            videoMetadataProbeProc.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (videoMetadataProbeProc.buffer.length > 0)
                    videoMetadataProbeProc.buffer += "\n"
                videoMetadataProbeProc.buffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && videoMetadataProbeProc.buffer.trim().length > 0) {
                try {
                    const parsed = JSON.parse(videoMetadataProbeProc.buffer.trim())
                    const key = root.entryKey(videoMetadataProbeProc.currentEntry)
                    const nextMap = Object.assign({}, root.videoMetadataByEntryKey)
                    nextMap[key] = {
                        sizeLabel: root.formatBinarySize(parsed.sizeBytes),
                        ext: parsed.ext,
                        width: parsed.width,
                        height: parsed.height,
                    }
                    root.videoMetadataByEntryKey = nextMap
                    root.videoMetadataRevision += 1
                } catch (e) {
                    console.error("[Cliphist] Failed to parse video metadata", e)
                }
            }

            videoMetadataProbeProc.currentEntry = ""
            videoMetadataProbeProc.runNext()
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}