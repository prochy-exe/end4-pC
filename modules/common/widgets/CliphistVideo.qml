import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    property string entry
    property real maxWidth
    property real maxHeight
    property bool blur: false

    readonly property string fileUri: StringUtils.cleanCliphistEntry(root.entry)
    readonly property string decodedPath: {
        if (!fileUri || !fileUri.startsWith("file://")) return ""
        // Keep a single leading slash for absolute paths.
        const withoutScheme = fileUri.slice("file://".length)
        return decodeURIComponent(withoutScheme)
    }

    property string thumbnailDir: "/tmp/quickshell/media/cliphist-video-thumbs"
    property string thumbnailPath: `${thumbnailDir}/${Qt.md5(fileUri)}.jpg`
    property string sourcePath: ""
    property int mediaWidth: thumbnail.status === Image.Ready ? thumbnail.sourceSize.width : 0
    property int mediaHeight: thumbnail.status === Image.Ready ? thumbnail.sourceSize.height : 0
    property real scale: {
        if (mediaWidth <= 0 || mediaHeight <= 0)
            return 1
        return Math.min(maxWidth / mediaWidth, maxHeight / mediaHeight, 1)
    }

    color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
    radius: Appearance.rounding.small
    implicitWidth: mediaWidth > 0 ? mediaWidth * scale : Math.min(maxWidth, 180)
    implicitHeight: mediaHeight > 0 ? mediaHeight * scale : Math.min(maxHeight, 100)
    clip: true

    Component.onCompleted: {
        if (root.decodedPath.length > 0)
            thumbnailProc.running = true
    }

    onEntryChanged: {
        if (root.decodedPath.length > 0) {
            thumbnailProc.running = false
            thumbnailProc.running = true
        }
    }

    Process {
        id: thumbnailProc
        command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.thumbnailDir)}' && [ -f '${StringUtils.shellSingleQuoteEscape(root.thumbnailPath)}' ] || ffmpeg -y -ss 0.2 -i '${StringUtils.shellSingleQuoteEscape(root.decodedPath)}' -frames:v 1 '${StringUtils.shellSingleQuoteEscape(root.thumbnailPath)}' >/dev/null 2>&1`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.sourcePath = root.thumbnailPath
            } else {
                root.sourcePath = ""
            }
        }
    }

    StyledImage {
        id: thumbnail
        anchors.fill: parent
        source: root.sourcePath
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Rectangle {
        visible: root.sourcePath.length === 0
        anchors.fill: parent
        color: MonitorThemes.shellColorForItem(root, "colLayer2", Appearance.colors.colLayer2)
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Video")
            color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Loader {
        id: blurLoader
        active: root.blur
        anchors.fill: parent
        sourceComponent: GaussianBlur {
            source: thumbnail
            radius: 35
            samples: radius * 2 + 1
        }
    }
}
