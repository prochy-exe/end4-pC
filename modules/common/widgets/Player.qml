pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    required property MprisPlayer player
    property var artUrl: player?.trackArtUrl ?? ""
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: ColorUtils.mix(
        (colorQuantizer?.colors[0] ?? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)),
        MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer),
        0.8) || MonitorThemes.colorForItem(root, "secondary_container", Appearance.m3colors.m3secondaryContainer)
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000
    property int visualizerSmoothing: 2
    property real radius
    property bool showLyrics: false
    // null = legacy fixed layout/always-shown visualizer (sidebar player).
    // Non-null = an explicit element list (e.g. Config.options.media.menuElements,
    // or a fixed list like the ticker's ["visualizer"]); the visualizer only
    // shows when "visualizer" is in that list.
    property var controlElements: null
    // Passed straight through to PlayerControls - 1.0 = unchanged.
    property real contentScale: 1.0
    // The full-card blurred art backdrop is cropped independently from the
    // sharp thumbnail inside PlayerControls - at a normal card's proportions
    // that's unnoticeable, but at the ticker's small/wide shape the two
    // crops don't line up and the blurred one reads as off-center.
    property bool showBlurredArt: true
    // Passed straight through to PlayerControls - false = unchanged.
    property bool centerContent: false
    // The ticker's window is sized to exactly this card's bounds with no
    // slack for a shadow to bleed into - it was getting clipped unevenly by
    // the mask/window edge instead of rendering as a clean, even shadow,
    // which read as lopsided top/bottom padding.
    property bool showShadow: true

    property string displayedArtFilePath: {
        if (!root.downloaded) return ""
        if (root.artUrl.startsWith("file://")) return root.artUrl
        return Qt.resolvedUrl(artFilePath)
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDominantColor = MonitorThemes.colorForItem(root, "secondary_container", Appearance.m3colors.m3secondaryContainer)
            root.downloaded = false
            return
        }

        if (root.artUrl.startsWith("file://")) {
            root.downloaded = true
            return
        }

        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    StyledRectangularShadow {
        visible: root.showShadow
        target: background
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        Image {
            id: blurredArt
            visible: root.showBlurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize.width: background.width
            sourceSize.height: background.height
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            visible: root.controlElements === null || root.controlElements.includes("visualizer")
            live: root.player?.isPlaying
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        Loader {
            id: layoutLoader
            anchors.fill: parent

            sourceComponent: root.showLyrics ? lyricsComponent : controlsComponent

            Component {
                id: controlsComponent
                PlayerControls {
                    player: root.player
                    blendedColors: root.blendedColors
                    displayedArtFilePath: root.displayedArtFilePath
                    radius: root.radius
                    controlElements: root.controlElements
                    contentScale: root.contentScale
                    centerContent: root.centerContent
                    onToggleLyrics: root.showLyrics = !root.showLyrics
                }
            }

            Component {
                id: lyricsComponent
                PlayerControlsLyrics {
                    player: root.player
                    blendedColors: root.blendedColors
                    displayedArtFilePath: root.displayedArtFilePath
                    radius: root.radius
                    artDominantColor: root.artDominantColor
                    onToggleLyrics: {
                        root.showLyrics = !root.showLyrics
                        Config.options.bar.media.showLyrics = root.showLyrics
                    }
                }
            }
        }
    }
}
