import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    signal requestReset()

    configEntryName: "media"

    readonly property var playerList: MprisController.players
    readonly property MprisPlayer currentPlayer: MprisController.activePlayer
    property var artUrl: currentPlayer?.trackArtUrl
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`

    property real widgetWidth: 420
    property real widgetHeight: 120
    property real buttonSize: 34
    property real buttonIconSize: 18

    property bool downloaded: false
    property bool showLyrics: false

    property string displayedArtFilePath: {
        if (!root.downloaded) return ""
        if (root.artUrl && root.artUrl.startsWith("file://")) return root.artUrl
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : ""
    }

    implicitHeight: card.implicitHeight
    implicitWidth: card.implicitWidth

    onArtFilePathChanged: updateArt()

    function updateArt() {
        if (!root.artUrl || root.artUrl.length === 0) {
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
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.downloaded = true }
    }

    StyledRectangularShadow {
        target: card
        z: -2
    }

    Rectangle {
        id: card
        implicitWidth: root.widgetWidth
        implicitHeight: root.widgetHeight + (root.showLyrics ? 264 : 0)
        radius: Appearance.rounding?.verylarge ?? 30
        color: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
        clip: true

        Behavior on implicitHeight {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            // Main Row
            Item {
                width: parent.width
                height: root.widgetHeight

                Rectangle {
                    id: artRect
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: root.widgetHeight
                    color: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                    topLeftRadius: card.radius
                    bottomLeftRadius: card.radius
                    topRightRadius: 0
                    bottomRightRadius: 0
                    clip: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artRect.width
                            height: artRect.height
                            topLeftRadius: card.radius
                            bottomLeftRadius: card.radius
                            topRightRadius: 0
                            bottomRightRadius: 0
                        }
                    }

                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: artRect.width * 2
                        sourceSize.height: artRect.height * 2
                        visible: root.displayedArtFilePath !== ""
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: "music_note"
                        iconSize: root.widgetHeight / 3
                        color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                        visible: root.displayedArtFilePath === ""
                    }
                }

                ColumnLayout {
                    anchors {
                        left: artRect.right
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 16
                        rightMargin: 14
                    }
                    spacing: -10

                    // Artist + Title
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.currentPlayer?.trackArtist ?? "Play"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.currentPlayer?.trackTitle ?? Translation.tr("Something")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                            opacity: 0.65
                            elide: Text.ElideRight
                        }
                    }

                    // Controls
                    Rectangle {
                        id: controlsPill
                        Layout.alignment: Qt.AlignRight
                        implicitWidth: controlsRow.implicitWidth + 10
                        implicitHeight: root.buttonSize + 8
                        radius: Appearance.rounding?.full ?? 999
                        color: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer), 0.9)

                        RowLayout {
                            id: controlsRow
                            anchors.centerIn: parent
                            spacing: 2

                            RippleButton {
                                implicitWidth: root.buttonSize
                                implicitHeight: root.buttonSize
                                buttonRadius: Appearance.rounding?.full ?? 999
                                colBackground: root.showLyrics
                                    ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                                    : "transparent"
                                colBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
                                colRipple: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                                downAction: () => { root.showLyrics = !root.showLyrics }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "lyrics"
                                    iconSize: root.buttonIconSize
                                    fill: root.showLyrics ? 1 : 0
                                    color: root.showLyrics
                                        ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
                                        : MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                                }
                            }

                            MaterialShapeWrappedMaterialSymbol {
                                shape: MaterialShape.Shape.Cookie12Sided
                                color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                                colSymbol: MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
                                text: root.currentPlayer?.isPlaying ? "pause" : "play_arrow"
                                iconSize: root.buttonIconSize + 12
                                fill: 1
                                padding: 8

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.currentPlayer?.togglePlaying()
                                }
                            }

                            RippleButton {
                                implicitWidth: root.buttonSize
                                implicitHeight: root.buttonSize
                                buttonRadius: Appearance.rounding?.full ?? 999
                                colBackground: "transparent"
                                colBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
                                colRipple: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                                downAction: () => root.currentPlayer?.next()
                                altAction: () => root.currentPlayer?.previous()

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "skip_next"
                                    iconSize: root.buttonIconSize
                                    fill: 1
                                    color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                                }
                            }
                        }
                    }
                }
            }

            // Divisor
            Item {
                width: parent.width
                height: root.showLyrics ? 2 : 0
                visible: root.showLyrics

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.2; color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) }
                        GradientStop { position: 0.8; color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    opacity: 0.15
                }
            }

            Item {
                width: parent.width
                height: root.showLyrics ? 250 : 0
                visible: root.showLyrics

                Lyrics {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    textAlignment: Text.AlignHCenter
                    textColor: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                    activeColor: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    dimColor: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    indicatorColor: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    indicatorShapeColor: MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
                }
            }
        }
    }
}
