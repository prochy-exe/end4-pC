import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: 8
    property string monitorName: ""
    property int currentPage: 0
    property bool showingProfile: false
    property bool isMinimal: Config.options.settings.style === "minimal"

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return
            
            let parts = GlobalStates.settingsPage.split(":");
            let pageName = parts[0];
            let searchTerm = parts.length > 1 ? parts[1] : "";

            const idx = root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase());
            
            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;
                
                if (searchTerm !== "") {
                    let loader = pagesRepeater.itemAt(idx);
                    if (loader && loader.item && typeof loader.item.goTo === "function") {
                        loader.item.goTo(searchTerm);
                    } else if (loader) {
                        loader.onLoaded.connect(function() {
                            if (loader.item && typeof loader.item.goTo === "function") {
                                loader.item.goTo(searchTerm);
                            }
                        });
                    }
                }
            }
            GlobalStates.settingsPage = "";
        }
    }

    onCurrentPageChanged: {
        const pageName = root.pages[currentPage]?.name ?? ""
        if (pageName === Translation.tr("About")) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            Updates.refresh()
        }
    }
    
    property var pages: {
        let list = [
            { name: Translation.tr("Quick"),      icon: "instant_mix",    component: Qt.resolvedUrl("pages/QuickConfig.qml") },
            { name: Translation.tr("General"),    icon: "browse",         component: Qt.resolvedUrl("pages/GeneralConfig.qml") },
            { name: Translation.tr("Bar"),        icon: "toast",          iconRotation: 180, component: Qt.resolvedUrl("pages/BarConfig.qml") },
            { name: Translation.tr("Desktop"),    icon: "texture",        component: Qt.resolvedUrl("pages/BackgroundConfig.qml") },
            { name: Translation.tr("Interface"),  icon: "bottom_app_bar", component: Qt.resolvedUrl("pages/InterfaceConfig.qml") },
            { name: Translation.tr("Services"),   icon: "settings",       component: Qt.resolvedUrl("pages/ServicesConfig.qml") },
        ]
        if (WM.compositor === "hyprland") {
                    list.push({ name: Translation.tr("Hyprland"), icon: "select_window_2", component: Qt.resolvedUrl("pages/HyprlandConfig.qml") })
                }
        if (WM.compositor === "niri") {
                    list.push({ name: Translation.tr("Niri"), icon: "select_window_2", component: Qt.resolvedUrl("pages/NiriConfig.qml") })
                }
        list.push({ name: Translation.tr("About"), icon: "info", component: Qt.resolvedUrl("pages/About.qml") })
        return list
    }

    Component.onCompleted: {
        Config.readWriteDelay = 0
    }

    property string searchQuery: ""
    readonly property bool showingSearchResults: root.searchQuery.trim().length > 0

    // One entry per page that matches, each carrying the individual matching
    // setting titles within it (not just a page-level/category match), so the
    // results page can show and jump to specific settings.
    readonly property var searchResults: {
        const q = root.searchQuery.trim().toLowerCase()
        if (q.length === 0) return []
        const matches = []
        for (let idx = 0; idx < root.pages.length; idx++) {
            const p = root.pages[idx]
            const indexEntry = LauncherSearch.settingsIndex.find(e => p.component.toString().endsWith(e.path))
            const englishName = indexEntry ? indexEntry.page : p.name
            const titles = indexEntry ? (LauncherSearch.settingsKeywordsList[indexEntry.page] || []) : []

            const pageNameMatches = (p.name + " " + englishName).toLowerCase().includes(q)
            const matchingTitles = titles.filter(t => t.toLowerCase().includes(q))

            if (pageNameMatches || matchingTitles.length > 0) {
                matches.push({ idx: idx, name: p.name, icon: p.icon, settings: matchingTitles })
            }
        }
        return matches
    }

    function goToSearchResult(idx, term) {
        root.currentPage = idx
        root.showingProfile = false

        if (term) {
            let loader = pagesRepeater.itemAt(idx)
            if (loader && loader.item && typeof loader.item.goTo === "function") {
                loader.item.goTo(term)
            } else if (loader) {
                loader.onLoaded.connect(function() {
                    if (loader.item && typeof loader.item.goTo === "function")
                        loader.item.goTo(term)
                })
            }
        }

        root.searchQuery = ""
        searchField.text = ""
    }

    // --- Live control previews for search results ---
    //
    // Rather than reparenting the real, on-screen setting control out of its
    // page (which would leave a hole there whenever search is open), each
    // matching leaf control gets a disposable copy: we instantiate a fresh,
    // hidden, throwaway instance of the whole page component, pluck out just
    // the matching control(s) from it, and destroy the rest of that instance.
    // The real settings pages (pagesRepeater) are never touched.
    //
    // Everything here is wrapped defensively (try/catch, status checks, depth
    // and count caps) so a page that fails to load or has an unusual control
    // shape just falls back to a plain click-to-navigate row instead of
    // breaking the results list.
    property var currentControlPreviews: []

    Item {
        id: controlPreviewPool
        visible: false
        width: 0
        height: 0
    }

    Timer {
        id: controlPreviewScanTimer
        interval: 400
        repeat: false
        onTriggered: root.rescanControlPreviews()
    }

    onSearchQueryChanged: {
        if (root.searchQuery.trim().length === 0) {
            root.clearControlPreviews()
        } else {
            controlPreviewScanTimer.restart()
        }
    }

    function clearControlPreviews() {
        controlPreviewScanTimer.stop()
        for (let i = 0; i < root.currentControlPreviews.length; i++) {
            try {
                if (root.currentControlPreviews[i].node)
                    root.currentControlPreviews[i].node.destroy()
            } catch (e) {}
        }
        root.currentControlPreviews = []
    }

    // Recognizes an actual settings control (has a label plus a live value),
    // as opposed to decorative labels/containers that merely have a `.text`.
    function isLeafSettingControl(node) {
        if (!node) return false
        try {
            const hasLabel = typeof node.text === "string" && node.text.length > 0
            const hasValue = (typeof node.checked === "boolean")
                || (typeof node.value === "number")
                || (typeof node.value === "string")
            return hasLabel && hasValue
        } catch (e) {
            return false
        }
    }

    function findLeafConfigControls(node, query, results, depth) {
        if (!node || depth > 12 || results.length >= 20) return
        const children = node.children || []
        for (let i = 0; i < children.length; i++) {
            const child = children[i]
            if (root.isLeafSettingControl(child) && child.text.toLowerCase().includes(query)) {
                results.push({ label: child.text, node: child })
                if (results.length >= 20) return
            }
            root.findLeafConfigControls(child, query, results, depth + 1)
            if (results.length >= 20) return
        }
    }

    function scanPageForControls(pageIdx, query, previews) {
        const page = root.pages[pageIdx]
        const component = Qt.createComponent(page.component)
        if (component.status === Component.Error) {
            console.warn("[Settings search] Failed to load page for preview:", component.errorString())
            return
        }
        // Local pages resolve synchronously; skip rather than block if not.
        if (component.status !== Component.Ready) return

        const pageInstance = component.createObject(controlPreviewPool)
        if (!pageInstance) return

        const found = []
        try {
            root.findLeafConfigControls(pageInstance, query, found, 0)
        } catch (e) {
            console.warn("[Settings search] Failed scanning page for preview:", e)
        }

        for (let i = 0; i < found.length; i++) {
            found[i].node.parent = controlPreviewPool
            previews.push({ idx: pageIdx, label: found[i].label, node: found[i].node })
        }

        pageInstance.destroy()
    }

    function rescanControlPreviews() {
        root.clearControlPreviews()
        const q = root.searchQuery.trim().toLowerCase()
        if (q.length === 0) return

        const previews = []
        for (let i = 0; i < root.searchResults.length; i++) {
            try {
                root.scanPageForControls(root.searchResults[i].idx, q, previews)
            } catch (e) {
                console.warn("[Settings search] Failed to build preview for page:", e)
            }
        }
        root.currentControlPreviews = previews
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }
        spacing: contentPadding

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            Rectangle {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 0
                implicitWidth: navRail.expanded ? 195 : fab.baseSize
                color: isMinimal ? "transparent" : Appearance.colors.colLayer1
                radius: Appearance.rounding.normal

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 20 }
                    spacing: 10
                    expanded: root.width > 900

                    Item {
                        id: profileRowContainer
                        visible: true
                        Layout.fillWidth: false
                        Layout.margins: isMinimal ? 0 : 5
                        Layout.topMargin: 15
                        Layout.bottomMargin: isMinimal ? -30 : 0
                        implicitHeight: profileRow.implicitHeight
                        implicitWidth: profileRow.implicitWidth

                        RowLayout {
                            id: profileRow
                            anchors.fill: parent
                            spacing: 10

                            Rectangle {
                                id: avatarRect
                                width: 48
                                height: 48
                                radius: width / 2
                                color: Appearance.colors.colPrimaryContainer

                                Image {
                                    id: avatarImage
                                    anchors.fill: parent
                                    source: Config.options.profile.avatarPath !== ""
                                        ? "file://" + Config.options.profile.avatarPicture
                                        : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                                    sourceSize.width: avatarImage.width * 2
                                    sourceSize.height: avatarImage.height * 2
                                    fillMode: Image.PreserveAspectCrop
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: avatarRect.width
                                            height: avatarRect.height
                                            radius: avatarRect.radius
                                        }
                                    }
                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            visible = false
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "account_circle"
                                    iconSize: 32
                                    color: Appearance.colors.colOnPrimaryContainer
                                    visible: avatarImage.status === Image.Error
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                visible: !isMinimal

                                StyledText {
                                    text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 100
                                }

                                StyledText {
                                    id: distroText
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 100

                                    text: {
                                        const d = Config.options.profile.descriptionText
                                        if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                        return SystemInfo.distroName
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showingProfile = !root.showingProfile
                        }
                    }

                    Rectangle {
                        id: searchRow
                        visible: navRail.expanded
                        Layout.fillWidth: true
                        Layout.margins: 5
                        Layout.topMargin: 2
                        implicitHeight: 44
                        radius: Appearance.rounding.full
                        color: MonitorThemes.colorForItem(root, "surface_container_high", Appearance.m3colors.m3surfaceContainerHigh)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: "search"
                                iconSize: Appearance.font.pixelSize.large
                                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }

                            MaterialTextField {
                                id: searchField
                                Layout.fillWidth: true
                                background: Item {}
                                implicitHeight: 44
                                font.pixelSize: Appearance.font.pixelSize.small
                                placeholderText: Translation.tr("Search settings...")
                                onTextChanged: root.searchQuery = text
                                Keys.onEscapePressed: {
                                    text = ""
                                    focus = false
                                }
                                Keys.onReturnPressed: {
                                    if (root.searchResults.length > 0) {
                                        const first = root.searchResults[0]
                                        root.goToSearchResult(first.idx, first.settings.length > 0 ? first.settings[0] : "")
                                    }
                                }
                            }

                            MaterialSymbol {
                                visible: searchField.text.length > 0
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)

                                TapHandler {
                                    onTapped: {
                                        searchField.text = ""
                                        root.searchQuery = ""
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: isMinimal ? 50 : 160
                        Layout.topMargin: isMinimal ? 30 : -5
                        Layout.bottomMargin: isMinimal ? -30 : 0
                        height: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.2; color: Appearance.colors.colOutline }
                            GradientStop { position: 0.8; color: Appearance.colors.colOutline }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.15
                    }

                    FloatingActionButton {
                        id: fab
                        visible: !isMinimal
                        Layout.bottomMargin: -25
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }
                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: fab.justCopied = false
                        }
                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    NavigationRailTabArray {
                        currentIndex: root.currentPage
                        expanded: navRail.expanded
                        colToggled: root.showingProfile ? "transparent" : Appearance.colors.colSecondaryContainer
                        Repeater {
                            model: root.pages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                toggled: root.currentPage === index && !root.showingProfile
                                onPressed: {
                                    root.currentPage = index
                                    root.showingProfile = false
                                }
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation || 0
                                buttonText: modelData.name
                                showToggledHighlight: false
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut

                Item {
                    anchors.fill: parent

                    Repeater {
                        id: pagesRepeater
                        model: root.pages
                        Loader {
                            id: pageLoader
                            required property var modelData
                            required property var index
                            source: modelData.component

                            active: Config.ready && (root.currentPage === index || item !== null)

                            anchors.fill: parent

                            property bool isActive: root.currentPage === index && !root.showingProfile && !root.showingSearchResults
                            opacity: isActive ? 1 : 0
                            enabled: isActive
                            visible: isActive
                            anchors.topMargin: isActive ? 0 : 12

                            onLoaded: {
                                if (root.currentPage === index) {
                                    GlobalStates.currentPageInstance = item;
                                }
                            }

                            onIsActiveChanged: {
                                if (isActive && item) {
                                    GlobalStates.currentPageInstance = item;
                                } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                    GlobalStates.currentPageInstance = null;
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Loader {
                        id: profileLoader
                        active: Config.ready && (root.showingProfile || item !== null)
                        anchors.fill: parent
                        source: Qt.resolvedUrl("pages/Profile.qml")

                        property bool isActive: root.showingProfile && !root.showingSearchResults
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    Item {
                        id: searchResultsView
                        anchors.fill: parent
                        visible: root.showingSearchResults
                        opacity: root.showingSearchResults ? 1 : 0
                        enabled: root.showingSearchResults

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: contentPadding * 2
                            spacing: 16

                            StyledText {
                                text: Translation.tr("Search results for \"%1\"").arg(root.searchQuery.trim())
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Medium
                                color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }

                            StyledText {
                                visible: root.searchResults.length === 0
                                text: Translation.tr("No settings found")
                                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                            }

                            StyledFlickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: resultsColumn.implicitHeight

                                ColumnLayout {
                                    id: resultsColumn
                                    width: parent.width
                                    spacing: 18

                                    Repeater {
                                        model: root.searchResults
                                        delegate: ColumnLayout {
                                            id: resultGroup
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 2

                                            RippleButton {
                                                Layout.fillWidth: true
                                                implicitHeight: 44
                                                buttonRadius: Appearance.rounding.normal
                                                onClicked: root.goToSearchResult(resultGroup.modelData.idx, "")

                                                contentItem: RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 12
                                                    MaterialSymbol {
                                                        text: resultGroup.modelData.icon
                                                        iconSize: Appearance.font.pixelSize.large
                                                        color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: resultGroup.modelData.name
                                                        font.pixelSize: Appearance.font.pixelSize.normal
                                                        font.weight: Font.Medium
                                                        color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                                                    }
                                                }
                                            }

                                            Repeater {
                                                model: resultGroup.modelData.settings
                                                delegate: RippleButton {
                                                    id: settingButton
                                                    required property string modelData
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 40
                                                    implicitHeight: 36
                                                    buttonRadius: Appearance.rounding.small
                                                    onClicked: root.goToSearchResult(resultGroup.modelData.idx, settingButton.modelData)

                                                    contentItem: RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 8
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: settingButton.modelData
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                                                        }
                                                    }
                                                }
                                            }

                                            // Live, interactive copies of the individual controls that
                                            // matched within this page (see the preview functions above).
                                            // Each is a disposable clone: destroyed when this delegate
                                            // goes away (query changes), never the real control.
                                            Repeater {
                                                model: root.currentControlPreviews.filter(c => c.idx === resultGroup.modelData.idx)
                                                delegate: Rectangle {
                                                    id: previewRow
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 40
                                                    Layout.topMargin: 2
                                                    Layout.bottomMargin: 2
                                                    implicitHeight: previewHost.implicitHeight + 12
                                                    radius: Appearance.rounding.small
                                                    color: MonitorThemes.colorForItem(root, "surface_container_high", Appearance.m3colors.m3surfaceContainerHigh)

                                                    Item {
                                                        id: previewHost
                                                        anchors {
                                                            left: parent.left
                                                            right: parent.right
                                                            verticalCenter: parent.verticalCenter
                                                            margins: 6
                                                        }
                                                        implicitHeight: previewRow.modelData.node ? previewRow.modelData.node.implicitHeight : 0

                                                        Component.onCompleted: {
                                                            const node = previewRow.modelData.node
                                                            if (!node) return
                                                            try {
                                                                node.parent = previewHost
                                                                node.anchors.left = previewHost.left
                                                                node.anchors.right = previewHost.right
                                                            } catch (e) {
                                                                console.warn("[Settings search] Failed to place preview control:", e)
                                                            }
                                                        }
                                                        Component.onDestruction: {
                                                            const node = previewRow.modelData.node
                                                            if (!node) return
                                                            try { node.destroy() } catch (e) {}
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
