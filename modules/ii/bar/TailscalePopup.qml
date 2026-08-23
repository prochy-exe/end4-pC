import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root
    keepOpenWhileHovered: true
    wantsKeyboardFocus: true

    readonly property var status: TailscaleService.status
    readonly property var prefs: status.prefs
    property string pickerFilter: ""

    function matchesQuery(n, q) {
        return n.hostname.toLowerCase().includes(q) ||
            n.country.toLowerCase().includes(q) ||
            n.city.toLowerCase().includes(q)
    }

    // Recommended is untouched by search - always the same fixed top picks,
    // search or no search. Only the list underneath gets filtered.
    readonly property var filteredRecommended: TailscaleService.recommendedNodes

    readonly property var filteredNodes: {
        const q = root.pickerFilter.trim().toLowerCase()
        // Whatever's already shown in Recommended above doesn't need to be
        // repeated in the list underneath.
        const recommendedValues = new Set(root.filteredRecommended.map(n => n.value))
        const base = q === "" ? TailscaleService.exitNodes
            : TailscaleService.exitNodes.filter(n => root.matchesQuery(n, q))
        return base.filter(n => !recommendedValues.has(n.value))
    }

    onShouldShowChanged: {
        if (shouldShow) TailscaleService.refreshExitNodes()
    }

    function nodeLabel(node) {
        if (!node) return Translation.tr("None")
        if (node.city) return `${node.city}, ${node.country}${node.id ? " (" + node.id + ")" : ""}`
        return node.hostname
    }

    // Whether modelData is the currently active exit node - computed live
    // against root.status.exit_node (which refreshes promptly after every
    // action) rather than the modelData.active field baked into the cached
    // exit-node list, since that list is intentionally NOT re-fetched right
    // after switching (see TailscaleService.setExitNode) to avoid collapsing
    // the picker mid-selection - so its "active" flags lag behind until the
    // next natural refresh.
    function isActive(node) {
        if (node.value === "") return root.status.exit_node === null
        return root.status.exit_node !== null && root.status.exit_node.value === node.value
    }

    component NodeRow: RippleButton {
        id: nodeRow
        required property var modelData
        readonly property bool isActive: root.isActive(modelData)
        width: ListView.view.width
        implicitHeight: 30
        colBackground: "transparent"
        enabled: modelData.online || modelData.value === ""
        onClicked: TailscaleService.setExitNode(modelData.value)
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol {
                visible: nodeRow.isActive
                text: "check"
                iconSize: Appearance.font.pixelSize.small
                color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            }
            Item { visible: !nodeRow.isActive; implicitWidth: 14 }
            MaterialSymbol {
                visible: modelData.value !== ""
                text: modelData.is_mullvad ? "shield_lock" : "person"
                iconSize: Appearance.font.pixelSize.small
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                opacity: 0.6
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                opacity: modelData.online || modelData.value === "" ? 1 : 0.4
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                text: modelData.value === "" ? Translation.tr("None")
                    : (modelData.city ? `${modelData.city}, ${modelData.country}${modelData.id ? " (" + modelData.id + ")" : ""}` : modelData.hostname)
            }
            StyledText {
                visible: (modelData.estimated_latency_ms ?? null) !== null
                text: `~${modelData.estimated_latency_ms}ms`
                font.pixelSize: Appearance.font.pixelSize.smallest
                opacity: 0.5
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
            }
            MaterialSymbol {
                visible: modelData.city_recommended
                text: "star"
                fill: 1
                iconSize: Appearance.font.pixelSize.small
                color: MonitorThemes.shellColorForItem(root, "colSecondary", Appearance.colors.colSecondary)
            }
            MaterialSymbol {
                visible: modelData.suggested
                text: "bolt"
                fill: 1
                iconSize: Appearance.font.pixelSize.small
                color: MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary)
            }
        }
    }

    ColumnLayout {
        implicitWidth: 260
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: TailscaleService.lastError !== "" ? TailscaleService.lastError
                    : (root.status.error ?? Translation.tr("Tailscale"))
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                opacity: (TailscaleService.lastError !== "" || root.status.error) ? 1 : 0.7
                elide: Text.ElideRight
            }

            StyledSwitch {
                checked: root.status.connected
                enabled: !TailscaleService.busy
                onClicked: TailscaleService.setEnabled(!root.status.connected)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.status.needs_login && root.status.auth_url
            wrapMode: Text.WordWrap
            text: Translation.tr("Sign-in required - click to open the login page")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["xdg-open", root.status.auth_url])
            }
        }

        GroupedList {
            Layout.fillWidth: true
            visible: root.status.connected
            bgcolor: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "dns"
                label: root.status.self.hostname || Translation.tr("This device")
                value: root.status.self.ips[0] ?? ""
                copyAction: root.status.self.ips[0] ? (() => Quickshell.clipboardText = root.status.self.ips[0]) : null
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "hub"
                label: Translation.tr("Peers online")
                value: `${root.status.peers.online} / ${root.status.peers.total}`
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialSymbol {
                    text: "output"
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    iconSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    text: Translation.tr("Exit node")
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    text: root.nodeLabel(root.status.exit_node)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.status.connected
            spacing: 2

            component PrefRow: ColumnLayout {
                id: prefRow
                required property string prefIcon
                required property string prefText
                required property string prefCaption
                required property bool prefChecked
                required property string prefFlag
                Layout.fillWidth: true
                spacing: -4

                ConfigSwitch {
                    buttonIcon: prefRow.prefIcon
                    text: prefRow.prefText
                    checked: prefRow.prefChecked
                    enabled: !TailscaleService.busy
                    onClicked: TailscaleService.setPref(prefRow.prefFlag, !checked)
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 34
                    Layout.bottomMargin: 4
                    text: prefRow.prefCaption
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    opacity: 0.5
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                }
            }

            PrefRow {
                prefIcon: "route"
                prefText: Translation.tr("Accept routes")
                prefCaption: Translation.tr("Use routes other tailnet devices advertise")
                prefChecked: root.prefs.accept_routes
                prefFlag: "accept-routes"
            }
            PrefRow {
                prefIcon: "dns"
                prefText: Translation.tr("Accept DNS")
                prefCaption: Translation.tr("Use your tailnet's DNS settings")
                prefChecked: root.prefs.accept_dns
                prefFlag: "accept-dns"
            }
            PrefRow {
                prefIcon: "shield"
                prefText: Translation.tr("Shields up")
                prefCaption: Translation.tr("Block incoming connections from peers")
                prefChecked: root.prefs.shields_up
                prefFlag: "shields-up"
            }
            PrefRow {
                prefIcon: "terminal"
                prefText: Translation.tr("Tailscale SSH")
                prefCaption: Translation.tr("Let tailnet devices SSH into this one")
                prefChecked: root.prefs.ssh
                prefFlag: "ssh"
            }
            PrefRow {
                prefIcon: "lan"
                prefText: Translation.tr("Allow LAN via exit node")
                prefCaption: Translation.tr("Keep local network access while exiting")
                prefChecked: root.prefs.exit_node_allow_lan_access
                prefFlag: "exit-node-allow-lan-access"
            }
            PrefRow {
                prefIcon: "podcasts"
                prefText: Translation.tr("Advertise as exit node")
                prefCaption: Translation.tr("Let others route their traffic through you")
                prefChecked: root.prefs.advertise_exit_node
                prefFlag: "advertise-exit-node"
            }
        }

        // Exit node chooser - always expanded, fixed size, so hovering the
        // bar icon (or scrolling the list, or the recommended-count varying)
        // never resizes the popup window itself.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.status.connected
            spacing: 4

            StyledText {
                Layout.leftMargin: 3
                text: Translation.tr("Choose exit node")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                opacity: 0.7
            }

            NodeRow {
                Layout.fillWidth: true
                modelData: ({ value: "", hostname: "", id: "", country: "", city: "", online: true, active: root.status.exit_node === null, is_mullvad: false, suggested: false, city_recommended: false, estimated_latency_ms: null })
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                spacing: 10

                RowLayout {
                    spacing: 2
                    MaterialSymbol { text: "shield_lock"; iconSize: Appearance.font.pixelSize.smallest; opacity: 0.6; color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant) }
                    StyledText { text: Translation.tr("Mullvad"); font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.6; color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant) }
                }
                RowLayout {
                    spacing: 2
                    MaterialSymbol { text: "star"; fill: 1; iconSize: Appearance.font.pixelSize.smallest; color: MonitorThemes.shellColorForItem(root, "colSecondary", Appearance.colors.colSecondary) }
                    StyledText { text: Translation.tr("recommended for city"); font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.6; color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant) }
                }
                RowLayout {
                    spacing: 2
                    MaterialSymbol { text: "bolt"; fill: 1; iconSize: Appearance.font.pixelSize.smallest; color: MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary) }
                    StyledText { text: Translation.tr("fastest for you"); font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.6; color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant) }
                }
            }

            // Fixed-size viewport: whatever's inside (spinner or the actual
            // recommended/search/list stack) is clipped to exactly this
            // size, so this is the only thing that determines the popup's
            // height from here down - it never grows or shrinks with content.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 320
                clip: true

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: TailscaleService.exitNodesLoading
                    width: parent.width
                    spacing: 6

                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Loading exit nodes...")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        opacity: 0.6
                        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.bottomMargin: 8
                    visible: !TailscaleService.exitNodesLoading
                    spacing: 4

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.filteredRecommended.length > 0
                        spacing: 0

                        StyledText {
                            Layout.leftMargin: 3
                            text: Translation.tr("Recommended (estimated, nearest-region latency)")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            opacity: 0.6
                            color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                        }

                        Repeater {
                            model: root.filteredRecommended
                            delegate: NodeRow {
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        visible: root.filteredRecommended.length > 0
                        implicitHeight: 1
                        color: MonitorThemes.shellColorForItem(root, "colOutline", Appearance.colors.colOutline)
                        opacity: 0.3
                    }

                    MaterialTextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Search country, city, hostname...")
                        text: root.pickerFilter
                        onTextChanged: root.pickerFilter = text
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 0

                        model: root.filteredNodes

                        delegate: NodeRow {}
                    }
                }
            }
        }
    }
}
