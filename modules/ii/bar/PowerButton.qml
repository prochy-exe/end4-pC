import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property real buttonPadding: 5

    implicitWidth: 32
    implicitHeight: implicitWidth

    buttonRadius: Appearance.rounding.full
    colBackground: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : "transparent"
    colBackgroundHover: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimaryHover", Appearance.colors.colPrimaryHover) : MonitorThemes.shellColorForItem(root, "colLayer1Hover", Appearance.colors.colLayer1Hover)
    colRipple: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimaryActive", Appearance.colors.colPrimaryActive) : MonitorThemes.shellColorForItem(root, "colLayer1Active", Appearance.colors.colLayer1Active)

    onPressed: {
        GlobalStates.sessionOpen = !GlobalStates.sessionOpen
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.isMaterial
        text: "power_settings_new"
        iconSize: Appearance.font.pixelSize.larger
        color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
    }

    MaterialShapeWrappedMaterialSymbol {
        anchors.centerIn: parent
        visible: root.isMaterial
        text: "power_settings_new"
        iconSize: Appearance.font.pixelSize.normal
        color: MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
        colSymbol: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
        wrappedShape: MaterialShape.Shape.Cookie12Sided
        padding: 2
    }
}