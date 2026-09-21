import qs.services
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    property string monitorName: ""
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property bool mediaEnabled: Config.options.sidebar.media.enable
    property int currentTabIndex: 0
    property Item translatorPage: null
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...(root.mediaEnabled ? [{"icon": "music_note", "name": Translation.tr("Media")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : []),
        {"icon": "image_search", "name": Translation.tr("Reverse Search")}
    ]
    property int tabCount: swipeView.count

    function tabIndexForRequest(tabName) {
        const request = `${tabName ?? ""}`.trim().toLowerCase()
        if (request.length === 0)
            return -1

        let index = 0
        if (root.aiChatEnabled) {
            if (request === "intelligence" || request === "ai") return index
            index += 1
        }
        if (root.translatorEnabled) {
            if (request === "translator" || request === "translate") return index
            index += 1
        }
        if (root.mediaEnabled) {
            if (request === "media") return index
            index += 1
        }
        if (root.animeEnabled && !root.animeCloset) {
            if (request === "anime") return index
            index += 1
        }
        if (request === "reversesearch" || request === "reverse search" || request === "reverse-search") return index
        return -1
    }

    function applyRequestedTab() {
        const requested = GlobalStates.sidebarLeftRequestedTab
        if (!requested || requested.length === 0)
            return
        const index = root.tabIndexForRequest(requested)
        if (index < 0)
            return
        if (index >= swipeView.count)
            return
        root.currentTabIndex = index
        if (root.currentTabIndex === index)
            GlobalStates.sidebarLeftRequestedTab = ""
    }

    function switchToTranslatorTab() {
        const index = root.tabIndexForRequest("translator")
        if (index < 0 || index >= swipeView.count)
            return false
        root.currentTabIndex = index
        return root.currentTabIndex === index
    }

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    function translatorTabIndex() {
        return root.tabIndexForRequest("translator")
    }

    function translatorItem() {
        return root.translatorPage
    }

    function ensureTranslatorPage() {
        if (!root.translatorEnabled) {
            root.translatorPage = null
            return
        }
        if (!root.translatorPage)
            root.translatorPage = translator.createObject()
    }

    function forceTranslatorPrefill(text) {
        const payload = `${text ?? ""}`
        if (payload.trim().length === 0)
            return false
        const item = root.translatorItem()
        if (!(item && typeof item.applyPrefillText === "function"))
            return false
        item.applyPrefillText(payload)
        return true
    }

    Component.onCompleted: {
        root.ensureTranslatorPage()
        root.applyRequestedTab()
    }

    onTranslatorEnabledChanged: root.ensureTranslatorPage()

    Connections {
        target: GlobalStates
        function onSidebarLeftRequestedTabChanged() {
            root.applyRequestedTab()
            delayedRequestedTabApply.restart()
        }
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                root.applyRequestedTab()
                if (root.currentTabIndex === root.translatorTabIndex()) {
                    const item = root.translatorItem()
                    if (item && typeof item.focusInputField === "function")
                        item.focusInputField()
                }
                delayedRequestedTabApply.restart()
            } else {
                GlobalStates.sidebarLeftRequestedTab = ""
                GlobalStates.sidebarLeftTranslatorPrefill = ""
                GlobalStates.sidebarLeftTranslatorPrefillArmed = false
                GlobalStates.sidebarLeftTranslatorResetNonce = (GlobalStates.sidebarLeftTranslatorResetNonce ?? 0) + 1
                root.scopeRoot.pendingTranslatorPrefill = ""
                const item = root.translatorItem()
                if (item && typeof item.clearInputText === "function")
                    item.clearInputText()
            }
        }
    }

    Connections {
        target: swipeView
        function onCountChanged() {
            if (swipeView.count > 0 && root.currentTabIndex >= swipeView.count)
                root.currentTabIndex = swipeView.count - 1
            root.applyRequestedTab()
            delayedRequestedTabApply.restart()
        }
        function onCurrentIndexChanged() {
            if (swipeView.currentIndex !== root.translatorTabIndex())
                return
            const item = root.translatorItem()
            if (item && typeof item.focusInputField === "function")
                item.focusInputField()
        }
    }

    Timer {
        id: delayedRequestedTabApply
        interval: 120
        repeat: false
        onTriggered: root.applyRequestedTab()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: verticalTabBar.expanded ? -2 : 0

        VerticalTabBar {
            id: verticalTabBar
            visible: tabButtonList.length > 0
            Layout.fillWidth: true
            tabButtonList: root.tabButtonList
            currentIndex: root.currentTabIndex
            onCurrentIndexChanged: {
                if (root.currentTabIndex !== currentIndex)
                    root.currentTabIndex = currentIndex
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            topLeftRadius: 0
            bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: 0
            bottomRightRadius: Appearance.rounding.normal
            color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: root.currentTabIndex
                onCurrentIndexChanged: {
                    if (root.currentTabIndex !== currentIndex)
                        root.currentTabIndex = currentIndex
                }

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.translatorEnabled && root.translatorPage ? [root.translatorPage] : []),
                    ...(root.mediaEnabled ? [media.createObject()] : []),
                    ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
                    ...(root.animeEnabled ? [anime.createObject()] : []),
                    reverseSearch.createObject(),
                ]
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: media
            SidebarPlayerControl {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: reverseSearch
            ReverseSearch {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                }
            }
        }
    }
}
