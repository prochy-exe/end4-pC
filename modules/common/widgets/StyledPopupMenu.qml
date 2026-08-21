import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common.widgets // Para las sombras y estilos
import qs.services

Item {
    id: root
    
    // Propiedades que recibe desde InterfaceConfig.qml (Bar settings)
    property alias model: repeater.model
    property var onItemSelected: (item) => {} 
    
    // Control de visibilidad
    property bool visible: false
    property string monitorName: ""

    LazyLoader {
        id: loader
        active: root.visible // Solo carga la ventana cuando visible es true

        component: PanelWindow {
            id: popupWindow
            readonly property string resolvedMonitorName: root.monitorName || screen?.name || ""
            
            // Configuración de Wayland
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:popup"
            
            color: "transparent"
            mask: true
            
            // Dimensiones basadas en el contenido
            implicitWidth: container.implicitWidth + 40
            implicitHeight: container.implicitHeight + 40

            // Si el usuario hace clic fuera o la ventana pierde foco, cerramos
            onActiveChanged: {
                if (!active) root.visible = false
            }

            // Sombras usando tus widgets existentes
            StyledRectangularShadow {
                target: container
            }

            Rectangle {
                id: container
                anchors.centerIn: parent
                implicitWidth: 200 
                implicitHeight: layout.implicitHeight + 16
                
                radius: Appearance.rounding.normal
                color: MonitorThemes.colorForItem(popupWindow, "surface_container", Appearance.m3colors.m3surfaceContainer)
                border.width: 1
                border.color: MonitorThemes.colorForItem(popupWindow, "outline_variant", Appearance.colors.colLayer0Border)

                ColumnLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Repeater {
                        id: repeater
                        delegate: MouseArea {
                            Layout.fillWidth: true
                            implicitHeight: 40 
                            hoverEnabled: true
                            id: itemArea

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: itemArea.containsMouse ? MonitorThemes.colorForItem(popupWindow, "surface_container_high", Appearance.colors.colLayer2Hover) : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.text || ""
                                font.family: Appearance.font.family.main
                                color: MonitorThemes.colorForItem(popupWindow, "on_surface", Appearance.m3colors.m3onSurface)
                            }

                            onClicked: {
                                root.visible = false
                                root.onItemSelected(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
