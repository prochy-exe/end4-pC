import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    implicitHeight: Appearance.sizes.barHeight
    width: parent.width
    readonly property real barPadding: 0
    // Settable from outside (Bar.qml passes barRoot.currentMonitorName, which is
    // reliable since it comes from the PanelWindow's own `screen` property).
    // root.screen?.name here is only a fallback for standalone/unset usage -
    // root.QsWindow (which root.screen depends on) isn't reliably available yet
    // for Loader-instantiated content, so relying on it alone left monitorName
    // permanently stuck at "" for every bar widget, silently breaking every
    // per-monitor bar setting.
    property string monitorName: root.screen?.name ?? ""
    function themeColor(role, fallback) {
        return MonitorThemes.color(root.monitorName, role, fallback)
    }
    readonly property bool isMaterial: Config.getBarSetting(monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    readonly property real centerPillX: centerPill.x
    readonly property real centerPillWidth: centerPill.width
    property var screen: root.QsWindow.window?.screen

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

    function getWidgetUrl(name) {
        if (!name) return "";
        let formattedName = name.charAt(0).toUpperCase() + name.slice(1);
        return Qt.resolvedUrl("./" + formattedName + ".qml");
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer" || w === "visualizerInput").length
        return prevCount % 2 === 1
    }

    function shouldPaintMaterialPill(name) {
        if (root.isMaterial !== true) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "docktoPanel", "leftSidebarButton", "activeWindow", "systemIcons"];
        if (blacklist.includes(name)) {
            return false;
        }
        return true;
    }

    function getMaterialPillColor(name) {
        if (root.isMaterial !== true) return MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer);
        switch(name) {
            case "media":
            case "sysTray":
                return MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer);
            case "resources":
                return MonitorThemes.shellColorForItem(root, "colTertiaryContainer", Appearance.colors.colTertiaryContainer);
            case "systemIcons":
                return MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary);
            default:
                return MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer);
        }
    }
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0


    Rectangle {
        id: barBackground
        anchors.fill: parent
        anchors.margins: root.currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        color: (!centerOnly && Config.getBarSetting(root.monitorName, ["showBackground"], Config.options.bar.showBackground) && root.currentCornerStyle !== 2 && !root.isMaterial)
            ? root.themeColor("surface_container_low", MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)) : "transparent"
        radius: root.currentCornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!centerOnly && root.currentCornerStyle === 1) ? 1 : 0
        border.color: root.themeColor("outline_variant", MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border))
    }

    // center-only
    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0
    readonly property int currentCornerStyle: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle)

    Rectangle {
        id: centerPill
        visible: centerOnly && Config.getBarSetting(root.monitorName, ["showBackground"], Config.options.bar.showBackground) && root.currentCornerStyle !== 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: middleRow.implicitWidth + 10
        height: parent.height - (root.currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
        color: root.themeColor("surface_container_low", MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0))
        radius: root.currentCornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: root.currentCornerStyle === 1 ? 1 : 0
        border.color: root.themeColor("outline_variant", MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border))

        bottomLeftRadius:  root.currentCornerStyle === 0 && !Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        bottomRightRadius: root.currentCornerStyle === 0 && !Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     root.currentCornerStyle === 0 && Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
        topRightRadius:    root.currentCornerStyle === 0 && Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom) ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Left
        Item {
            anchors.left: parent.left
            anchors.leftMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (root.currentCornerStyle === 1 ? 4 : 10)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.isMaterial ? leftMaterialPill.implicitWidth : leftRow.implicitWidth

            // Material pill wrapper
            Rectangle {
                id: leftMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: leftMaterialRow.implicitWidth + 10
                implicitHeight: leftMaterialRow.implicitHeight
                radius: Appearance.rounding.full
                color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)

                RowLayout {
                    id: leftMaterialRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveLeftLayout
                        delegate: leftMaterialGroupDelegate
                    }

                    Component {
                        id: leftMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveLeftLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            monitorName: root.monitorName
                            Loader {
                                property string monitorName: root.monitorName
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item)
                                        item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: leftRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: root.currentBorderless === "transparent" ? -7 : 2

                Repeater {
                    model: root.effectiveLeftLayout
                    delegate: leftBarGroupDelegate
                }

                Component {
                    id: leftBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveLeftLayout.length
                        monitorName: root.monitorName
                        Loader {
                            property string monitorName: root.monitorName
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item)
                                    item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: leftNoGroupDelegate
                    Loader {
                        property string monitorName: root.monitorName
                        Layout.fillHeight: false
                        Layout.topMargin: root.currentBottom ? -5 : 3
                        Layout.alignment: Qt.AlignVCenter
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item)
                                item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveLeftLayout, index)
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            anchors.centerIn: parent
            width: root.isMaterial ? centerMaterialPill.implicitWidth : middleRow.implicitWidth
            height: parent.height

            // Material pill wrapper
            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: centerMaterialRow.implicitWidth + 10
                implicitHeight: centerMaterialRow.implicitHeight
                radius: Appearance.rounding.full
                color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)

                RowLayout {
                    id: centerMaterialRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveMiddleLayout
                        delegate: middleMaterialGroupDelegate
                    }

                    Component {
                        id: middleMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveMiddleLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            monitorName: root.monitorName
                            Loader {
                                property string monitorName: root.monitorName
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item)
                                        item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: middleRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: root.currentBorderless === "transparent" ? -7 : 2

                Repeater {
                    model: root.effectiveMiddleLayout
                    delegate: middleBarGroupDelegate
                }

                Component {
                    id: middleBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveMiddleLayout.length
                        monitorName: root.monitorName
                        Loader {
                            property string monitorName: root.monitorName
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item)
                                    item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: middleNoGroupDelegate
                    Loader {
                        property string monitorName: root.monitorName
                        Layout.fillHeight: false
                        Layout.topMargin: root.currentBottom ? -5 : 3
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item)
                                item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveMiddleLayout, index)
                        }
                    }
                }
            }
        }

        // Right
        Item {
            anchors.right: parent.right
            anchors.rightMargin: root.isMaterial ? (Config.options.hyprland.general.gapsOut || 5) : (root.currentCornerStyle === 1 ? 4 : 10)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.isMaterial ? rightMaterialPill.implicitWidth : rightRow.implicitWidth

            // Material pill wrapper
            Rectangle {
                id: rightMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: rightMaterialRow.implicitWidth + 10
                implicitHeight: rightMaterialRow.implicitHeight
                radius: Appearance.rounding.full
                color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)

                RowLayout {
                    id: rightMaterialRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.effectiveRightLayout
                        delegate: rightMaterialGroupDelegate
                    }

                    Component {
                        id: rightMaterialGroupDelegate
                        BarGroup {
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: root.effectiveRightLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            monitorName: root.monitorName
                            Loader {
                                property string monitorName: root.monitorName
                                Layout.fillHeight: true
                                source: root.getWidgetUrl(modelData)
                                onLoaded: {
                                    if (item)
                                        item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveRightLayout, index)
                                }
                            }
                        }
                    }
                }
            }

            // Non-material layout
            RowLayout {
                id: rightRow
                visible: !root.isMaterial
                anchors.fill: parent
                spacing: root.currentBorderless === "transparent" ? -7 : 2

                Repeater {
                    model: root.effectiveRightLayout
                    delegate: rightBarGroupDelegate
                }

                Component {
                    id: rightBarGroupDelegate
                    BarGroup {
                        Layout.fillHeight: true
                        currentIndex: index
                        totalCount: root.effectiveRightLayout.length
                        monitorName: root.monitorName
                        Loader {
                            property string monitorName: root.monitorName
                            Layout.fillHeight: true
                            source: root.getWidgetUrl(modelData)
                            onLoaded: {
                                if (item)
                                    item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveRightLayout, index)
                            }
                        }
                    }
                }

                Component {
                    id: rightNoGroupDelegate
                    Loader {
                        property string monitorName: root.monitorName
                        Layout.fillHeight: false
                        Layout.topMargin: root.currentBottom ? -5 : 3
                        source: root.getWidgetUrl(modelData)
                        onLoaded: {
                            if (item)
                                item.LayoutMirroring.enabled = root.getMirroredForIndex(root.effectiveRightLayout, index)
                        }
                    }
                }
            }
        }
    }
}
