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

    property string thermalPath: ""

    Process {
        id: findThermalPathProc
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ -d \"$h\" ] || continue; for l in \"$h\"/temp*_label; do [ -f \"$l\" ] || continue; if grep -qE 'Package id 0|Tctl|Tdie' \"$l\" 2>/dev/null; then inp=\"${l%_label}_input\"; [ -f \"$inp\" ] && echo \"$inp\" && exit 0; fi; done; done; for z in /sys/class/thermal/thermal_zone*; do [ -d \"$z\" ] || continue; type=$(cat \"$z/type\" 2>/dev/null); case \"$type\" in x86_pkg_temp|cpu*|TCPU) [ -f \"$z/temp\" ] && echo \"$z/temp\" && exit 0;; esac; done; for t in /sys/class/hwmon/hwmon*/temp1_input /sys/class/thermal/thermal_zone0/temp; do [ -f \"$t\" ] && echo \"$t\" && exit 0; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const foundPath = text.trim();
                if (foundPath.length > 0) {
                    root.thermalPath = foundPath;
                    fileTemp.reload();
                }
            }
        }
    }

    FileView {
        id: fileTemp
        path: root.thermalPath
        printErrors: false
        onLoaded: {
            const raw = parseFloat(fileTemp.text().trim());
            if (!isNaN(raw) && raw > 0) {
                root.cpuTemp = raw > 200 ? Math.round(raw / 100) / 10 : raw;
            }
        }
    }

    Process {
        id: tempProcFallback
        command: ["bash", "-c", "sensors 2>/dev/null | grep -E 'Package id 0|Tctl|Tdie' | grep -oP '\\+\\K[0-9.]+(?=°C)' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = parseFloat(text.trim());
                if (!isNaN(parsed) && parsed > 0) {
                    root.cpuTemp = parsed;
                }
            }
        }
    }

    Process {
        id: diskProc
        command: ["df", "-k", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 2) {
                    const parts = lines[1].trim().split(/\s+/).map(Number);
                    if (parts.length >= 4) {
                        root.diskTotal = parts[1];
                        root.diskUsed  = parts[2];
                        root.diskFree  = parts[3];
                    }
                }
            }
        }
    }

    Process {
        id: processAndGpuProc
        command: ["bash", "-c", "ps -eo comm=,%cpu=,%mem= --sort=-%cpu | head -n 4 | awk '{cpu=$(NF-1); mem=$NF; $NF=\"\"; $(NF-1)=\"\"; sub(/[ \\t]+$/, \"\"); printf \"CPU|%s|%s|%s\\n\",$0,cpu,mem}'; ps -eo comm=,%cpu=,%mem= --sort=-%mem | head -n 4 | awk '{cpu=$(NF-1); mem=$NF; $NF=\"\"; $(NF-1)=\"\"; sub(/[ \\t]+$/, \"\"); printf \"MEM|%s|%s|%s\\n\",$0,cpu,mem}'; if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,name --format=csv,noheader,nounits 2>/dev/null | head -n 1 | awk -F', ' '{printf \"GPU|%s|%s|%s|%s\\n\",$1,$2,$3,$4}'; nvidia-smi pmon -c 1 2>/dev/null | awk 'NR>2 && $2 ~ /^[0-9]+$/ && $4 != \"-\" {print $2 \"|\" $4}' | sort -t'|' -k2,2nr | head -n 4 | while IFS='|' read -r pid usage; do commandName=$(ps -p \"$pid\" -o comm= 2>/dev/null | head -n 1); [ -n \"$commandName\" ] && printf \"GPUPROC|%s|%s\\n\" \"$commandName\" \"$usage\"; done; nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | sort -t, -k3 -nr | head -n 4 | while IFS=, read -r pid processName memory; do commandName=$(ps -p \"$pid\" -o comm= 2>/dev/null | head -n 1); [ -n \"$commandName\" ] || commandName=${processName##*/}; commandName=${commandName%% *}; printf \"GPUVRAMPROC|%s|%s\\n\" \"$commandName\" \"$memory\"; done; else for busy in /sys/class/drm/card*/device/gpu_busy_percent /sys/class/drm/card*/device/gt_busy_percent; do if [ -r \"$busy\" ]; then usage=$(cat \"$busy\"); usedFile=${busy%/*}/mem_info_vram_used; totalFile=${busy%/*}/mem_info_vram_total; used=0; total=0; [ -r \"$usedFile\" ] && used=$(awk '{printf \"%.0f\",$1/1048576}' \"$usedFile\"); [ -r \"$totalFile\" ] && total=$(awk '{printf \"%.0f\",$1/1048576}' \"$totalFile\"); printf \"GPU|%s|%s|%s|DRM GPU\\n\" \"$usage\" \"$used\" \"$total\"; break; fi; done; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cpu = []
                const memory = []
                const gpuProcesses = []
                const gpuMemoryProcesses = []
                let foundGpu = false
                for (const line of text.trim().split("\n")) {
                    const parts = line.split("|")
                    if (parts[0] === "CPU" && parts.length >= 4)
                        cpu.push({ name: parts[1], cpu: Number(parts[2]), memory: Number(parts[3]) })
                    else if (parts[0] === "MEM" && parts.length >= 4)
                        memory.push({ name: parts[1], cpu: Number(parts[2]), memory: Number(parts[3]) })
                    else if (parts[0] === "GPU" && parts.length >= 5) {
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
                root.topCpuProcesses = cpu
                root.topMemoryProcesses = memory
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
            tempProc.running = false
            tempProc.running = true
            diskProc.running = false
            diskProc.running = true
            processAndGpuProc.running = false
            processAndGpuProc.running = true
        }
    }

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) memoryUsageHistory.shift()
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) swapUsageHistory.shift()
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) cpuUsageHistory.shift()
    }
    function updateDiskUsageHistory() {
        diskUsageHistory = [...diskUsageHistory, diskUsedPercentage]
        if (diskUsageHistory.length > historyLength) diskUsageHistory.shift()
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

            if (root.thermalPath.length > 0) {
                fileTemp.reload()
                const raw = parseFloat(fileTemp.text().trim())
                if (!isNaN(raw) && raw > 0) {
                    root.cpuTemp = raw > 200 ? Math.round(raw / 100) / 10 : raw
                }
            } else if (!findThermalPathProc.running) {
                tempProcFallback.running = false
                tempProcFallback.running = true
            }

            diskProc.running = false
            diskProc.running = true

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
