import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSubsection {
    id: priorityRoot
    title: Translation.tr("Player priority")
    tooltip: Translation.tr("Drag to reorder. Media keys, the bar's media widget and the Super+M menu order follow this list - the highest-ranked player that's currently open wins control. Turn on \"Prefer the playing player\" below to have actual playback state break that tie instead.")

    // Known-ranked entries (in stored order, live or not) first, then any
    // newly-seen live player nobody has ranked yet, appended at the end.
    // Reactive: reads Config.options.media.priorityOrder and
    // MprisController.players, so it recomputes whenever either changes.
    property var rows: priorityRoot.combinedRows()

    function combinedRows() {
        const order = Config.options.media.priorityOrder ?? []
        const live = MprisController.players
        let liveById = ({})
        for (const p of live) liveById[MprisController.playerIdentifier(p)] = p

        let seen = ({})
        let result = []
        for (const id of order) {
            if (seen[id] || !id) continue
            seen[id] = true
            const p = liveById[id]
            result.push({ id: id, label: p ? (p.identity || id) : id, live: !!p })
        }
        for (const p of live) {
            const id = MprisController.playerIdentifier(p)
            if (seen[id] || !id) continue
            seen[id] = true
            result.push({ id: id, label: p.identity || id, live: true })
        }
        return result
    }

    function persist(newRows) {
        Config.options.media.priorityOrder = newRows.map(r => r.id)
    }

    function removeRow(index) {
        let list = priorityRoot.rows.slice()
        list.splice(index, 1)
        priorityRoot.persist(list)
    }

    StyledText {
        Layout.fillWidth: true
        visible: priorityRoot.rows.length === 0
        text: Translation.tr("No controllable media players detected right now.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: rowColumn.implicitHeight

        Column {
            id: rowColumn
            width: parent.width
            spacing: 4

            Repeater {
                id: rowRepeater
                model: priorityRoot.rows

                delegate: Rectangle {
                    id: rowDelegate
                    required property var modelData
                    required property int index
                    width: rowColumn.width
                    height: 36
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    opacity: rowDelegate.modelData.live ? (dragHandler.active ? 0.6 : 1) : 0.5
                    z: dragHandler.active ? 10 : 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        MaterialSymbol {
                            text: "drag_indicator"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.preferredWidth: 20
                            text: `${rowDelegate.index + 1}.`
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: rowDelegate.modelData.label
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: !rowDelegate.modelData.live
                            text: Translation.tr("not running")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        RippleButton {
                            visible: !rowDelegate.modelData.live
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            implicitWidth: 24
                            implicitHeight: 24
                            onClicked: priorityRoot.removeRow(rowDelegate.index)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    DragHandler {
                        id: dragHandler
                        target: null

                        function findNewIndex(dragY) {
                            let newIndex = rowDelegate.index
                            let minDist = Infinity
                            for (let i = 0; i < rowRepeater.count; i++) {
                                if (i === rowDelegate.index) continue
                                const child = rowRepeater.itemAt(i)
                                if (!child) continue
                                const childCenterY = child.mapToItem(null, 0, child.height / 2).y
                                const dist = Math.abs(dragY - childCenterY)
                                if (dist < minDist) {
                                    minDist = dist
                                    newIndex = i
                                }
                            }
                            return newIndex
                        }

                        onActiveChanged: {
                            if (!active) {
                                dropIndicator.visible = false
                                const dragY = dragHandler.centroid.scenePosition.y
                                const newIndex = findNewIndex(dragY)
                                if (newIndex !== rowDelegate.index) {
                                    let list = priorityRoot.rows.slice()
                                    const item = list.splice(rowDelegate.index, 1)[0]
                                    list.splice(newIndex, 0, item)
                                    priorityRoot.persist(list)
                                }
                            }
                        }

                        onCentroidChanged: {
                            if (!active) return
                            const dragY = dragHandler.centroid.scenePosition.y
                            const newIndex = findNewIndex(dragY)
                            if (newIndex !== rowDelegate.index) {
                                const refChild = rowRepeater.itemAt(newIndex)
                                if (refChild) {
                                    const refLocal = refChild.mapToItem(rowColumn, 0, 0)
                                    dropIndicator.y = newIndex < rowDelegate.index
                                        ? refLocal.y - 5
                                        : refLocal.y + refChild.height + 1
                                    dropIndicator.visible = true
                                }
                            } else {
                                dropIndicator.visible = false
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: dropIndicator
            visible: false
            width: rowColumn.width
            height: 3
            radius: 2
            color: Appearance.colors.colPrimary

            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    ConfigSwitch {
        Layout.topMargin: 4
        buttonIcon: "play_circle"
        text: Translation.tr("Prefer the playing player")
        checked: Config.options.media.priorityPreferActive
        onCheckedChanged: Config.options.media.priorityPreferActive = checked
    }
}
