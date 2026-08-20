import QtQuick
import QtQuick.Layouts

RowLayout {
    property bool uniform: false
    spacing: 4
    uniformCellSizes: uniform
    opacity: enabled ? 1 : 0.4
}
