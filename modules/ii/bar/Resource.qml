import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import qs.services
import QtQuick.Layouts

Item {
    id: root
    property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    required property string iconName
    required property double percentage
    property bool vertical: false
    property int warningThreshold: 100
    property bool shown: true
    readonly property string detailLabel: {
        switch (iconName) {
        case "memory": return "RAM"
        case "planner_review": return "CPU"
        case "developer_board": return "GPU"
        case "thermostat": return "CPU Temp"
        case "hard_drive": return "Disk"
        case "swap_horiz": return "Swap"
        default: return "Resource"
        }
    }
    readonly property string detailSublabel: {
        if (iconName === "memory") return root.formatKB(ResourceUsage.memoryUsed) + " / " + root.formatKB(ResourceUsage.memoryTotal)
        if (iconName === "planner_review" || iconName === "thermostat") return `${Math.round(ResourceUsage.cpuTemp)}°C`
        if (iconName === "developer_board") return ResourceUsage.gpuMemoryTotal > 0
            ? `${ResourceUsage.gpuMemoryUsed} / ${ResourceUsage.gpuMemoryTotal} MB`
            : (ResourceUsage.gpuName || "Usage unavailable")
        if (iconName === "hard_drive") return root.formatKB(ResourceUsage.diskUsed) + " / " + root.formatKB(ResourceUsage.diskTotal)
        if (iconName === "swap_horiz") return root.formatKB(ResourceUsage.swapUsed) + " / " + root.formatKB(ResourceUsage.swapTotal)
        return ""
    }
    readonly property var detailRows: {
        if (iconName === "memory") return ResourceUsage.topMemoryProcesses.map(p => ({ icon: "memory", label: p.name, value: `${Number(p.memory).toFixed(1)}%` }))
        if (iconName === "planner_review") return ResourceUsage.topCpuProcesses.map(p => ({ icon: "speed", label: p.name, value: `${Number(p.cpu).toFixed(1)}%` }))
        if (iconName === "developer_board") return [
            ...ResourceUsage.topGpuProcesses.map(p => ({ section: "GPU utilization", icon: "monitoring", label: p.name, value: `${Math.round(p.usage)}%` })),
            ...ResourceUsage.topGpuMemoryProcesses.map(p => ({ section: "VRAM usage", icon: "memory", label: p.name, value: `${Math.round(p.memory)} MB` }))
        ]
        if (iconName === "thermostat") return [{ icon: "thermostat", label: "Temperature", value: `${Math.round(ResourceUsage.cpuTemp)}°C` }]
        if (iconName === "hard_drive") return [
            { icon: "storage", label: "Used", value: root.formatKB(ResourceUsage.diskUsed) },
            { icon: "check_circle", label: "Free", value: root.formatKB(ResourceUsage.diskFree) }
        ]
        if (iconName === "swap_horiz") return [
            { icon: "swap_horiz", label: "Used", value: root.formatKB(ResourceUsage.swapUsed) },
            { icon: "check_circle", label: "Free", value: root.formatKB(ResourceUsage.swapFree) }
        ]
        return []
    }
    clip: !vertical
    visible: shown
    implicitWidth: !shown ? 0 : (vertical ? Appearance.sizes.verticalBarWidth : resourceRowLayout.implicitWidth)
    implicitHeight: !shown ? 0 : (vertical ? resourceProgress.implicitHeight : Appearance.sizes.barHeight)
    property bool warning: percentage * 100 >= warningThreshold

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }


    Component {
        id: outlineStyle
        ClippedOutlineCircularProgress {
            lineWidth: Appearance.rounding.unsharpen
            value: root.percentage
            implicitSize: vertical ? 20 : 20
            colPrimary: root.warning ? MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError) : MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: root.iconName
                    iconSize: Appearance.font.pixelSize.normal
                    color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                }
            }
        }
    }

    Component {
        id: filledStyle
        ClippedFilledCircularProgress {
            lineWidth: Appearance.rounding.unsharpen
            value: root.percentage
            implicitSize: 20
            colPrimary: root.warning ? MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError) : MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
            accountForLightBleeding: !root.warning
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: vertical ? Font.Medium : Font.DemiBold
                    fill: 1
                    text: root.iconName
                    iconSize: Appearance.font.pixelSize.normal
                    color: MonitorThemes.m3ColorForItem(root, "m3onSecondaryContainer", Appearance.m3colors.m3onSecondaryContainer)
                }
            }
        }
    }

    // Vertical
    Loader {
        id: resourceProgress
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: Config.getBarSetting(root.monitorName, ["resources", "style"], Config.options.bar.resources.style) === "filled" ? filledStyle : outlineStyle
    }

    // Horizontal
    RowLayout {
        id: resourceRowLayout
        visible: !root.vertical
        spacing: 2
        x: shown ? 0 : -resourceRowLayout.width
        anchors.verticalCenter: parent.verticalCenter

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: !root.vertical
            visible: active
            sourceComponent: Config.getBarSetting(root.monitorName, ["resources", "style"], Config.options.bar.resources.style) === "filled" ? filledStyle : outlineStyle
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            visible: Config.getBarSetting(root.monitorName, ["resources", "showValue"], Config.options.bar.resources.showValue)
            implicitWidth: visible ? fullPercentageTextMetrics.width : 0
            implicitHeight: percentageText.implicitHeight
            TextMetrics {
                id: fullPercentageTextMetrics
                text: "100"
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                id: percentageText
                anchors.centerIn: parent
                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                font.pixelSize: Appearance.font.pixelSize.small
                text: `${Math.round(root.percentage * 100).toString()}`
            }
        }

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: root.shown && root.visible
    }

    ResourceDetailPopup {
        hoverTarget: hoverArea
        label: root.detailLabel
        iconName: root.iconName
        usage: root.percentage
        sublabel: root.detailSublabel
        detailRows: root.detailRows
    }

    Behavior on implicitWidth {
        enabled: false
    }
}
