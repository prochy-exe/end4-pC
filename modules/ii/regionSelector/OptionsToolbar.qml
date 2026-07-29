pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    property bool recordSystemAudio: false
    property bool recordMicAudio: false
    property bool copyToClipboard: true
    // Signals
    signal dismiss()
    signal selectMonitor()

    readonly property bool recordingMode: root.action === RegionSelection.SnipAction.Record
    readonly property bool screenshotMode: root.action === RegionSelection.SnipAction.Copy
        || root.action === RegionSelection.SnipAction.Edit

    ToolbarTabBar {
        id: mediaTabBar
        tabButtonList: [
            {"icon": "content_cut", "name": Translation.tr("Screenshot")},
            {"icon": "videocam", "name": Translation.tr("Recording")},
            {"icon": "image_search", "name": Translation.tr("Google Lens")},
            {"icon": "document_scanner", "name": Translation.tr("OCR")}
        ]
        currentIndex: root.action === RegionSelection.SnipAction.Record ? 1
            : root.action === RegionSelection.SnipAction.Search ? 2
            : root.action === RegionSelection.SnipAction.CharRecognition ? 3
            : 0
        onCurrentIndexChanged: {
            if (currentIndex === 0) {
                root.action = RegionSelection.SnipAction.Copy;
            } else if (currentIndex === 1) {
                root.action = RegionSelection.SnipAction.Record;
            } else if (currentIndex === 2) {
                root.action = RegionSelection.SnipAction.Search;
            } else {
                root.action = RegionSelection.SnipAction.CharRecognition;
            }
        }
    }

    ToolbarTabBar {
        id: selectionTabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")},
            {"icon": "monitor", "name": Translation.tr("Monitor")}
        ]
        currentIndex: root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0
            : root.selectionMode === RegionSelection.SelectionMode.Circle ? 1 : 2
        onCurrentIndexChanged: {
            if (currentIndex === 0) {
                root.selectionMode = RegionSelection.SelectionMode.RectCorners;
            } else if (currentIndex === 1) {
                root.selectionMode = RegionSelection.SelectionMode.Circle;
            } else {
                root.selectionMode = RegionSelection.SelectionMode.Monitor;
                root.selectMonitor();
            }
        }
    }

    IconToolbarButton {
        visible: recordingMode || screenshotMode
        text: root.copyToClipboard ? "content_paste" : "content_paste_off"
        toggled: root.copyToClipboard
        onClicked: {
            root.copyToClipboard = !root.copyToClipboard;
        }
        StyledToolTip {
            text: recordingMode
                ? (root.copyToClipboard ? Translation.tr("Copy recording path to clipboard") : Translation.tr("Do not copy recording path"))
                : (root.copyToClipboard ? Translation.tr("Copy screenshot to clipboard") : Translation.tr("Do not copy screenshot"))
        }
    }

    IconToolbarButton {
        visible: !recordingMode && (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit)
        text: "draw"
        toggled: root.action === RegionSelection.SnipAction.Edit
        onClicked: {
            if (root.action === RegionSelection.SnipAction.Edit) {
                root.action = RegionSelection.SnipAction.Copy;
            } else {
                root.action = RegionSelection.SnipAction.Edit;
            }
        }
        StyledToolTip {
            text: root.action === RegionSelection.SnipAction.Edit
                ? Translation.tr("Annotation mode")
                : Translation.tr("Enable annotation mode")
        }
    }

    IconToolbarButton {
        visible: recordingMode
        text: "volume_up"
        toggled: root.recordSystemAudio
        onClicked: {
            root.recordSystemAudio = !root.recordSystemAudio;
        }
        StyledToolTip {
            text: Translation.tr("System audio")
        }
    }

    IconToolbarButton {
        visible: recordingMode
        text: "mic"
        toggled: root.recordMicAudio
        onClicked: {
            root.recordMicAudio = !root.recordMicAudio;
        }
        StyledToolTip {
            text: Translation.tr("Microphone")
        }
    }
}
