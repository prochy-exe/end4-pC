import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io


Item {
    id: root

    signal wallpaperSelected(string path)
    property real cellWidth: grid.cellWidth
    property real cellHeight: grid.cellHeight

    function moveSelection(delta) { grid.moveSelection(delta) }
    function activateCurrent() { grid.activateCurrent() }

    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3

    // Drag-and-drop state
    property bool isDragging: false
    property int dragFromIndex: -1
    property int dropTargetIndex: -1
    property real dragX: 0
    property real dragY: 0
    property var draggedItemData: null

    function startDrag(fromIdx, data, pos) {
        dragFromIndex = fromIdx;
        dropTargetIndex = fromIdx;
        draggedItemData = data;
        dragX = pos.x;
        dragY = pos.y;
        isDragging = true;
    }

    function updateDrag(pos) {
        dragX = pos.x;
        dragY = pos.y;

        const gridPos = root.mapToItem(grid, pos.x, pos.y);
        const col = Math.max(0, Math.min(root.columns - 1, Math.floor(gridPos.x / grid.cellWidth)));
        const row = Math.floor((gridPos.y + grid.contentY) / grid.cellHeight);
        const target = Math.max(0, Math.min(grid.model.count - 1, row * root.columns + col));
        dropTargetIndex = target;

        if (gridPos.y < 50) {
            autoScrollUpTimer.running = true;
            autoScrollDownTimer.running = false;
        } else if (gridPos.y > grid.height - 50) {
            autoScrollDownTimer.running = true;
            autoScrollUpTimer.running = false;
        } else {
            autoScrollUpTimer.running = false;
            autoScrollDownTimer.running = false;
        }
    }

    function endDrag() {
        autoScrollUpTimer.running = false;
        autoScrollDownTimer.running = false;
        if (isDragging && dragFromIndex >= 0 && dropTargetIndex >= 0 && dragFromIndex !== dropTargetIndex) {
            Wallpapers.moveWallpaper(dragFromIndex, dropTargetIndex);
            grid.currentIndex = dropTargetIndex;
        }
        isDragging = false;
        dragFromIndex = -1;
        dropTargetIndex = -1;
        draggedItemData = null;
    }

    function cancelDrag() {
        autoScrollUpTimer.running = false;
        autoScrollDownTimer.running = false;
        isDragging = false;
        dragFromIndex = -1;
        dropTargetIndex = -1;
        draggedItemData = null;
    }

    Timer {
        id: autoScrollUpTimer
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            grid.contentY = Math.max(0, grid.contentY - 14);
            root.updateDrag(Qt.point(root.dragX, root.dragY));
        }
    }

    Timer {
        id: autoScrollDownTimer
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            const maxContentY = Math.max(0, grid.contentHeight - grid.height);
            grid.contentY = Math.min(maxContentY, grid.contentY + 14);
            root.updateDrag(Qt.point(root.dragX, root.dragY));
        }
    }

    Process {
        id: deleteProc
        property string filePath: ""
        function deleteFile(path) {
            filePath = path;
            command = ["gio", "trash", path];
            running = true;
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) console.log("Error deleting file:", filePath);
        }
    }

    // ─── Dismiss overlay for context menu ───
    MouseArea {
        anchors.fill: parent
        visible: contextMenu.visible
        z: 105
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: contextMenu.visible = false
    }

    // ─── Context menu ───
    Item {
        id: contextMenu
        visible: false
        z: 110

        property string targetPath: ""
        property int targetIndex: -1
        property real targetX: 0
        property real targetY: 0
        property real targetWidth: grid.cellWidth
        property real targetHeight: grid.cellHeight

        x: Math.max(8, Math.min(root.width - width - 8, targetX))
        y: Math.max(8, Math.min(root.height - height - 8, targetY))
        width: Math.max(grid.cellWidth, 230)
        height: Math.max(grid.cellHeight, 90)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
        }
        Row {
            anchors.centerIn: parent
            spacing: 12
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: height / 2
                colBackground: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                onClicked: contextMenu.visible = false
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }
            }
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: height / 2
                colBackground: MonitorThemes.shellColorForItem(root, "colErrorContainer", Appearance.colors.colErrorContainer)
                onClicked: {
                    contextMenu.visible = false
                    deleteProc.deleteFile(contextMenu.targetPath)
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: Appearance.font.pixelSize.larger
                    color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }
            }
        }
    }

    // ─── Progress bars ───
    StyledIndeterminateProgressBar {
        id: indeterminateProgressBar
        visible: Wallpapers.thumbnailGenerationRunning && value == 0
        anchors {
            bottom: grid.top
            left: parent.left
            right: parent.right
            leftMargin: 4
            rightMargin: 4
        }
    }

    StyledProgressBar {
        visible: Wallpapers.thumbnailGenerationRunning && value > 0
        value: Wallpapers.thumbnailGenerationProgress
        anchors.fill: indeterminateProgressBar
    }

    // ─── Grid ───
    GridView {
        id: grid
        anchors.fill: parent
        visible: Wallpapers.wallpaperModel.count > 0

        readonly property int columns: root.columns
        readonly property int rows: Math.max(1, Math.ceil(count / columns))
        property int currentIndex: 0

        cellWidth: width / root.columns
        cellHeight: cellWidth / root.previewCellAspectRatio
        interactive: true
        acceptedButtons: Qt.NoButton // Disables mouse-hold flicking/dragging; scrolls ONLY via wheel or trackpad
        clip: true
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}

        function getModelProp(idx, prop) {
            if (!grid.model || idx < 0 || idx >= grid.model.count) return prop === "fileIsDir" ? false : "";
            const item = grid.model.get(idx);
            if (!item) return prop === "fileIsDir" ? false : "";
            return (typeof item[prop] !== "undefined") ? item[prop] : (typeof grid.model.get(idx, prop) !== "undefined" ? grid.model.get(idx, prop) : "");
        }

        function moveSelection(delta) {
            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
            positionViewAtIndex(currentIndex, GridView.Contain);
            const filePath = grid.model.get(currentIndex, "filePath");
            const isDir = grid.model.get(currentIndex, "fileIsDir");
            // Keyboard nav needs the same lockWall/monitor-target exclusion
            // as WallpaperDirectoryItem's click handler - see the comment
            // there for why per-monitor targets can't preview correctly yet.
            const canPreview = Config.options.background.enableWallpaperPreview
                && GlobalStates.wallpaperSelectorTarget !== "lockWall"
                && !GlobalStates.wallpaperSelectorTarget.startsWith("monitor:");
            if (!isDir && filePath && canPreview) Wallpapers.startPreview(filePath);
        }

        function activateCurrent() {
            const filePath = getModelProp(currentIndex, "filePath");
            root.wallpaperSelected(filePath);
        }

        model: Wallpapers.wallpaperModel
        onModelChanged: { currentIndex = 0; Wallpapers.stopPreview(); }

        delegate: Item {
            id: delegateCell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            colBackground: (index === grid?.currentIndex || containsMouse)
                ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                : (fileModelData.filePath === Config.options.background.wallpaperPath)
                    ? MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
                    : ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer))
            colText: (index === grid.currentIndex || containsMouse)
                ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
                : (fileModelData.filePath === Config.options.background.wallpaperPath)
                    ? MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                    : MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)

            MouseArea {
                id: cellMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                property real startPressX: 0
                property real startPressY: 0
                property bool dragInitiated: false

                onEntered: {
                    if (!root.isDragging) {
                        grid.currentIndex = delegateCell.index;
                    }
                }

                onPressed: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        startPressX = mouse.x;
                        startPressY = mouse.y;
                        dragInitiated = false;
                    }
                }

                onPositionChanged: (mouse) => {
                    if (mouse.buttons & Qt.LeftButton) {
                        if (!root.isDragging) {
                            const dist = Math.hypot(mouse.x - startPressX, mouse.y - startPressY);
                            if (dist > 8) {
                                dragInitiated = true;
                                root.startDrag(delegateCell.index, delegateCell.modelData, cellMouseArea.mapToItem(root, mouse.x, mouse.y));
                            }
                        } else {
                            root.updateDrag(cellMouseArea.mapToItem(root, mouse.x, mouse.y));
                        }
                    }
                }

                onReleased: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        const pos = cellMouseArea.mapToItem(contextMenu.parent, 0, 0);
                        contextMenu.targetX = pos.x;
                        contextMenu.targetY = pos.y;
                        contextMenu.targetPath = delegateCell.modelData.filePath;
                        contextMenu.targetIndex = delegateCell.index;
                        contextMenu.visible = true;
                        return;
                    }
                    if (root.isDragging) {
                        root.endDrag();
                    } else if (!dragInitiated) {
                        grid.currentIndex = delegateCell.index;
                        if (GlobalStates.wallpaperSelectorTarget === "lockWall" || !Config.options.background.enableWallpaperPreview) {
                            root.wallpaperSelected(delegateCell.modelData.filePath);
                        } else {
                            if (!delegateCell.modelData.fileIsDir && Config.options.background.enableWallpaperPreview) {
                                Wallpapers.startPreview(delegateCell.modelData.filePath);
                            }
                        }
                    }
                }

                onCanceled: root.cancelDrag()

                onDoubleClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        root.wallpaperSelected(delegateCell.modelData.filePath);
                    }
                }
            }
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: grid.width
                height: grid.height
                radius: Appearance.rounding.screenRounding + 5
            }
        }
    }
}
