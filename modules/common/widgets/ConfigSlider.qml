import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    // 0 (the Slider default) keeps continuous dragging, matching every
    // existing caller; only set this to opt into discrete steps.
    property alias stepSize: slider.stepSize
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120
    property bool showLabel: true

    RowLayout {
        id: row
        visible: root.showLabel
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.preferredWidth: root.textWidth
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    StyledSlider {
        id: slider
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        // from/to MUST be applied before value. QML assigns in declaration
        // order, so with value first it was set against Slider's default 0..1
        // range: Qt clamps it and remembers `position`, then recomputes value
        // from that position once the real range arrives, landing on a
        // different (often extreme) number. The call site's onValueChanged then
        // wrote that back to config and broke the binding - which is how simply
        // opening a settings page could rewrite the values on it.
        from: root.from
        to: root.to
        value: root.value
        // No-op when stepSize is 0 (continuous), so this is safe to set
        // unconditionally for every caller.
        snapMode: Slider.SnapAlways
    }
}