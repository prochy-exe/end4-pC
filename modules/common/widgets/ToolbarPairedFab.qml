pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.services

Item {
    id: root
    signal clicked(event: var)
    property alias iconText: fabWidget.iconText
    property alias baseSize: fabWidget.baseSize
    default property alias fabData: fabWidget.data
    property bool enableShadow: true

    implicitWidth: fabWidget.implicitWidth
    implicitHeight: fabWidget.implicitHeight

    StyledRectangularShadow {
        visible: root.enableShadow
        target: fabWidget
        radius: fabWidget.buttonRadius
    }

    FloatingActionButton {
        id: fabWidget
        onClicked: e => root.clicked(e)
        baseSize: 48
            colBackground: MonitorThemes.shellColorForItem(root, "colTertiaryContainer", Appearance.colors.colTertiaryContainer)
            colBackgroundHover: MonitorThemes.shellColorForItem(root, "colTertiaryContainerHover", Appearance.colors.colTertiaryContainerHover)
            colRipple: MonitorThemes.shellColorForItem(root, "colTertiaryContainerActive", Appearance.colors.colTertiaryContainerActive)
        colOnBackground: MonitorThemes.shellColorForItem(root, "colOnTertiaryContainer", Appearance.colors.colOnTertiaryContainer)
    }
}
