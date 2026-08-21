import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Unified, to-scale preview of the real monitor arrangement. Merges what
// used to be three separate widgets - MonitorCanvas (Displays), the
// selection-only sticky tab strip (Bar's per-monitor layout), and
// MonitorPreviewCanvas (Popup positions) - into one: monitor position/size
// with drag-to-reposition, the primary-monitor badge, the bar's position per
// monitor, and where the ticker/notifications/OSD currently land, all in one
// view. Click a monitor to select it - callers keep selectedMonitorName in
// sync with whatever else also drives monitor selection (InterfaceConfig.qml
// keeps this bound to page.selectedMonitorTab, also written to by the sticky
// tab strip, so both stay in sync automatically).
//
// Backed entirely by monitorConfig.monitors (hyprctl monitors all -j, see
// MonitorConfigOption.qml) rather than Quickshell.screens - it's the only
// source that also knows about disabled/disconnected monitors and has
// editable geometry, both required for drag-repositioning. The bar-strip and
// popup-marker math (PopupPlacement.barInfoFor/usableRectFor/realRectFor)
// only ever needs {name, width, height} of a monitor, so a plain object
// built from monitorConfig's own fields stands in fine for a real
// Quickshell.screens entry - see scaledLogW/scaledLogH below for why that
// object uses SCALED (logical) pixels rather than monitorConfig's raw ones.
Item {
    id: root

    property var monitorConfig
    property string selectedMonitorName: ""
    // [{ id, label, iconName, accentColor, monitorMode, monitorName,
    // position, customX, customY, customAnchor }, ...] - same shape the old
    // MonitorPreviewCanvas took.
    property var popupItems: []
    property real padding: 20
    property var previewPositions: ({})
    property bool dragHasOverlap: false

    signal monitorSelected(string name)

    implicitHeight: 220

    property var bounds: {
        let minX = Infinity, minY = Infinity
        let maxX = -Infinity, maxY = -Infinity
        const mons = monitorConfig.monitors
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            if (m.disabled) continue
            const w = monitorConfig.logicalWidth(m)
            const h = monitorConfig.logicalHeight(m)
            const px = previewPositions[m.name]?.x ?? m.x
            const py = previewPositions[m.name]?.y ?? m.y
            minX = Math.min(minX, px)
            minY = Math.min(minY, py)
            maxX = Math.max(maxX, px + w)
            maxY = Math.max(maxY, py + h)
        }
        if (minX === Infinity) return { minX: 0, minY: 0, width: 1920, height: 1080 }
        return { minX, minY, width: maxX - minX, height: maxY - minY }
    }

    property real scaleFactor: {
        if (bounds.width === 0 || bounds.height === 0) return 0.1
        const scaleX = (canvas.width  - padding * 2) / bounds.width
        const scaleY = (canvas.height - padding * 2) / bounds.height
        return Math.min(scaleX, scaleY)
    }

    property point offset: Qt.point(
        (canvas.width  - bounds.width  * scaleFactor) / 2 - bounds.minX * scaleFactor,
        (canvas.height - bounds.height * scaleFactor) / 2 - bounds.minY * scaleFactor
    )

    function checkOverlap(monitors, idx) {
        const a = monitors[idx]
        const aw = monitorConfig.logicalWidth(a)
        const ah = monitorConfig.logicalHeight(a)
        for (let i = 0; i < monitors.length; i++) {
            if (i === idx) continue
            if (monitors[i].disabled) continue
            const b = monitors[i]
            const bw = monitorConfig.logicalWidth(b)
            const bh = monitorConfig.logicalHeight(b)
            if (a.x < b.x + bw && a.x + aw > b.x &&
                a.y < b.y + bh && a.y + ah > b.y) {
                return true
            }
        }
        return false
    }

    function computeNormalized(monitors, changedIdx, newX, newY) {
        let m = monitors.slice().map(mon => Object.assign({}, mon))
        m[changedIdx].x = newX
        m[changedIdx].y = newY
        let minX = Infinity, minY = Infinity
        for (let i = 0; i < m.length; i++) {
            if (m[i].disabled) continue
            minX = Math.min(minX, m[i].x)
            minY = Math.min(minY, m[i].y)
        }
        const offX = minX < 0 ? -minX : 0
        const offY = minY < 0 ? -minY : 0
        if (offX > 0 || offY > 0) {
            for (let i = 0; i < m.length; i++) {
                m[i].x += offX
                m[i].y += offY
            }
        }
        return m
    }

    function updatePreview(idx, newX, newY) {
        const normalized = computeNormalized(monitorConfig.monitors, idx, newX, newY)
        root.dragHasOverlap = checkOverlap(normalized, idx)
        let preview = {}
        for (let i = 0; i < normalized.length; i++) {
            preview[normalized[i].name] = { x: normalized[i].x, y: normalized[i].y }
        }
        root.previewPositions = preview
    }

    function commitPosition(idx, newX, newY) {
        const normalized = computeNormalized(monitorConfig.monitors, idx, newX, newY)
        monitorConfig.monitors = normalized
        root.previewPositions = {}
        for (let i = 0; i < normalized.length; i++) {
            monitorConfig.applyMonitor(normalized[i])
        }
        monitorConfig.save()
    }

    // Which popup items land on a given monitor, at what normalized (0-1)
    // fraction of it, clustered so co-located ones cascade instead of fully
    // overlapping - ported from the old MonitorPreviewCanvas.placementsForMonitor,
    // adapted to run off monitorConfig.monitors instead of Quickshell.screens.
    // logW/logH must already be in SCALED (logical) pixels, the same space
    // real popups are placed in - see scaledLogW/scaledLogH below.
    function placementsForMonitor(monitor, logW, logH) {
        const raw = []
        for (const item of root.popupItems) {
            const belongsHere = item.monitorMode === "specific" ? item.monitorName === monitor.name : true
            if (!belongsHere) continue
            const footprint = PopupPlacement.footprintFor(item.id)
            const usable = PopupPlacement.usableRectFor({ name: monitor.name, width: logW, height: logH })
            const rect = PopupPlacement.realRectFor(item.id, item.position, item.customX, item.customY, logW, logH, item.customAnchor, usable)
            const fx = (rect.x + footprint.width / 2) / logW
            const fy = (rect.y + footprint.height / 2) / logH
            raw.push(Object.assign({}, item, { fx, fy }))
        }

        const clusterThreshold = 0.06
        const clusters = []
        for (const p of raw) {
            let cluster = clusters.find(c => Math.hypot(c.fx - p.fx, c.fy - p.fy) < clusterThreshold)
            if (!cluster) {
                cluster = { fx: p.fx, fy: p.fy, members: [] }
                clusters.push(cluster)
            }
            cluster.members.push(p)
        }

        const result = []
        for (const cluster of clusters) {
            const n = cluster.members.length
            cluster.members.forEach((member, i) => {
                result.push(Object.assign({}, member, {
                    fx: cluster.fx,
                    fy: cluster.fy,
                    // Matches MonitorSetupRect.markerSpacing below - kept as
                    // a literal here since this function runs outside any
                    // one delegate instance.
                    rowOffsetX: (i - (n - 1) / 2) * 24,
                    clusterIndex: i,
                    clusterSize: n,
                }))
            })
        }
        return result
    }

    component MonitorSetupRect: Rectangle {
        id: monRect

        required property var monitor
        required property int monitorIndex
        required property var monitorConfig
        required property real scaleFactor
        required property point canvasOffset
        required property var allMonitors
        property bool isSelected: false
        property var previewPositions: ({})
        property bool hasOverlap: false
        // (monitor, logW, logH) -> [{ label, iconName, accentColor, fx, fy,
        // rowOffsetX, clusterIndex, clusterSize }, ...], bound to
        // MonitorSetupCanvas.placementsForMonitor by the Repeater below.
        required property var placementsForMonitor

        signal positionCommitted(int index, int x, int y)
        signal monitorClicked(string name)
        signal positionDragging(int index, int x, int y)

        readonly property real markerSize: 20
        readonly property real markerSpacing: 24

        property bool isDragging: false
        property real dragX: 0
        property real dragY: 0
        property int snappedX: 0
        property int snappedY: 0
        property real snapThreshold: 12

        property int logW: monitorConfig?.logicalWidth(monitor) ?? 0
        property int logH: monitorConfig?.logicalHeight(monitor) ?? 0
        // Bar-strip/popup-marker math needs the monitor's SCALED (logical)
        // pixel size - the same space real popups/the bar are placed in -
        // not the raw hyprctl resolution logW/logH already are.
        readonly property real scaledLogW: logW / (monitor.scale || 1)
        readonly property real scaledLogH: logH / (monitor.scale || 1)

        x: isDragging ? dragX : (previewPositions[monitor.name]?.x ?? monitor.x) * scaleFactor + canvasOffset.x
        y: isDragging ? dragY : (previewPositions[monitor.name]?.y ?? monitor.y) * scaleFactor + canvasOffset.y
        width:  logW * scaleFactor
        height: logH * scaleFactor

        radius: Appearance.rounding.small
        z: isDragging ? 100 : isSelected ? 2 : 1

        color: {
            if (monitor.disabled)             return MonitorThemes.shellColorForItem(root, "colLayer2", Appearance.colors.colLayer2)
            if (isDragging && hasOverlap)     return Qt.alpha(MonitorThemes.colorForItem(root, "error", Appearance.m3colors.m3error), 0.5)
            if (isDragging)                   return Qt.alpha(MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer), 0.7)
            if (isSelected)                   return MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
            if (hoverArea.containsMouse)      return MonitorThemes.shellColorForItem(root, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover)
            return MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
        }

        border.color: (isDragging && hasOverlap) ? MonitorThemes.colorForItem(root, "error", Appearance.m3colors.m3error)
            : (isDragging || isSelected) ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            : MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)
        border.width: (isDragging || isSelected) ? 2 : 1

        Behavior on x { enabled: !isDragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !isDragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }

        readonly property bool isPrimaryMonitor: (Config.options.hyprland.primaryMonitor ?? "") === (monitor.name ?? "")

        // This monitor's bar, as a full-edge strip - drawn from raw
        // fractions rather than inset like the popup markers below, so it
        // touches the box's edges exactly. Declared first so it sits behind
        // everything else. Ported from MonitorThumbnail.qml.
        readonly property var barInfo: monitor.disabled ? { present: false }
            : PopupPlacement.barInfoFor({ name: monitor.name, width: monRect.scaledLogW, height: monRect.scaledLogH })
        readonly property var barFractions: {
            if (!monRect.barInfo.present) return { present: false, vertical: false, x: 0, y: 0, width: 0, height: 0 }
            return {
                present: true,
                vertical: monRect.barInfo.vertical,
                x: monRect.barInfo.rect.x / monRect.scaledLogW,
                y: monRect.barInfo.rect.y / monRect.scaledLogH,
                width: monRect.barInfo.rect.width / monRect.scaledLogW,
                height: monRect.barInfo.rect.height / monRect.scaledLogH,
            }
        }

        Rectangle {
            readonly property real minThickness: 3
            visible: monRect.barFractions.present
            x: monRect.barFractions.x > 0.5 ? monRect.width - width : 0
            y: monRect.barFractions.y > 0.5 ? monRect.height - height : 0
            width: monRect.barFractions.vertical
                ? Math.max(minThickness, monRect.barFractions.width * monRect.width)
                : monRect.width
            height: monRect.barFractions.vertical
                ? monRect.height
                : Math.max(minThickness, monRect.barFractions.height * monRect.height)
            color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
            opacity: 0.4
        }

        // Popup item markers (ticker/notifications/OSD), clustered - ported
        // from MonitorThumbnail.qml.
        readonly property var placements: monitor.disabled ? []
            : monRect.placementsForMonitor(monitor, monRect.scaledLogW, monRect.scaledLogH)

        readonly property real padX: {
            let pad = monRect.markerSize / 2
            for (const p of monRect.placements) {
                if (p.clusterSize > 1) pad = Math.max(pad, (p.clusterSize * monRect.markerSpacing + 8) / 2)
            }
            return pad
        }
        readonly property real padY: {
            let pad = monRect.markerSize / 2
            for (const p of monRect.placements) {
                if (p.clusterSize > 1) pad = Math.max(pad, (monRect.markerSize + 8) / 2)
            }
            return pad
        }

        function place(fraction, extent, pad) {
            return pad + fraction * Math.max(0, extent - 2 * pad)
        }

        Repeater {
            model: monRect.placements.filter(p => p.clusterSize > 1 && p.clusterIndex === 0)
            delegate: Rectangle {
                required property var modelData
                readonly property real pillWidth: modelData.clusterSize * monRect.markerSpacing + 8
                readonly property real pillHeight: monRect.markerSize + 8
                width: pillWidth
                height: pillHeight
                radius: height / 2
                color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
                border.width: 1
                border.color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutlineVariant)
                x: monRect.place(modelData.fx, monRect.width, monRect.padX) - pillWidth / 2
                y: monRect.place(modelData.fy, monRect.height, monRect.padY) - pillHeight / 2
            }
        }

        // Reuses the same read-only marker the live popup editor draws for
        // every OTHER monitor (PopupEditorWindow.qml) - modules/common/widgets/
        // monitorPreview/PopupPositionIndicator.qml - rather than
        // reimplementing it, so this preview and the live editor can never
        // drift apart visually.
        Repeater {
            model: monRect.placements
            delegate: PopupPositionIndicator {
                required property var modelData
                label: modelData.label
                iconName: modelData.iconName
                accentColor: modelData.accentColor
                rowOffsetX: modelData.rowOffsetX
                centerX: monRect.place(modelData.fx, monRect.width, monRect.padX)
                centerY: monRect.place(modelData.fy, monRect.height, monRect.padY)
            }
        }

        Rectangle {
            visible: monRect.isDragging && !monRect.hasOverlap
            x: monRect.snappedX * monRect.scaleFactor + monRect.canvasOffset.x - monRect.x
            y: monRect.snappedY * monRect.scaleFactor + monRect.canvasOffset.y - monRect.y
            width: monRect.width
            height: monRect.height
            radius: monRect.radius
            color: "transparent"
            border.color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            border.width: 2
            opacity: 0.6
        }

        Rectangle {
            visible: monRect.isPrimaryMonitor
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            radius: Appearance.rounding.full
            color: monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
            border.width: 1
            border.color: monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            implicitHeight: 24
            implicitWidth: primaryRow.implicitWidth + 12

            RowLayout {
                id: primaryRow
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    text: "home_pin"
                    iconSize: 14
                    color: monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }

                StyledText {
                    text: Translation.tr("Primary")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: monRect.monitor.disabled ? "desktop_access_disabled" : "desktop_windows"
                iconSize: Math.min(20, Math.min(monRect.width * 0.25, monRect.height * 0.25))
                color: monRect.monitor.disabled ? MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    : monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                    : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: monRect.monitor?.name ?? ""
                font.pixelSize: Math.max(9, Math.min(13, monRect.width * 0.1))
                font.weight: Font.Medium
                color: monRect.monitor.disabled ? MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    : monRect.isSelected ? MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                    : MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, monRect.width - 8)
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${monRect.logW}x${monRect.logH}`
                font.pixelSize: Math.max(8, Math.min(10, monRect.width * 0.08))
                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        function snapPosition(px, py) {
            let sx = px, sy = py
            const thresh = snapThreshold / scaleFactor
            for (let i = 0; i < allMonitors.length; i++) {
                if (i === monitorIndex) continue
                const other = allMonitors[i]
                if (other.disabled) continue
                const ow = monitorConfig.logicalWidth(other)
                const oh = monitorConfig.logicalHeight(other)
                if (Math.abs(px - other.x) < thresh)                 sx = other.x
                if (Math.abs(px - (other.x + ow)) < thresh)          sx = other.x + ow
                if (Math.abs((px + logW) - other.x) < thresh)        sx = other.x - logW
                if (Math.abs((px + logW) - (other.x + ow)) < thresh) sx = other.x + ow - logW
                if (Math.abs(py - other.y) < thresh)                 sy = other.y
                if (Math.abs(py - (other.y + oh)) < thresh)          sy = other.y + oh
                if (Math.abs((py + logH) - other.y) < thresh)        sy = other.y - logH
                if (Math.abs((py + logH) - (other.y + oh)) < thresh) sy = other.y + oh - logH
            }
            return Qt.point(sx, sy)
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !monRect.monitor.disabled
            cursorShape: monRect.monitor.disabled ? Qt.ArrowCursor
                : (monRect.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            drag.target: monRect
            drag.axis: Drag.XAndYAxis
            drag.threshold: 4

            onPressed: {
                monRect.dragX = monRect.monitor.x * monRect.scaleFactor + monRect.canvasOffset.x
                monRect.dragY = monRect.monitor.y * monRect.scaleFactor + monRect.canvasOffset.y
                monRect.snappedX = monRect.monitor.x
                monRect.snappedY = monRect.monitor.y
                monRect.isDragging = true
            }

            onPositionChanged: {
                if (!monRect.isDragging) return
                monRect.dragX = monRect.x
                monRect.dragY = monRect.y
                const realX = Math.round((monRect.x - monRect.canvasOffset.x) / monRect.scaleFactor)
                const realY = Math.round((monRect.y - monRect.canvasOffset.y) / monRect.scaleFactor)
                const snapped = monRect.snapPosition(realX, realY)
                monRect.snappedX = snapped.x
                monRect.snappedY = snapped.y
                monRect.positionDragging(monRect.monitorIndex, monRect.snappedX, monRect.snappedY)
            }

            onReleased: {
                monRect.isDragging = false
                if (monRect.snappedX === monRect.monitor.x && monRect.snappedY === monRect.monitor.y) {
                    monRect.monitorClicked(monRect.monitor.name)
                    return
                }
                monRect.positionCommitted(monRect.monitorIndex, monRect.snappedX, monRect.snappedY)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
        border.width: 1
        border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)

        Item {
            id: canvas
            anchors.fill: parent

            Repeater {
                model: root.monitorConfig.monitors.length
                delegate: MonitorSetupRect {
                    required property int index
                    monitor: root.monitorConfig.monitors[index]
                    monitorIndex: index
                    monitorConfig: root.monitorConfig
                    scaleFactor: root.scaleFactor
                    canvasOffset: root.offset
                    allMonitors: root.monitorConfig.monitors
                    isSelected: monitor.name === root.selectedMonitorName
                    previewPositions: root.previewPositions
                    hasOverlap: root.dragHasOverlap && isDragging
                    placementsForMonitor: root.placementsForMonitor

                    onMonitorClicked: name => {
                        root.selectedMonitorName = name
                        root.monitorSelected(name)
                    }
                    onPositionDragging: (idx, x, y) => root.updatePreview(idx, x, y)
                    onPositionCommitted: (idx, x, y) => {
                        const hadOverlap = root.dragHasOverlap
                        root.previewPositions = {}
                        root.dragHasOverlap = false
                        if (!hadOverlap)
                            root.commitPosition(idx, x, y)
                    }
                }
            }
        }
    }
}
