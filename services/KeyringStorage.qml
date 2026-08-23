pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * For storing sensitive data in the keyring.
 * Use this for small data only, since it stores a JSON of the contents directly and doesn't use a database.
 */
Singleton {
    id: root

    signal dataChanged()

    property bool loaded: false
    property var keyringData: ({})
    
    property var properties: {
        "application": "illogical-impulse",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("illogical-impulse")

    function setNestedField(path, value) {
        if (!root.keyringData) root.keyringData = {};
        let keys = path;
        let obj = root.keyringData;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Set the value at the innermost key
        obj[keys[keys.length - 1]] = value;

        // Reassign each parent object from the bottom up to trigger change notifications
        for (let i = keys.length - 2; i >= 0; --i) {
            let parent = parents[i];
            let key = keys[i];
            // Shallow clone to change object identity (spread replaced with Object.assign)
            parent[key] = Object.assign({}, parent[key]);
        }

        // Finally, reassign root.keyringData to trigger top-level change
        root.keyringData = Object.assign({}, root.keyringData);

        saveKeyringData();
    }

    function fetchKeyringData() {
        // console.log("[KeyringStorage] Fetching keyring data...");
        // console.log("[KeyringStorage] getData command:'" + getData.command.join("' '") + "'");
        getData.running = true;
    }

    function saveKeyringData() {
        // The secret is passed via an environment variable, then written to a
        // private 0600 temp file for `secret-tool store` to read as its
        // stdin, rather than written directly over the process's own stdin
        // pipe with stdinEnabled toggled off afterward to signal "done".
        // That used to be how this worked, but Process.stdinEnabled set to
        // false *after* already-true does not reliably close/EOF the pipe --
        // confirmed directly: secret-tool (like curl reading `-d @-`) reads
        // stdin until EOF before returning, and sat blocked for a lot longer
        // than it should have with data written but the pipe still open.
        // Silently, this meant every saved Bitwarden session/API key
        // potentially never actually got persisted to the keyring, with no
        // error raised anywhere. A real file's EOF is unambiguous, so this
        // sidesteps the unreliable close-the-pipe mechanism entirely.
        const args = root.propertiesAsArgs
            .map(a => `'${StringUtils.shellSingleQuoteEscape(a)}'`)
            .join(" ")
        saveData.exec({
            command: ["bash", "-c", [
                "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\")",
                "chmod 600 \"$f\"",
                "printf '%s' \"$KEYRING_SAVE_JSON\" > \"$f\"",
                `secret-tool store --label='${StringUtils.shellSingleQuoteEscape(root.keyringLabel)}' ${args} < "$f"`,
                "code=$?",
                "rm -f \"$f\"",
                "exit $code"
            ].join("\n")],
            environment: { KEYRING_SAVE_JSON: JSON.stringify(root.keyringData) }
        })
        root.dataChanged()
    }

    Process {
        id: saveData

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.error("[KeyringStorage] Failed to save to keyring, exit code:", exitCode)
        }
    }

    Process {
        id: getData
        command: [ // We need to use echo for a newline so splitparser does parse
            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,
        ]
        stdout: StdioCollector {
            id: keyringDataOutputCollector
            onStreamFinished: {
                const data = keyringDataOutputCollector.text;
                if (data.length === 0 || !data.startsWith("{")) return;
                try {
                    root.keyringData = JSON.parse(data);
                    // console.log("[KeyringStorage] Keyring data fetched:", JSON.stringify(root.keyringData));
                } catch (e) {
                    console.error("[KeyringStorage] Failed to get keyring data, reinitializing.");
                    root.keyringData = {};
                    saveKeyringData()
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // console.log("[KeyringStorage] Keyring data fetch process exited with code:", exitCode);
            if (exitCode === 1) {
                console.error("[KeyringStorage] Entry not found, initializing.");
                root.keyringData = {};
                saveKeyringData()
            }
            if (exitCode !== 2) {
                root.loaded = true;
            }
        }
    }
    
}
