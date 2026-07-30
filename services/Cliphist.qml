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
    property list<string> entries: []
    property int pinRevision: 0
    readonly property list<string> pinnedEntryKeys: Config.options?.search?.clipboardPinnedEntries ?? []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))

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
        const availableKeys = new Set(root.entries.map(entry => root.entryKey(entry)));
        const pins = root.normalizedPinnedEntryKeys().filter(key => availableKeys.has(key));
        if (pins.length !== root.normalizedPinnedEntryKeys().length) {
            root.setPinnedEntryKeys(pins);
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

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            const copyType = root.entryIsFileUri(entry) ? "--type text/uri-list" : ""
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy ${copyType}`]);
        }
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function pasteText(text) {
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) { // Classic cliphist
            const copyType = root.entryIsFileUri(entry) ? "--type text/uri-list" : ""
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy ${copyType} && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
        }
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`]);
        }
    }

    function superpaste(count, isImage = false) {
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
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
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
        const unpinned = root.entries.filter(entry => !root.isPinned(entry));
        if (unpinned.length === 0) {
            return;
        }

        const deleteCommands = unpinned.map(entry =>
            `printf '%s\n' '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} delete`
        );

        wipeKeepPinnedProc.command = ["bash", "-c", deleteCommands.join(" && ")];
        wipeKeepPinnedProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
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
                root.entries = readProc.buffer
                root.rebuildPinsFromCurrentEntries()
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
