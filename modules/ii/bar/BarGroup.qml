import qs.modules.common
import QtQuick
import qs.services
import QtQuick.Layouts

Item {
    id: root
    // Settable from outside - see BarContent.qml's monitorName for why relying
    // solely on QsWindow here left this permanently stuck at "".
    property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    readonly property string currentBorderless: Config.getBarSetting(root.monitorName, ["borderless"], Config.options.bar.borderless)
    readonly property int currentCornerStyle: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle)
    property bool paintMaterialPill: false
    property real padding: (root.isMaterial && !root.paintMaterialPill) ? 0 : 5
    property color bgColor: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)

    readonly property real fullRadius: height / 2
    readonly property real midRadius: root.currentCornerStyle === 2 ? Appearance.rounding.unsharpenmore + 2 : Appearance.rounding.unsharpenmore
    property real startRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === 0) return fullRadius;
        return midRadius;
    }
    property real endRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === totalCount - 1) return fullRadius;
        return midRadius;
    }

    implicitWidth: vertical && root.isMaterial ? Appearance.sizes.baseVerticalBarWidth - 6 : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    default property alias items: gridLayout.children

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: (root.isMaterial && !root.paintMaterialPill)
            ? "transparent"
            : (root.isMaterial && root.paintMaterialPill)
                ? root.bgColor
                : (root.currentBorderless === "transparent"
                    ? "transparent"
                    : root.currentCornerStyle === 2
                        ? MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
                        : MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1))

        topLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (root.currentBorderless === "separated" ? root.fullRadius : root.startRadius)
        bottomLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (root.currentBorderless === "separated" ? root.fullRadius : root.vertical ? root.endRadius : root.startRadius)
        topRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (root.currentBorderless === "separated" ? root.fullRadius : root.vertical ? root.startRadius : root.endRadius)
        bottomRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (root.currentBorderless === "separated" ? root.fullRadius : root.endRadius)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
    }
}