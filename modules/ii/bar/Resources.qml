import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

BarWidgetSwitcherArea {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool alwaysShowAllResources: false
    horizontalExtraPadding: 12

    hoverEnabled: !Config.getBarSetting(root.monitorName, ["tooltips", "clickToShow"], Config.options.bar.tooltips.clickToShow)
    rowDefault: Component {
            RowLayout {
                property string monitorName: root.monitorName
                spacing: 0
                Resource {
                iconName: "memory"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowRam"], Config.options.bar.resources.alwaysShowRam)
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "memoryWarningThreshold"], Config.options.bar.resources.memoryWarningThreshold)
            }
                Resource {
                iconName: "planner_review"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpu"], Config.options.bar.resources.alwaysShowCpu)
                percentage: ResourceUsage.cpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "cpuWarningThreshold"], Config.options.bar.resources.cpuWarningThreshold)
            }
                Resource {
                iconName: "developer_board"
                shown: ResourceUsage.gpuAvailable && Config.getBarSetting(root.monitorName, ["resources", "alwaysShowGpu"], Config.options.bar.resources.alwaysShowGpu)
                percentage: Math.max(0, ResourceUsage.gpuUsage / 100)
                Layout.leftMargin: shown ? 6 : 0
            }
                Resource {
                iconName: "thermostat"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpuTemp"], Config.options.bar.resources.alwaysShowCpuTemp)
                percentage: ResourceUsage.cpuTemp / 100
                Layout.leftMargin: shown ? 6 : 0
            }
                Resource {
                iconName: "hard_drive"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowDisk"], Config.options.bar.resources.alwaysShowDisk)
                percentage: ResourceUsage.diskUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
            }
                Resource {
                iconName: "swap_horiz"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowSwap"], Config.options.bar.resources.alwaysShowSwap)
                percentage: ResourceUsage.swapUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "swapWarningThreshold"], Config.options.bar.resources.swapWarningThreshold)
            }
        }
    }

    rowMaterial: Component {
        RowLayout {
            property string monitorName: root.monitorName
            spacing: 0
            Resource {
                iconName: "memory"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowRam"], Config.options.bar.resources.alwaysShowRam)
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "memoryWarningThreshold"], Config.options.bar.resources.memoryWarningThreshold)
            }
            Resource {
                iconName: "planner_review"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpu"], Config.options.bar.resources.alwaysShowCpu)
                percentage: ResourceUsage.cpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "cpuWarningThreshold"], Config.options.bar.resources.cpuWarningThreshold)
            }
            Resource {
                iconName: "developer_board"
                shown: ResourceUsage.gpuAvailable && Config.getBarSetting(root.monitorName, ["resources", "alwaysShowGpu"], Config.options.bar.resources.alwaysShowGpu)
                percentage: Math.max(0, ResourceUsage.gpuUsage / 100)
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "thermostat"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpuTemp"], Config.options.bar.resources.alwaysShowCpuTemp)
                percentage: ResourceUsage.cpuTemp / 100
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "hard_drive"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowDisk"], Config.options.bar.resources.alwaysShowDisk)
                percentage: ResourceUsage.diskUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "swap_horiz"
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowSwap"], Config.options.bar.resources.alwaysShowSwap)
                percentage: ResourceUsage.swapUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "swapWarningThreshold"], Config.options.bar.resources.swapWarningThreshold)
            }
        }
    }

    colDefault: Component {
        ColumnLayout {
            property string monitorName: root.monitorName
            spacing: 7
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "memory"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowRam"], Config.options.bar.resources.alwaysShowRam)
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "memoryWarningThreshold"], Config.options.bar.resources.memoryWarningThreshold)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "planner_review"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpu"], Config.options.bar.resources.alwaysShowCpu)
                percentage: ResourceUsage.cpuUsage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "cpuWarningThreshold"], Config.options.bar.resources.cpuWarningThreshold)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "developer_board"
                vertical: true
                shown: ResourceUsage.gpuAvailable && Config.getBarSetting(root.monitorName, ["resources", "alwaysShowGpu"], Config.options.bar.resources.alwaysShowGpu)
                percentage: Math.max(0, ResourceUsage.gpuUsage / 100)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "thermostat"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpuTemp"], Config.options.bar.resources.alwaysShowCpuTemp)
                percentage: ResourceUsage.cpuTemp / 100
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "hard_drive"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowDisk"], Config.options.bar.resources.alwaysShowDisk)
                percentage: ResourceUsage.diskUsedPercentage
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "swap_horiz"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowSwap"], Config.options.bar.resources.alwaysShowSwap)
                percentage: ResourceUsage.swapUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "swapWarningThreshold"], Config.options.bar.resources.swapWarningThreshold)
            }
        }
    }

    colMaterial: Component {
        ColumnLayout {
            property string monitorName: root.monitorName
            spacing: 7
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "memory"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowRam"], Config.options.bar.resources.alwaysShowRam)
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "memoryWarningThreshold"], Config.options.bar.resources.memoryWarningThreshold)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "planner_review"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpu"], Config.options.bar.resources.alwaysShowCpu)
                percentage: ResourceUsage.cpuUsage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "cpuWarningThreshold"], Config.options.bar.resources.cpuWarningThreshold)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "developer_board"
                vertical: true
                shown: ResourceUsage.gpuAvailable && Config.getBarSetting(root.monitorName, ["resources", "alwaysShowGpu"], Config.options.bar.resources.alwaysShowGpu)
                percentage: Math.max(0, ResourceUsage.gpuUsage / 100)
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "thermostat"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowCpuTemp"], Config.options.bar.resources.alwaysShowCpuTemp)
                percentage: ResourceUsage.cpuTemp / 100
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "hard_drive"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowDisk"], Config.options.bar.resources.alwaysShowDisk)
                percentage: ResourceUsage.diskUsedPercentage
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "swap_horiz"
                vertical: true
                shown: Config.getBarSetting(root.monitorName, ["resources", "alwaysShowSwap"], Config.options.bar.resources.alwaysShowSwap)
                percentage: ResourceUsage.swapUsedPercentage
                warningThreshold: Config.getBarSetting(root.monitorName, ["resources", "swapWarningThreshold"], Config.options.bar.resources.swapWarningThreshold)
            }
        }
    }

}
