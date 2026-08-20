import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Io

StyledPopup {
    id: root

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function processDetails(processes, field, suffix) {
        if (!processes || processes.length === 0)
            return "No process data yet"
        return processes.map(p => `${p.name}: ${Number(p[field]).toFixed(1)}%${suffix}`).join("\n")
    }

    function resourceEnabled(setting) {
        return Config.getBarSetting(root.popupMonitorName, ["resources", setting], Config.options.bar.resources[setting])
    }

    Row {
        spacing: 5

        Column {
            spacing: 5

            ResourceCard {
                visible: root.resourceEnabled("alwaysShowRam")
                label: "RAM"
                iconText: "memory"
                iconShape: MaterialShape.Shape.Clover4Leaf
                value: ResourceUsage.memoryUsed / ResourceUsage.memoryTotal
                sublabel: root.formatKB(ResourceUsage.memoryUsed) + " / " + root.formatKB(ResourceUsage.memoryTotal)
                detailText: "Top memory users\n" + root.processDetails(ResourceUsage.topMemoryProcesses, "memory", " RAM")
            }

            ResourceCard {
                visible: root.resourceEnabled("alwaysShowCpu")
                label: "CPU"
                iconText: "planner_review"
                iconShape: MaterialShape.Shape.Gem
                value: ResourceUsage.cpuUsage
                sublabel: `${Math.round(ResourceUsage.cpuTemp)}°C`
                sublabelColor: ResourceUsage.cpuTemp > 80 ? MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError)
                    : ResourceUsage.cpuTemp > 60 ? MonitorThemes.m3ColorForItem(root, "m3tertiary", Appearance.m3colors.m3tertiary)
                    : MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                detailText: "Top CPU users\n" + root.processDetails(ResourceUsage.topCpuProcesses, "cpu", " CPU")
            }

            ResourceCard {
                visible: root.resourceEnabled("alwaysShowCpuTemp")
                label: "CPU Temp"
                iconText: "thermostat"
                iconShape: MaterialShape.Shape.Bun
                value: ResourceUsage.cpuTemp / 100
                sublabel: `${Math.round(ResourceUsage.cpuTemp)}°C`
                detailText: `CPU temperature\n${Math.round(ResourceUsage.cpuTemp)}°C`
            }
        }

        Column {
            spacing: 5

            ResourceCard {
                visible: root.resourceEnabled("alwaysShowSwap")
                label: "Swap"
                iconText: "swap_horiz"
                iconShape: MaterialShape.Shape.Bun
                value: ResourceUsage.swapUsedPercentage
                sublabel: root.formatKB(ResourceUsage.swapUsed) + " / " + root.formatKB(ResourceUsage.swapTotal)
                detailText: "Swap usage\n" + root.formatKB(ResourceUsage.swapUsed) + " used of " + root.formatKB(ResourceUsage.swapTotal)
            }

            ResourceCard {
                visible: root.resourceEnabled("alwaysShowDisk")
                label: "Disk"
                iconText: "hard_drive"
                iconShape: MaterialShape.Shape.Circle
                value: ResourceUsage.diskUsedPercentage
                sublabel: root.formatKB(ResourceUsage.diskUsed) + " / " + root.formatKB(ResourceUsage.diskTotal)
                detailText: "Disk usage\n" + root.formatKB(ResourceUsage.diskUsed) + " used of " + root.formatKB(ResourceUsage.diskTotal)
            }

            ResourceCard {
                visible: ResourceUsage.gpuAvailable && root.resourceEnabled("alwaysShowGpu")
                label: "GPU"
                iconText: "developer_board"
                iconShape: MaterialShape.Shape.Cookie4Sided
                value: ResourceUsage.gpuUsage / 100
                sublabel: ResourceUsage.gpuMemoryTotal > 0
                    ? `${ResourceUsage.gpuMemoryUsed} / ${ResourceUsage.gpuMemoryTotal} MB`
                    : (ResourceUsage.gpuName || "Usage unavailable")
                detailText: `${ResourceUsage.gpuName || "GPU"}\nUsage: ${Math.round(ResourceUsage.gpuUsage)}%${ResourceUsage.gpuMemoryTotal > 0 ? `\nVRAM: ${ResourceUsage.gpuMemoryUsed} / ${ResourceUsage.gpuMemoryTotal} MB` : ""}`
            }
        }
    }
}
