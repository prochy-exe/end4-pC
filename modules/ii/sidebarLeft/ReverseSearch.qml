import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property list<var> engineOptions: [
        { displayName: "SauceNAO", icon: "auto_awesome", value: "saucenao" },
        { displayName: "IQDB",     icon: "image_search",  value: "iqdb"     },
    ]

    property string selectedEngine: "saucenao"
    property string dropStatus: "idle"   // idle | hover | searching | done | error
    property string statusMessage: ""

    readonly property var acceptedExtensions: ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]

    property var fileQueue: []
    property int queueTotal: 0
    property int queueDone: 0

    function engineEndpoint(engine) {
        if (engine === "iqdb") {
            return { url: "https://iqdb.org/", origin: "https://iqdb.org/", extraForm: "" }
        }
        return { url: "https://saucenao.com/search.php", origin: "https://saucenao.com/", extraForm: "-F 'database=999'" }
    }

    function buildSearchScript(path) {
        const endpoint = root.engineEndpoint(root.selectedEngine)
        const p = StringUtils.shellSingleQuoteEscape(path)
        return `out=$(mktemp --suffix=.html) && printf '<base href="${endpoint.origin}">' > "$out" && curl -sS --max-time 25 -A 'Mozilla/5.0' -F 'file=@${p}' ${endpoint.extraForm} '${endpoint.url}' >> "$out" && xdg-open "$out"`
    }

    function startSearch(path) {
        searcher.command = ["bash", "-c", root.buildSearchScript(path)]
        searcher.running = true
    }

    Process {
        id: searcher
        onExited: (exitCode) => {
            root.queueDone++
            if (exitCode !== 0) {
                root.dropStatus = "error"
                root.statusMessage = "Search failed. Is curl/xdg-open installed?"
                root.fileQueue = []
                root.queueTotal = 0
                root.queueDone = 0
                resetTimer.start()
                return
            }
            if (root.fileQueue.length > 0) {
                const next = root.fileQueue[0]
                root.fileQueue = root.fileQueue.slice(1)
                root.statusMessage = "Searching " + (root.queueDone + 1) + " / " + root.queueTotal + "..."
                root.startSearch(next)
            } else {
                root.dropStatus = "done"
                root.statusMessage = root.queueTotal === 1
                    ? "Opened in browser"
                    : root.queueTotal + " searches opened"
                root.queueTotal = 0
                root.queueDone = 0
                resetTimer.start()
            }
        }
    }

    Timer {
        id: resetTimer
        interval: 3500
        repeat: false
        onTriggered: root.dropStatus = "idle"
    }

    function decodeFileUri(raw) {
        try {
            return decodeURIComponent(raw)
        } catch (e) {
            return raw
        }
    }

    function enqueueFiles(urls) {
        var valid = []
        for (var i = 0; i < urls.length; i++) {
            var cleanPath = root.decodeFileUri(urls[i].toString().replace(/^file:\/\//, ""))
            if (cleanPath.length === 0) continue
            var ext = cleanPath.split(".").pop().toLowerCase()
            if (root.acceptedExtensions.indexOf(ext) !== -1)
                valid.push(cleanPath)
        }
        if (valid.length === 0) {
            root.dropStatus = "error"
            root.statusMessage = "No supported image found."
            resetTimer.start()
            return
        }

        root.dropStatus = "searching"
        root.fileQueue  = valid.slice(1)
        root.queueTotal = valid.length
        root.queueDone  = 0
        root.statusMessage = valid.length > 1 ? "Searching 1 / " + valid.length + "..." : "Searching..."
        root.startSearch(valid[0])
    }

    function pasteFromClipboard() {
        if (root.dropStatus === "searching") return
        pasteReader.running = true
    }

    Process {
        id: pasteReader
        command: ["bash", "-c",
            "types=$(wl-paste -n --list-types 2>/dev/null); " +
            "if echo \"$types\" | grep -qx 'text/uri-list'; then " +
            "  wl-paste -n --type text/uri-list 2>/dev/null; " +
            "elif echo \"$types\" | grep -qi '^image/'; then " +
            "  mime=$(echo \"$types\" | grep -i '^image/' | head -n1); " +
            "  ext=$(echo \"$mime\" | sed 's#image/##'); " +
            "  tmp=$(mktemp --suffix=\".$ext\"); " +
            "  wl-paste -n --type \"$mime\" > \"$tmp\"; " +
            "  echo \"file://$tmp\"; " +
            "fi"
        ]
        stdout: StdioCollector { id: pasteCollector }
        onExited: (exitCode) => {
            const lines = pasteCollector.text.split("\n").map(l => l.trim()).filter(l => l.length > 0)
            if (exitCode !== 0 || lines.length === 0) {
                root.dropStatus = "error"
                root.statusMessage = "Clipboard has no image."
                resetTimer.start()
                return
            }
            root.enqueueFiles(lines)
        }
    }

    function openFilePicker() {
        if (root.dropStatus === "searching") return
        filePicker.running = true
    }

    Process {
        id: filePicker
        command: ["kdialog", "--multiple", "--separate-output", "--getopenfilename",
            Quickshell.env("HOME"), "image/png image/jpeg image/webp image/avif image/bmp image/gif image/tiff"]
        stdout: StdioCollector { id: filePickerOutput }
        onExited: (exitCode) => {
            if (exitCode !== 0) return
            const lines = filePickerOutput.text.split("\n").map(l => l.trim()).filter(l => l.length > 0)
            if (lines.length === 0) return
            root.enqueueFiles(lines.map(p => "file://" + p))
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 12
        }
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
            opacity: 0.6
            text: "Reverse Image Search"
        }

        Rectangle {
            id: dropZone
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: {
                switch (root.dropStatus) {
                    case "hover":      return MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                    case "searching":  return MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
                    case "done":       return MonitorThemes.shellColorForItem(root, "colTertiaryContainer", Appearance.colors.colTertiaryContainer)
                    case "error":      return Qt.rgba(
                                            MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError).r,
                                            MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError).g,
                                            MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError).b, 0.15)
                    default:           return MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                }
            }
            border.color: {
                switch (root.dropStatus) {
                    case "hover":      return MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    case "searching":  return MonitorThemes.shellColorForItem(root, "colSecondary", Appearance.colors.colSecondary)
                    case "done":       return MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary)
                    case "error":      return MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError)
                    default:           return MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                }
            }
            border.width: root.dropStatus === "hover" ? 2 : 1

            Behavior on color        { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -18
                visible: root.dropStatus === "searching"
                loading: root.dropStatus === "searching"
                colBg: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                colShape: MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
                implicitSize: 56
            }

            MaterialSymbol {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -18
                visible: root.dropStatus !== "searching"
                iconSize: 40
                fill: root.dropStatus === "done" ? 1 : 0
                color: {
                    switch (root.dropStatus) {
                        case "hover": return MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                        case "done":  return MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary)
                        case "error": return MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError)
                        default:      return MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                    }
                }
                text: {
                    switch (root.dropStatus) {
                        case "hover": return "download"
                        case "done":  return "check_circle"
                        case "error": return "error"
                        default:      return "image_search"
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 30
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                width: parent.width - 32
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: {
                    switch (root.dropStatus) {
                        case "hover":     return MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                        case "done":      return MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary)
                        case "error":     return MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError)
                        default:          return MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                    }
                }
                opacity: root.dropStatus === "idle" ? 0.6 : 1.0
                text: {
                    switch (root.dropStatus) {
                        case "idle":      return "Drop, paste, or click to search"
                        case "hover":     return "Release to search"
                        case "searching": return root.statusMessage
                        case "done":      return root.statusMessage
                        case "error":     return root.statusMessage
                        default:          return ""
                    }
                }
                Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.dropStatus !== "searching"
                onClicked: root.openFilePicker()
            }

            CircleUtilButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                visible: root.dropStatus !== "searching"
                onClicked: root.pasteFromClipboard()

                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    text: "content_paste"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    drag.accept(Qt.CopyAction)
                    root.dropStatus = "hover"
                }
                onExited: {
                    if (root.dropStatus === "hover")
                        root.dropStatus = "idle"
                }
                onDropped: (drop) => {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        root.enqueueFiles(drop.urls)
                    } else {
                        root.dropStatus = "error"
                        root.statusMessage = "Could not read file path."
                        resetTimer.start()
                    }
                }
            }

            Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_V) && (event.modifiers & Qt.ControlModifier)) {
                    root.pasteFromClipboard()
                    event.accepted = true
                }
            }
            focus: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.leftMargin: 3
                text: "Search with:"
                font.pixelSize: Appearance.font.pixelSize.small
                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                opacity: 0.7
                Layout.alignment: Qt.AlignVCenter
            }

            StyledComboBox {
                Layout.fillWidth: true
                model: root.engineOptions
                colBackground: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                colBackgroundHover: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                colBackgroundActive: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                textRole: "displayName"
                valueRole: "value"
                currentIndex: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].value === root.selectedEngine) return i;
                    }
                    return 0;
                }
                onActivated: (index) => {
                    root.selectedEngine = model[index].value
                }
            }
        }
    }
}
