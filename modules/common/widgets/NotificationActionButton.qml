import qs.modules.common
import qs.services
import QtQuick
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string buttonText
    property string urgency

    implicitHeight: 34
    leftPadding: 15
    rightPadding: 15
    buttonRadius: Appearance.rounding.small
    colBackground: (urgency == NotificationUrgency.Critical) ? MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer) : MonitorThemes.shellColorForItem(parent, "colLayer4", Appearance.colors.colLayer4)
    colBackgroundHover: (urgency == NotificationUrgency.Critical) ? MonitorThemes.shellColorForItem(parent, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover) : Appearance.colors.colLayer4Hover
    colRipple: (urgency == NotificationUrgency.Critical) ? MonitorThemes.shellColorForItem(parent, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive) : Appearance.colors.colLayer4Active

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        text: buttonText
        color: (urgency == NotificationUrgency.Critical) ? MonitorThemes.colorForItem(parent, "on_surface_variant", Appearance.m3colors.m3onSurfaceVariant) : MonitorThemes.colorForItem(parent, "on_surface", Appearance.m3colors.m3onSurface)
    }
}
