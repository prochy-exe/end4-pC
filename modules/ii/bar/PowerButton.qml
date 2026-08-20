import qs
import qs.services
import qs.modules.common

UtilButton {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    iconText: "power_settings_new"

    onClicked: {
        GlobalStates.sessionOpen = !GlobalStates.sessionOpen
    }
}
