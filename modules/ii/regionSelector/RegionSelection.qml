pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.phase === RegionSelection.Phase.Select
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound }
    enum SelectionMode { RectCorners, Circle, Monitor }
    enum Phase { Select, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property bool recordSystemAudio: Config.options.screenRecord.recordSystemAudio
    property bool recordMicAudio: Config.options.screenRecord.recordMicAudio
    property bool copyToClipboard: true
    property bool showControls: true
    property real cursorGlobalX: -1
    property real cursorGlobalY: -1
    property bool postMode: false
    property var lastSelectionMode: RegionSelection.SelectionMode.RectCorners
    property bool selectionLocked: false
    property string dragEditMode: "none" // none|move|resize_tl|resize_tr|resize_bl|resize_br
    property real editStartRegionX: 0
    property real editStartRegionY: 0
    property real editStartRegionWidth: 0
    property real editStartRegionHeight: 0
    property var phase: RegionSelection.Phase.Select
    onVisibleChanged: {
        if (root.visible && root.phase === RegionSelection.Phase.Select) {
            root.resetSelectionState();
        }
    }
    onPostModeChanged: {
        if (postMode) {
            root.phase = RegionSelection.Phase.Post
        }
    }
    onSelectionModeChanged: {
        if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
            root.selectionLocked = false;
            root.dragging = false;
            root.dragEditMode = "none";
            root.updateMonitorHighlight();
        } else if (root.lastSelectionMode === RegionSelection.SelectionMode.Monitor) {
            // Leaving monitor mode should clear monitor-wide highlight state.
            root.resetSelectionState();
        }
        root.lastSelectionMode = root.selectionMode;
    }
    onCursorGlobalXChanged: {
        if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
            root.updateMonitorHighlight();
        }
    }
    onCursorGlobalYChanged: {
        if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
            root.updateMonitorHighlight();
        }
    }
    signal recordingStarted()
    signal dismiss()
    onRecordSystemAudioChanged: Config.options.screenRecord.recordSystemAudio = root.recordSystemAudio
    onRecordMicAudioChanged: Config.options.screenRecord.recordMicAudio = root.recordMicAudio

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && root.phase === RegionSelection.Phase.Select
        onActivated: root.dismiss()
    }

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity
    readonly property real monitorLayoutWidth: root.hyprlandMonitor.width ?? root.screen.width
    readonly property real monitorLayoutHeight: root.hyprlandMonitor.height ?? root.screen.height
    readonly property bool cursorOnThisMonitor: root.cursorGlobalX >= root.monitorOffsetX
        && root.cursorGlobalX < root.monitorOffsetX + root.monitorLayoutWidth
        && root.cursorGlobalY >= root.monitorOffsetY
        && root.cursorGlobalY < root.monitorOffsetY + root.monitorLayoutHeight

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
        root.layerRegions
    ).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
        }
    })
    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && root.selectionMode === RegionSelection.SelectionMode.RectCorners
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && root.selectionMode === RegionSelection.SelectionMode.RectCorners
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content && root.selectionMode === RegionSelection.SelectionMode.RectCorners

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const isRecordingAction = root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound;
        const padding = isRecordingAction ? 0 : Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function pointInSelection(x, y) {
        return x >= root.regionX && x <= root.regionX + root.regionWidth
            && y >= root.regionY && y <= root.regionY + root.regionHeight;
    }

    function resizeHandleAt(x, y) {
        const handle = 12;
        const left = root.regionX;
        const right = root.regionX + root.regionWidth;
        const top = root.regionY;
        const bottom = root.regionY + root.regionHeight;

        if (Math.abs(x - left) <= handle && Math.abs(y - top) <= handle) return "resize_tl";
        if (Math.abs(x - right) <= handle && Math.abs(y - top) <= handle) return "resize_tr";
        if (Math.abs(x - left) <= handle && Math.abs(y - bottom) <= handle) return "resize_bl";
        if (Math.abs(x - right) <= handle && Math.abs(y - bottom) <= handle) return "resize_br";
        return "none";
    }

    function constrainSelectionToScreen() {
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));
    }

    function syncRegionFromDrag() {
        root.regionX = Math.min(root.dragStartX, root.draggingX);
        root.regionY = Math.min(root.dragStartY, root.draggingY);
        root.regionWidth = Math.abs(root.draggingX - root.dragStartX);
        root.regionHeight = Math.abs(root.draggingY - root.dragStartY);
    }

    function updateMonitorHighlight() {
        if (root.selectionMode === RegionSelection.SelectionMode.Monitor && root.cursorOnThisMonitor) {
            root.regionX = 0;
            root.regionY = 0;
            root.regionWidth = root.screen.width;
            root.regionHeight = root.screen.height;
        } else {
            root.regionWidth = 0;
            root.regionHeight = 0;
        }
    }

    function resetSelectionState() {
        root.selectionLocked = false;
        root.dragging = false;
        root.dragEditMode = "none";
        root.mouseButton = null;
        root.regionX = 0;
        root.regionY = 0;
        root.regionWidth = 0;
        root.regionHeight = 0;
        root.dragStartX = 0;
        root.dragStartY = 0;
        root.draggingX = 0;
        root.draggingY = 0;
        root.dragDiffX = 0;
        root.dragDiffY = 0;
        root.points = [];
        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    function lockSelectionForConfirm() {
        root.selectionLocked = true;
        root.dragging = false;
        root.dragEditMode = "none";
    }

    function captureOrLockSelection() {
        const screenshotAction = root.getScreenshotAction();
        const immediateAction = screenshotAction === ScreenshotAction.Action.Record
            || screenshotAction === ScreenshotAction.Action.RecordWithSound
            || root.selectionMode !== RegionSelection.SelectionMode.RectCorners;

        if (immediateAction) {
            root.selectionLocked = false;
            root.snip();
            return;
        }

        root.lockSelectionForConfirm();
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property real regionWidth: 0
    property real regionHeight: 0
    property real regionX: 0
    property real regionY: 0

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) imageDetectionProcess.running = true;
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    Connections {
        target: Persistent.states.record
        function onEnableChanged() {
            if (!Persistent.states.record.enable && root.isRecording) {
                root.dismiss();
            }
        }
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` 
            + `--hyprctl ` 
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` 
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` 
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                imageRegions = RegionFunctions.filterImageRegions(
                    JSON.parse(imageDimensionCollector.text),
                    root.windowRegions
                );
            }
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.Record;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    // Execution after selection
    function snip() {
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
            return;
        }

        // Clamp region to screen bounds
        root.constrainSelectionToScreen();
        
        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
            Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        let commandX = root.regionX * root.monitorScale;
        let commandY = root.regionY * root.monitorScale;
        if (screenshotAction === ScreenshotAction.Action.Record || screenshotAction === ScreenshotAction.Action.RecordWithSound) {
            // wf-recorder geometry is in global compositor coordinates.
            commandX = (root.regionX + root.monitorOffsetX) * root.monitorScale;
            commandY = (root.regionY + root.monitorOffsetY) * root.monitorScale;
        }
        const command = ScreenshotAction.getCommand(
            commandX, //
            commandY, //
            root.regionWidth * root.monitorScale,// 
            root.regionHeight * root.monitorScale, //
            root.screenshotPath, //
            screenshotAction, //
            screenshotDir,
            root.recordSystemAudio,
            root.recordMicAudio,
            root.copyToClipboard
        )
        Quickshell.execDetached(command);
        if (root.action == RegionSelection.SnipAction.Record || root.action == RegionSelection.SnipAction.RecordWithSound) {
            root.recordingStarted();
            root.phase = RegionSelection.Phase.Post
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        } else {
            root.dismiss();
        }
    }

    // Only clickable in Selection phase
    mask: Region {
        item: switch(root.phase) {
            case RegionSelection.Phase.Select: return mouseArea;
            case RegionSelection.Phase.Post: return null;
        }
    }

    ScreencopyView { // For freezing
        anchors.fill: parent
        live: false
        captureSource: root.screen
        visible: root.phase === RegionSelection.Phase.Select

        focus: root.visible
        Keys.onPressed: (event) => { // Esc to close
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.phase === RegionSelection.Phase.Select
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        // Controls
        onPressed: (mouse) => {
            if (root.selectionLocked && root.selectionMode === RegionSelection.SelectionMode.RectCorners) {
                root.mouseButton = mouse.button;

                if (mouse.button === Qt.RightButton) {
                    root.selectionLocked = false;
                } else if (mouse.button === Qt.LeftButton) {
                    const handle = root.resizeHandleAt(mouse.x, mouse.y);
                    if (handle !== "none") {
                        root.dragEditMode = handle;
                    } else if (root.pointInSelection(mouse.x, mouse.y)) {
                        root.dragEditMode = "move";
                    } else {
                        root.selectionLocked = false;
                        root.dragEditMode = "none";
                    }
                }

                if (root.selectionLocked && root.dragEditMode !== "none") {
                    root.editStartRegionX = root.regionX;
                    root.editStartRegionY = root.regionY;
                    root.editStartRegionWidth = root.regionWidth;
                    root.editStartRegionHeight = root.regionHeight;
                    root.dragStartX = mouse.x;
                    root.dragStartY = mouse.y;
                    root.draggingX = mouse.x;
                    root.draggingY = mouse.y;
                    root.dragging = true;
                    return;
                }
            }

            if (mouse.button === Qt.RightButton && root.selectionMode !== RegionSelection.SelectionMode.RectCorners) {
                // Right drag is always custom region selection.
                root.selectionMode = RegionSelection.SelectionMode.RectCorners;
            }
            if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
                if (!root.cursorOnThisMonitor) {
                    return;
                }
                root.regionX = 0;
                root.regionY = 0;
                root.regionWidth = root.screen.width;
                root.regionHeight = root.screen.height;
                root.dragging = false;
                root.mouseButton = mouse.button;
                return;
            }
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.syncRegionFromDrag();
            root.dragDiffX = 0;
            root.dragDiffY = 0;
            root.points = [];
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: (mouse) => {
            if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
                if (!root.cursorOnThisMonitor) {
                    return;
                }
                if (root.mouseButton === Qt.RightButton) {
                    root.resetSelectionState();
                    return;
                }
                root.captureOrLockSelection();
                return;
            }

            if (root.selectionLocked && root.mouseButton === Qt.LeftButton) {
                const wasEditing = root.dragEditMode !== "none";
                root.dragging = false;
                root.dragEditMode = "none";
                if (!wasEditing && root.pointInSelection(mouse.x, mouse.y)) {
                    root.selectionLocked = false;
                    root.snip();
                }
                return;
            }

            let shouldSnip = true;
            const isClick = root.draggingX === root.dragStartX && root.draggingY === root.dragStartY;

            if (root.mouseButton === Qt.RightButton) {
                if (isClick) {
                    root.resetSelectionState();
                    return;
                }
                root.syncRegionFromDrag();
                root.lockSelectionForConfirm();
                return;
            }

            // Detect if it was a click -> Try to select targeted region
            if (isClick) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                } else {
                    shouldSnip = false;
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }
            if (shouldSnip) {
                root.captureOrLockSelection();
            }
        }
        onPositionChanged: (mouse) => {
            if (root.selectionLocked && root.dragging && root.dragEditMode !== "none") {
                const dx = mouse.x - root.dragStartX;
                const dy = mouse.y - root.dragStartY;
                const minSize = 8;

                if (root.dragEditMode === "move") {
                    root.regionX = root.editStartRegionX + dx;
                    root.regionY = root.editStartRegionY + dy;
                } else if (root.dragEditMode === "resize_tl") {
                    root.regionX = root.editStartRegionX + dx;
                    root.regionY = root.editStartRegionY + dy;
                    root.regionWidth = root.editStartRegionWidth - dx;
                    root.regionHeight = root.editStartRegionHeight - dy;
                } else if (root.dragEditMode === "resize_tr") {
                    root.regionY = root.editStartRegionY + dy;
                    root.regionWidth = root.editStartRegionWidth + dx;
                    root.regionHeight = root.editStartRegionHeight - dy;
                } else if (root.dragEditMode === "resize_bl") {
                    root.regionX = root.editStartRegionX + dx;
                    root.regionWidth = root.editStartRegionWidth - dx;
                    root.regionHeight = root.editStartRegionHeight + dy;
                } else if (root.dragEditMode === "resize_br") {
                    root.regionWidth = root.editStartRegionWidth + dx;
                    root.regionHeight = root.editStartRegionHeight + dy;
                }

                if (root.regionWidth < minSize) root.regionWidth = minSize;
                if (root.regionHeight < minSize) root.regionHeight = minSize;
                root.constrainSelectionToScreen();
                return;
            }

            root.updateTargetedRegion(mouse.x, mouse.y);
            if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
                root.updateMonitorHighlight();
            }
            if (!root.dragging) return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            if (root.selectionMode === RegionSelection.SelectionMode.RectCorners) {
                root.syncRegionFromDrag();
            }
            root.points.push({ x: mouse.x, y: mouse.y });
        }
        onExited: {
            if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
                root.regionWidth = 0;
                root.regionHeight = 0;
            }
        }
        onContainsMouseChanged: {
            if (root.selectionMode === RegionSelection.SelectionMode.Monitor) {
                root.updateMonitorHighlight();
            }
        }
        
        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode !== RegionSelection.SelectionMode.Circle
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                showAimLines: root.cursorOnThisMonitor
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select && root.cursorOnThisMonitor
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions && root.cursorOnThisMonitor) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions && root.cursorOnThisMonitor) {
                        return root.layerRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions && root.cursorOnThisMonitor) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            visible: root.showControls && root.phase === RegionSelection.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onVisibleChanged() {
                    if (!visible) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                Synchronizer on recordSystemAudio {
                    property alias source: root.recordSystemAudio
                }
                Synchronizer on recordMicAudio {
                    property alias source: root.recordMicAudio
                }
                Synchronizer on copyToClipboard {
                    property alias source: root.copyToClipboard
                }
                onSelectMonitor: root.updateMonitorHighlight()
                onDismiss: root.dismiss();
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: root.dismiss();
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }

        Row {
            id: selectionConfirmControls
            z: 11
            visible: root.selectionLocked
                && root.phase === RegionSelection.Phase.Select
                && root.selectionMode === RegionSelection.SelectionMode.RectCorners
                && root.regionWidth > 0
                && root.regionHeight > 0
            spacing: 8
            x: Math.max(0, Math.min(parent.width - width, root.regionX + (root.regionWidth - width) / 2))
            y: Math.min(parent.height - height, root.regionY + root.regionHeight + 8)

            ToolbarPairedFab {
                iconText: "check"
                onClicked: {
                    root.selectionLocked = false;
                    root.snip();
                }
                StyledToolTip {
                    text: Translation.tr("Capture selection")
                }
            }

            ToolbarPairedFab {
                iconText: "close"
                onClicked: {
                    root.resetSelectionState();
                }
                StyledToolTip {
                    text: Translation.tr("Cancel selection")
                }
            }
        }
        
    }
}