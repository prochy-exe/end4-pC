pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.widgets.mediaElements
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
    required property QtObject blendedColors
    required property string displayedArtFilePath
    required property real radius
    // null = always show everything (sidebar player, unchanged). Otherwise,
    // a list of enabled element ids - same original layout/positions either
    // way, pieces are just toggled on/off (Settings > Services > Media),
    // never reordered.
    property var controlElements: null
    readonly property bool showProgressBar: root.controlElements === null || root.controlElements.includes("progressBar")
    readonly property bool showSkipButtons: root.controlElements === null || root.controlElements.includes("skipButtons")
    readonly property bool showPlayPause: root.controlElements === null || root.controlElements.includes("playPauseButton")
    readonly property bool showLyricsToggle: root.controlElements === null || root.controlElements.includes("lyricsToggle")
    // Off by default even when controlElements is null (legacy/sidebar) - the
    // volume row didn't exist before this was added, so nothing should show
    // it without being asked to.
    readonly property bool showVolumeBar: root.controlElements !== null && root.controlElements.includes("volumeBar")
    // 1.0 = unchanged (menu/sidebar). Scales margins/spacing/title+artist
    // font size down proportionally - for a small card (e.g. the ticker)
    // that doesn't have room for full-size text.
    property real contentScale: 1.0
    // false = unchanged (menu/sidebar): title/artist anchor to the top, all
    // leftover vertical space goes below them before the controls row. true
    // (the ticker, where controls are always empty) adds a matching spacer
    // above too, so the text is vertically centered instead of top-heavy.
    property bool centerContent: false
    signal toggleLyrics()

    // Appearance.rounding.verysmall (and the mask's extra +6) were tuned
    // against the menu/sidebar's art square, which is always this size
    // (mediaControlsHeight minus the elevation margin and this row's own
    // margins on both sides). The ticker's art square is much smaller, so
    // reusing those same absolute pixel values there made the corner
    // radius a much bigger fraction of the square - it read as circular
    // instead of rounded. Scale both by how much smaller the actual
    // square is instead of applying them at face value.
    readonly property real referenceArtSize: Appearance.sizes.mediaControlsHeight - 2 * Appearance.sizes.elevationMargin - 2 * 13

    component TrackChangeButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        property var iconName
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 13 * root.contentScale
        spacing: 15 * root.contentScale

        Rectangle {
            id: artBackground
            Layout.fillHeight: true
            implicitWidth: height
            // centerContent is only true for the ticker - reuse it instead of
            // adding a dedicated prop just for this.
            Layout.topMargin: root.centerContent ? -4 : 0
            // Without this, the margin snaps to 0 the instant centerContent
            // flips (on click), while the card's own implicitWidth/Height are
            // still mid-animation (see MediaControls.qml) - the still-small
            // card would show the "expanded" layout for that ~180ms, reading
            // as a jump. Match that animation so both move together.
            Behavior on Layout.topMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            radius: Appearance.rounding.verysmall * (artBackground.height / root.referenceArtSize)
            color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artBackground.width
                    height: artBackground.height
                    radius: artBackground.radius + 6 * (artBackground.height / root.referenceArtSize)
                }
            }

            StyledImage {
                id: mediaArt
                // anchors.fill alone, not also an explicit width/height tied
                // to a truncating `int` copy of parent.height - the two sizing
                // mechanisms could disagree on a fractional height (e.g. the
                // ticker's ~29.9px row) and which anchor edge won determined
                // whether the image sat flush or left a stray gap on one side.
                anchors.fill: parent
                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                sourceSize.width: artBackground.width
                sourceSize.height: artBackground.height
            }
        }

        ColumnLayout {
            // centerContent: natural size (title+artist only, nothing else
            // visible) + Qt's own AlignVCenter - deterministic centering,
            // instead of fillHeight relying on two separate spacers to
            // split leftover space exactly evenly (they didn't).
            Layout.fillHeight: !root.centerContent
            Layout.alignment: root.centerContent ? Qt.AlignVCenter : Qt.AlignTop
            spacing: 2 * root.contentScale

            StyledText {
                id: trackTitle
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large * root.contentScale
                color: root.blendedColors.colOnLayer0
                elide: Text.ElideRight
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            StyledText {
                id: trackArtist
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller * root.contentScale
                color: root.blendedColors.colSubtext
                elide: Text.ElideRight
                text: root.player?.trackArtist
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            Item { Layout.fillHeight: true }

            Item {
                Layout.fillWidth: true
                // With nothing left to show (the ticker's compact state),
                // this must be fully out of the layout, not just visually
                // empty - otherwise it still reserves an implicit minimum
                // height that eats into the *bottom* spacer specifically
                // (there's nothing between them), throwing off centering.
                visible: root.showProgressBar || root.showSkipButtons || root.showPlayPause || root.showLyricsToggle
                implicitHeight: (trackTime.visible ? trackTime.implicitHeight : 0) + sliderRow.implicitHeight

                StyledText {
                    id: trackTime
                    visible: root.showProgressBar
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    anchors.left: parent.left
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                    font.features: { "tnum": 1 }
                    text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                }

                RowLayout {
                    id: sliderRow
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }

                    TrackChangeButton {
                        iconName: "skip_previous"
                        visible: root.showSkipButtons
                        downAction: () => root.player?.previous()
                    }

                    Item {
                        id: progressBarContainer
                        visible: root.showProgressBar
                        Layout.fillWidth: true
                        implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                        Loader {
                            id: sliderLoader
                            anchors.fill: parent
                            active: root.player?.canSeek ?? false
                            sourceComponent: StyledSlider {
                                configuration: StyledSlider.Configuration.Wavy
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                handleColor: root.blendedColors.colPrimary
                                value: root.player?.position / root.player?.length
                                onMoved: root.player.position = value * root.player.length
                            }
                        }

                        Loader {
                            id: progressBarLoader
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                            }
                            active: !(root.player?.canSeek ?? false)
                            sourceComponent: StyledProgressBar {
                                wavy: root.player?.isPlaying
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                value: root.player?.position / root.player?.length
                            }
                        }
                    }

                    TrackChangeButton {
                        iconName: "skip_next"
                        visible: root.showSkipButtons
                        downAction: () => root.player?.next()
                    }

                    TrackChangeButton {
                        iconName: "lyrics"
                        visible: !GlobalStates.sidebarRightOpen && root.showLyricsToggle
                        downAction: () => root.toggleLyrics()
                    }
                }

                RippleButton {
                    id: playPauseButton
                    visible: root.showPlayPause
                    anchors.right: parent.right
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    property real size: 44
                    implicitWidth: size
                    implicitHeight: size
                    downAction: () => root.player.togglePlaying()

                    buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
                    colBackground: root.player?.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.player?.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.player?.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive

                    contentItem: MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.huge
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.player?.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                        text: root.player?.isPlaying ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }

            MediaVolumeBarElement {
                Layout.fillWidth: true
                Layout.topMargin: 6
                // Combines the toggle with "this player doesn't implement
                // MPRIS volume" (the element hides itself for that by
                // default too, but only that condition when unset here).
                visible: root.showVolumeBar && (root.player?.volumeSupported ?? false)
                player: root.player
                blendedColors: root.blendedColors
            }
        }
    }
}