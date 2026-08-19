pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""

    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property bool borderless: Config.getBarSetting(root.monitorName, ["borderless"], Config.options.bar.borderless)
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    readonly property bool alwaysVisible: Config.getBarSetting(root.monitorName, ["media", "alwaysVisible"], Config.options.bar.media.alwaysVisible)
    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""
    property string trackTitle:  activePlayer?.trackTitle  ?? ""
    property string trackArtist: activePlayer?.trackArtist ?? ""
    property bool   isPlaying:   activePlayer?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    property string artDownloadLocation: Directories.coverArt
    property string artFileName:         Qt.md5(artUrl)
    property string artFilePath:         `${artDownloadLocation}/${artFileName}`
    property bool   artDownloaded:       false

    property string displayedArtFilePath: {
        if (!root.artDownloaded) return ""
        if (root.artUrl.startsWith("file://")) return root.artUrl
        return Qt.resolvedUrl(artFilePath)
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false
            return
        }
        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true
            return
        }
        artDownloader.targetFile  = root.artUrl
        artDownloader.artFilePath = root.artFilePath
        root.artDownloaded = false
        artDownloader.running = true
    }

    readonly property bool shouldShow: root.alwaysVisible || !!root.activePlayer

    Process {
        id: artDownloader
        property string targetFile:  root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c",
            `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.artDownloaded = true }
    }

    Layout.fillHeight: true
    visible: root.shouldShow
    implicitWidth: !root.shouldShow ? 0 : (vertical
        ? Appearance.sizes.verticalBarWidth
        : (isMaterial
            ? materialRow.implicitWidth
            : Math.max(
                Config.getBarSetting(root.monitorName, ["media", "minWidth"], Config.options.bar.media.minWidth),
                Math.min(rowLayout.implicitWidth + 8, Config.getBarSetting(root.monitorName, ["media", "maxWidth"], Config.options.bar.media.maxWidth))
            )))
    implicitHeight: !root.shouldShow ? 0 : (vertical ? (isMaterial ? 32 : mediaCircProg.implicitHeight) : Appearance.sizes.barHeight)

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        hoverEnabled: !Config.getBarSetting(root.monitorName, ["tooltips", "clickToShow"], Config.options.bar.tooltips.clickToShow)
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton)      activePlayer?.togglePlaying()
            else if (event.button === Qt.BackButton)   activePlayer?.previous()
            else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) activePlayer?.next()
            else if (event.button === Qt.LeftButton)   GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
        }
    }

    // Vertical default
    Loader {
        id: mediaCircProg
        active: root.vertical && !root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: ClippedFilledCircularProgress {
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: root.activePlayer?.position / root.activePlayer?.length
            colPrimary: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: MonitorThemes.m3ColorForItem(root, "m3onSecondaryContainer", Appearance.m3colors.m3onSecondaryContainer)
                }
            }
        }
    }

    // Vertical Material
    Rectangle {
        visible: root.vertical && root.isMaterial
        anchors.centerIn: parent
        color: MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
        radius: Appearance.rounding.full
        implicitWidth: 32
        implicitHeight: 32

        MaterialSymbol {
            anchors.centerIn: parent
            fill: 1
            text: root.activePlayer?.isPlaying ? "pause" : "music_note"
            iconSize: Appearance.font.pixelSize.normal
            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
        }
    }

    // Horizontal default
    Loader {
        id: rowLayout
        active: !root.vertical && !root.isMaterial
        visible: active
        anchors.fill: parent
        sourceComponent: RowLayout {
            spacing: 4
            ClippedFilledCircularProgress {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 3
                implicitSize: 20
                lineWidth: Appearance.rounding.unsharpen
                value: root.activePlayer?.position / root.activePlayer?.length
                colPrimary: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                enableAnimation: false
                Item {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: MonitorThemes.m3ColorForItem(root, "m3onSecondaryContainer", Appearance.m3colors.m3onSecondaryContainer)
                    }
                }
            }
            StyledText {
                visible: Config.getBarSetting(root.monitorName, ["verbose"], Config.options.bar.verbose)
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.rightMargin: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                text: Config.getBarSetting(root.monitorName, ["media", "onlyTitle"], Config.options.bar.media.onlyTitle) ? root.cleanedTitle : `${root.cleanedTitle}${root.activePlayer?.trackArtist ? ' • ' + root.activePlayer.trackArtist : ''}`
            }
        }
    }

    // Horizontal Material
    Loader {
        id: materialRow
        active: !root.vertical && root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: innerRow
            anchors.centerIn: parent
            spacing: 6

            // No platyer
            Loader {
                active: !root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Avatar
                    Rectangle {
                        id: avatarRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: avatarRect.width
                                height: avatarRect.height
                                radius: avatarRect.radius
                            }
                        }

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: Config.options.profile.avatarPath !== ""
                                ? "file://" + Config.options.profile.avatarPicture
                                : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                            sourceSize.width: avatarRect.width * 2
                            sourceSize.height: avatarRect.height * 2
                            fillMode: Image.PreserveAspectCrop
                            onStatusChanged: {
                                if (status === Image.Error)
                                    visible = false
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "account_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                            visible: avatarImage.status === Image.Error || avatarImage.status === Image.Null
                        }
                    }

                    ColumnLayout {
                        spacing: -3
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2

                        StyledText {
                            text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                        }

                        StyledText {
                            id: distroLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.rightMargin: 8
                            Layout.maximumWidth: 120
                            text: SystemInfo.distroName
                        }
                    }
                }
            }

            // Player
            Loader {
                active: root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Art
                    Rectangle {
                        id: artRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

                        StyledImage {
                            anchors.fill: parent
                            source: root.displayedArtFilePath
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            antialiasing: true
                            sourceSize.width: artRect.width
                            sourceSize.height: artRect.height
                            visible: root.displayedArtFilePath !== ""
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            visible: root.displayedArtFilePath === ""
                        }
                    }

                    // Title + Artist
                    ColumnLayout {
                        spacing: -4
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2

                        StyledText {
                            id: artistText
                            text: root.trackArtist
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                            Behavior on text {
                                SequentialAnimation {
                                    NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                    PropertyAction { target: artistText; property: "text" }
                                    NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                        StyledText {
                            id: titleText
                            Layout.topMargin: (!root.activePlayer || root.trackArtist.length === 0) ? -13 : 0
                            text: StringUtils.cleanMusicTitle(root.trackTitle) || Translation.tr("No media")
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            elide: Text.ElideRight
                            opacity: 0.7
                            Layout.maximumWidth: 120
                            Behavior on text {
                                SequentialAnimation {
                                    NumberAnimation { target: titleText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                    PropertyAction { target: titleText; property: "text" }
                                    NumberAnimation { target: titleText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }

                    // Play/Pause
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 23
                        buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
                        colBackground: root.isPlaying ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)
                        colBackgroundHover: root.isPlaying ? MonitorThemes.shellColorForItem(root, "colPrimaryHover", Appearance.colors.colPrimaryHover) : MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
                        colRipple: root.isPlaying ? MonitorThemes.shellColorForItem(root, "colPrimaryActive", Appearance.colors.colPrimaryActive) : MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                        downAction: () => root.activePlayer?.togglePlaying()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.isPlaying ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: root.isPlaying ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                        }
                    }

                    // Next
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.leftMargin: -4
                        buttonRadius: 13
                        colBackground: "transparent"
                        colBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
                        colRipple: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                        downAction: () => root.activePlayer?.next()
                        altAction: () => root.activePlayer?.previous()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "skip_next"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                        }
                    }
                }
            }
        }
    }
}
