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
    // Keep caller values on the wrapper until the child slider has finished
    // constructing. A direct alias receives `value` before a caller's
    // `from`/`to` assignments, so Qt clamps it against Slider's initial 0..1
    // range and can write that bad value back to config.
    property real value: 0
    property alias stopIndicatorValues: slider.stopIndicatorValues
    // 0 (the Slider default) keeps continuous dragging, matching every
    // existing caller; only set this to opt into discrete steps.
    property alias stepSize: slider.stepSize
    property alias pressed: slider.pressed
    property bool usePercentTooltip: true
    property real from: 0
    property real to: 1
    property real textWidth: 120
    property bool showLabel: true
    property bool sliderReady: false
    property bool syncingSlider: false

    function syncSlider() {
        if (!sliderReady)
            return;
        syncingSlider = true;
        slider.from = from;
        slider.to = to;
        slider.value = value;
        syncingSlider = false;
    }

    onValueChanged: syncSlider()
    onFromChanged: syncSlider()
    onToChanged: syncSlider()

    RowLayout {
        id: row
        visible: root.showLabel
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.preferredWidth: root.textWidth
            Layout.maximumWidth: root.textWidth
            elide: Text.ElideRight
            text: root.text
            color: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
            opacity: root.enabled ? 1 : 0.4
        }
    }
    StyledSlider {
        id: slider
        configuration: StyledSlider.Configuration.XS
        animateValue: false
        enabled: root.enabled
        usePercentTooltip: root.usePercentTooltip
        // Keep this range broad until the delayed bindings below take over.
        from: -1000000
        to: 1000000
        snapMode: Slider.SnapAlways

        onValueChanged: {
            if (root.sliderReady && !root.syncingSlider && root.value !== value)
                root.value = value;
        }
    }

    // Config values can finish loading after the settings component itself.
    // Start on the next event-loop turn, then only forward actual slider input
    // back to the wrapper; syncSlider() suppresses programmatic updates.
    Timer {
        interval: 1
        running: true
        repeat: false
        onTriggered: {
            root.sliderReady = true;
            root.syncSlider();
        }
    }
}
