import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar

Item {
    id: root
    implicitWidth: Appearance.sizes.verticalBarWidth
    height: parent.height
    property var screen: root.QsWindow.window?.screen

    readonly property real barPadding: 0
    readonly property string monitorName: root.screen?.name ?? ""
    readonly property bool isMaterial: Config.getBarSetting(monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    readonly property bool trayHasItems: SystemTray.items.values.length > 0
    readonly property var monitorLayoutEntry: {
        const screenName = root.screen?.name ?? ""
        const layouts = Config.options.bar.monitorLayouts ?? []
        return layouts.find(item => item.name === screenName) ?? null
    }

    function resolvedLayout(layoutKey) {
        const override = root.monitorLayoutEntry?.[layoutKey]
        return override !== undefined ? override : Config.options.bar.layouts[layoutKey]
    }

    function filterLayout(layout) {
        return trayHasItems ? layout : layout.filter(name => name !== "sysTray")
    }

    readonly property var effectiveLeftLayout:   filterLayout(root.resolvedLayout("leftLayout"))
    readonly property var effectiveMiddleLayout: filterLayout(root.resolvedLayout("middleLayout"))
    readonly property var effectiveRightLayout:  filterLayout(root.resolvedLayout("rightLayout"))
    readonly property string currentBorderless: Config.getBarSetting(root.monitorName, ["borderless"], Config.options.bar.borderless)
    readonly property bool currentBottom: Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom)

    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0
    readonly property int currentCornerStyle: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle)
    readonly property real centerPillY: centerPill.y
    readonly property real centerPillHeight: centerPill.height

    function shouldPaintMaterialPill(name) {
        if (!root.isMaterial) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "media", "docktoPanel", "leftSidebarButton"];
        if (blacklist.includes(name)) {
            return false;
        }
        return true;
    }

    function getMaterialPillColor(name) {
        if (!root.isMaterial) return Appearance.colors.colPrimaryContainer;
        switch(name) {
            case "media":
            case "sysTray":
                return Appearance.colors.colSecondaryContainer;
            case "resources":
                return Appearance.colors.colTertiaryContainer;
            case "systemIcons":
                return Appearance.colors.colPrimary; 
            default:
                return Appearance.colors.colPrimaryContainer;
        }
    }

    function getWidgetUrl(name) {
        if (!name) return "";
        let formattedName = name.charAt(0).toUpperCase() + name.slice(1);
        return Qt.resolvedUrl("../bar/" + formattedName + ".qml");
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer" || w === "visualizerInput").length
        return prevCount % 2 === 1
    }

    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: root.currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        }
        color: (Config.getBarSetting(root.monitorName, ["showBackground"], Config.options.bar.showBackground) && root.currentCornerStyle !== 2 && !root.isMaterial && !root.centerOnly)
            ? Appearance.colors.colLayer0 : "transparent"
        radius: root.currentCornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!root.centerOnly && root.currentCornerStyle === 1) ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    // centerOnly
    Rectangle {
        id: centerPill
        visible: root.centerOnly && Config.getBarSetting(root.monitorName, ["showBackground"], Config.options.bar.showBackground) && root.currentCornerStyle !== 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: middleCol.implicitHeight + 7
        width: parent.width - (root.currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
        color: Appearance.colors.colLayer0
        radius: root.currentCornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: root.currentCornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        bottomRightRadius: root.currentCornerStyle === 0 && !Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        topRightRadius:    root.currentCornerStyle === 0 && !Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        bottomLeftRadius:  root.currentCornerStyle === 0 && Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     root.currentCornerStyle === 0 && Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Top
        Item {
            anchors.top: parent.top
            anchors.topMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (root.currentCornerStyle === 1 ? 4 : 10)
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? topMaterialPill.implicitHeight : topCol.implicitHeight

            Rectangle {
                id: topMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: topMaterialCol.implicitWidth
                implicitHeight: topMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0

                ColumnLayout {
                    id: topMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveLeftLayout
                        delegate: topMaterialGroupDelegate
                    }

                    Component {
                        id: topMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveLeftLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: topCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.currentBorderless === "transparent" ? -4 : 2

                Repeater {
                    model: root.effectiveLeftLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveLeftLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            anchors.centerIn: parent
            width: parent.width
            height: root.isMaterial ? centerMaterialPill.implicitHeight : middleCol.implicitHeight

            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: centerMaterialCol.implicitWidth 
                implicitHeight: centerMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0

                ColumnLayout {
                    id: centerMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveMiddleLayout
                        delegate: centerMaterialGroupDelegate
                    }

                    Component {
                        id: centerMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveMiddleLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: middleCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.currentBorderless === "transparent" ? -4 : 2

                Repeater {
                    model: root.effectiveMiddleLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveMiddleLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                            }
                        }
                    }
                }
            }
        }

        // Bottom
        Item {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (root.currentCornerStyle === 1 ? 4 : 10)
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? bottomMaterialPill.implicitHeight : bottomCol.implicitHeight

            Rectangle {
                id: bottomMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: bottomMaterialCol.implicitWidth
                implicitHeight: bottomMaterialCol.implicitHeight + 10 
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0

                ColumnLayout {
                    id: bottomMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveRightLayout
                        delegate: bottomMaterialGroupDelegate
                    }

                    Component {
                        id: bottomMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.effectiveRightLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                Layout.fillWidth: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                    if (item && item.hasOwnProperty("mirrored"))
                                        item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: bottomCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.currentBorderless === "transparent" ? -4 : 2

                Repeater {
                    model: root.effectiveRightLayout
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.effectiveRightLayout.length
                        Loader {
                            Layout.fillWidth: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                                if (item && item.hasOwnProperty("mirrored"))
                                    item.mirrored = root.getMirroredForIndex(root.effectiveRightLayout, index)
                            }
                        }
                    }
                }
            }
        }
    }
}