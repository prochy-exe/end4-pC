pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU and Disk usage.
 */
Singleton {
    id: root
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    property list<var> topCpuProcesses: []
    property list<var> topMemoryProcesses: []
    property list<var> topGpuProcesses: []
    property list<var> topGpuMemoryProcesses: []
    property real gpuUsage: -1
    property real gpuMemoryUsed: 0
    property real gpuMemoryTotal: 0
    property string gpuName: ""
    readonly property bool gpuAvailable: gpuUsage >= 0

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    property real cpuTemp: 0

    property real diskTotal: 1
    property real diskUsed: 0
    property real diskFree: 0
    property real diskUsedPercentage: diskTotal > 0 ? diskUsed / diskTotal : 0
    property list<real> diskUsageHistory: []
    property string maxAvailableDiskString: kbToGbString(diskTotal)

    Process {
        id: tempProc
        command: ["sensors"]
        stdout: StdioCollector {
            onStreamFinished: {
                const temperature = text.match(/(?:Package id 0|Tctl|Tdie)[^\n]*?\+([0-9.]+)°C/)
                root.cpuTemp = temperature ? Number(temperature[1]) : NaN
            }
        }
    }

    Process {
        id: diskProc
        command: ["df", "-k", "--output=size,used,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text.trim().split("\n")[1] ?? "").trim().split(/\s+/).map(Number)
                if (parts.length >= 3) {
                    root.diskTotal = parts[0]
                    root.diskUsed  = parts[1]
                    root.diskFree  = parts[2]
                }
            }
        }
    }

    Process {
        id: processSnapshotProc
        command: ["ps", "-eo", "comm=,%cpu=,%mem=,rss=,pid=", "--sort=-%cpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                const processes = []
                for (const line of text.trim().split("\n")) {
                    const match = line.match(/^(.+?)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s*$/)
                    if (match)
                        processes.push({ name: match[1].trim(), cpu: Number(match[2]), memory: Number(match[3]), rss: Number(match[4]), pid: Number(match[5]) })
                }
                root.topCpuProcesses = processes.slice(0, 4)
                root.topMemoryProcesses = processes.sort((a, b) => b.rss - a.rss || a.pid - b.pid).slice(0, 4)
            }
        }
    }

    Process {
        id: processAndGpuProc
        command: ["bash", "-c", "if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,name --format=csv,noheader,nounits 2>/dev/null | head -n 1 | awk -F', ' '{printf \"GPU|%s|%s|%s|%s\\n\",$1,$2,$3,$4}'; nvidia-smi pmon -c 1 2>/dev/null | awk 'NR>2 && $2 ~ /^[0-9]+$/ && $4 != \"-\" {print $2 \"|\" $4}' | sort -t'|' -k2,2nr | head -n 4 | while IFS='|' read -r pid usage; do commandName=$(ps -p \"$pid\" -o comm= 2>/dev/null | head -n 1); [ -n \"$commandName\" ] && printf \"GPUPROC|%s|%s\\n\" \"$commandName\" \"$usage\"; done; nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | sort -t, -k3 -nr | head -n 4 | while IFS=, read -r pid processName memory; do commandName=$(ps -p \"$pid\" -o comm= 2>/dev/null | head -n 1); [ -n \"$commandName\" ] || commandName=${processName##*/}; commandName=${commandName%% *}; printf \"GPUVRAMPROC|%s|%s\\n\" \"$commandName\" \"$memory\"; done; else for busy in /sys/class/drm/card*/device/gpu_busy_percent /sys/class/drm/card*/device/gt_busy_percent; do if [ -r \"$busy\" ]; then usage=$(cat \"$busy\"); usedFile=${busy%/*}/mem_info_vram_used; totalFile=${busy%/*}/mem_info_vram_total; used=0; total=0; [ -r \"$usedFile\" ] && used=$(awk '{printf \"%.0f\",$1/1048576}' \"$usedFile\"); [ -r \"$totalFile\" ] && total=$(awk '{printf \"%.0f\",$1/1048576}' \"$totalFile\"); printf \"GPU|%s|%s|%s|DRM GPU\\n\" \"$usage\" \"$used\" \"$total\"; break; fi; done; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const gpuProcesses = []
                const gpuMemoryProcesses = []
                let foundGpu = false
                for (const line of text.trim().split("\n")) {
                    const parts = line.split("|")
                    if (parts[0] === "GPU" && parts.length >= 5) {
                        root.gpuUsage = Number(parts[1])
                        root.gpuMemoryUsed = Number(parts[2])
                        root.gpuMemoryTotal = Number(parts[3])
                        root.gpuName = parts.slice(4).join("|").trim()
                        foundGpu = true
                    } else if (parts[0] === "GPUPROC" && parts.length >= 3)
                        gpuProcesses.push({ name: parts[1], usage: Number(parts[2]) })
                    else if (parts[0] === "GPUVRAMPROC" && parts.length >= 3)
                        gpuMemoryProcesses.push({ name: parts[1], memory: Number(parts[2]) })
                }
                root.topGpuProcesses = gpuProcesses
                root.topGpuMemoryProcesses = gpuMemoryProcesses
                if (!foundGpu) {
                    root.gpuUsage = -1
                    root.gpuMemoryUsed = 0
                    root.gpuMemoryTotal = 0
                    root.gpuName = ""
                    root.topGpuProcesses = []
                    root.topGpuMemoryProcesses = []
                }
            }
        }
    }

    Timer {
        interval: Config?.options.resources.updateInterval ?? 3000
        running: true
        repeat: true
        onTriggered: {
            tempProc.running = true
            diskProc.running = true
            processSnapshotProc.running = true
            processAndGpuProc.running = true
        }
    }

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function updateMemoryUsageHistory() {
        const history = [...memoryUsageHistory, memoryUsedPercentage]
        if (history.length > historyLength) history.shift()
        memoryUsageHistory = history
    }
    function updateSwapUsageHistory() {
        const history = [...swapUsageHistory, swapUsedPercentage]
        if (history.length > historyLength) history.shift()
        swapUsageHistory = history
    }
    function updateCpuUsageHistory() {
        const history = [...cpuUsageHistory, cpuUsage]
        if (history.length > historyLength) history.shift()
        cpuUsageHistory = history
    }
    function updateDiskUsageHistory() {
        const history = [...diskUsageHistory, diskUsedPercentage]
        if (history.length > historyLength) history.shift()
        diskUsageHistory = history
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
        updateDiskUsageHistory()
    }

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()

            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree  = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal   = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree    = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            const textStat = fileStat.text()
            const cpuLine  = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle  = stats[3]
                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff  = idle  - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }
                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat;    path: "/proc/stat" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
