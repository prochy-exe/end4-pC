pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    property bool busy: ocrProc.running

    function startFromScreenshotPath(screenshotPath, x, y, width, height) {
        const rx = Math.round(x)
        const ry = Math.round(y)
        const rw = Math.round(width)
        const rh = Math.round(height)
        const path = StringUtils.shellSingleQuoteEscape(`${screenshotPath ?? ""}`)

        if (rw <= 0 || rh <= 0 || path.length === 0) {
            Quickshell.execDetached(["notify-send", Translation.tr("OCR"), Translation.tr("Invalid OCR region"), "-a", "Shell"])
            return
        }

        if (ocrProc.running)
            ocrProc.running = false

        GlobalStates.ocrActionsPopupOpen = false
        ocrProc.buffer = ""
        ocrProc.errBuffer = ""

        const cmd = [
            "set -e",
            `trap "rm -f '${path}'" EXIT`,
            `magick '${path}' -crop ${rw}x${rh}+${rx}+${ry} +repage '${path}'`,
            `tesseract '${path}' stdout`
        ].join(" && ")

        ocrProc.command = ["bash", "-lc", cmd]
        ocrTimeoutTimer.restart()
        ocrProc.running = true
    }

    function finish(exitCode) {
        ocrTimeoutTimer.stop()

        if (exitCode !== 0) {
            const err = `${ocrProc.errBuffer ?? ""}`.trim()
            Quickshell.execDetached(["notify-send", Translation.tr("OCR"), err.length > 0 ? err : Translation.tr("OCR failed"), "-a", "Shell"])
            return
        }

        const text = `${ocrProc.buffer ?? ""}`.trim()
        if (text.length === 0) {
            Quickshell.execDetached(["notify-send", Translation.tr("OCR"), Translation.tr("No text detected"), "-a", "Shell"])
            return
        }

        GlobalStates.lastOcrText = text
        GlobalStates.lastOcrCapturedMs = Date.now()
        Quickshell.clipboardText = text
        GlobalStates.ocrActionsPopupOpen = true
        Quickshell.execDetached(["notify-send", Translation.tr("OCR"), Translation.tr("Text copied to clipboard"), "-a", "Shell"])
    }

    function cancelTimedOut() {
        if (!ocrProc.running)
            return
        ocrProc.running = false
        Quickshell.execDetached(["notify-send", Translation.tr("OCR"), Translation.tr("OCR timed out after 15s"), "-a", "Shell"])
    }

    Process {
        id: ocrProc
        running: false
        command: ["bash", "-lc", "true"]
        property string buffer: ""
        property string errBuffer: ""

        stdout: SplitParser {
            onRead: data => {
                if (ocrProc.buffer.length > 0)
                    ocrProc.buffer += "\n"
                ocrProc.buffer += data
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (ocrProc.errBuffer.length > 0)
                    ocrProc.errBuffer += "\n"
                ocrProc.errBuffer += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.finish(exitCode)
        }
    }

    Timer {
        id: ocrTimeoutTimer
        interval: 15000
        repeat: false
        onTriggered: root.cancelTimedOut()
    }
}
