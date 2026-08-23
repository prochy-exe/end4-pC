pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    spacing: 6
    property bool animateWidth: false
    property alias searchInput: searchInput
    property string searchingText

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Bitwarden, Clipboard, Emojis, Symbols, Math, ShellCommand, WebSearch, Keybinds, DefaultSearch }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.bitwarden)) return SearchBar.SearchPrefixType.Bitwarden;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.symbols)) return SearchBar.SearchPrefixType.Symbols;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.keybinds ?? "<")) return SearchBar.SearchPrefixType.Keybinds;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }
    
    MaterialShapeWrappedMaterialSymbol {
        id: searchIcon
        Layout.alignment: Qt.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge
        shape: switch(root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return MaterialShape.Shape.Pill;
            case SearchBar.SearchPrefixType.App: return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Bitwarden: return MaterialShape.Shape.Oval;
            case SearchBar.SearchPrefixType.Clipboard: return MaterialShape.Shape.Gem;
            case SearchBar.SearchPrefixType.Emojis: return MaterialShape.Shape.Sunny;
            case SearchBar.SearchPrefixType.Symbols: return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Math: return MaterialShape.Shape.PuffyDiamond;
            case SearchBar.SearchPrefixType.ShellCommand: return MaterialShape.Shape.PixelCircle;
            case SearchBar.SearchPrefixType.WebSearch: return MaterialShape.Shape.SoftBurst;
            case SearchBar.SearchPrefixType.Keybinds: return MaterialShape.Shape.Cookie4Sided;
            default: return MaterialShape.Shape.Cookie7Sided;
        }
        text: switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return "settings_suggest";
            case SearchBar.SearchPrefixType.App: return "apps";
            case SearchBar.SearchPrefixType.Bitwarden: return "password";
            case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
            case SearchBar.SearchPrefixType.Symbols: return "interests";
            case SearchBar.SearchPrefixType.Math: return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
            case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
            case SearchBar.SearchPrefixType.DefaultSearch: return "search";
            case SearchBar.SearchPrefixType.Keybinds: return "keyboard_command_key";
            default: return "search";
        }
    }
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 40
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small

        readonly property bool bitwardenLocked: root.searchPrefixType === SearchBar.SearchPrefixType.Bitwarden
            && Bitwarden.status === "locked"

        // Auto-switches into a masked password field the moment the vault
        // shows up locked, so the field the user is already typing/focused in
        // becomes the unlock prompt instead of requiring a separate dialog.
        echoMode: bitwardenLocked ? TextInput.Password : TextInput.Normal
        placeholderText: {
            if (bitwardenLocked) return Translation.tr("Vault locked - enter password")
            if (root.searchPrefixType === SearchBar.SearchPrefixType.Bitwarden) return Translation.tr("Type to search Bitwarden vault")
            return Translation.tr("Search, calculate or run")
        }
        implicitWidth: root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth

        // The "!" mode-switch prefix only needs to live in the text while we
        // don't yet know the lock state. Once locked, leaving it in would get
        // echoMode-masked along with the password itself -- rendered as an
        // extra bullet glued to the front of whatever's typed, with the
        // placeholder overlay below misaligned next to it (its position was
        // computed from the prefix's normal glyph width, not its masked
        // width). Clearing it is safe: root.searchPrefixType is driven by
        // searchingText, which onTextChanged (below) already freezes the
        // moment we're locked, so it doesn't fall back to a different mode
        // just because the field is now empty.
        onBitwardenLockedChanged: {
            if (bitwardenLocked) {
                searchInput.text = ""
            } else if (searchInput.text === "") {
                // bitwardenLocked can only have just been true (searchPrefixType
                // was already Bitwarden, and onTextChanged above blocks anything
                // from changing that classification while locked), so reaching
                // false here means we were locked and just stopped being locked
                // -- almost always a successful unlock. Restore the mode prefix
                // so the field is a ready, empty Bitwarden search box instead of
                // a plain unmarked one that falls through to the global search
                // on the next keystroke. Without this, only fully closing and
                // reopening via Super+B (which re-sets the prefix itself) got
                // back into Bitwarden search mode.
                searchInput.text = Config.options.search.prefix.bitwarden
            }
        }

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: root.animateWidth
            NumberAnimation {
                duration: 300
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        // Don't feed a partially-typed master password into the live search
        // (would spam pointless "!<password chars so far>" vault lookups).
        // Also catches a gap onBitwardenLockedChanged (above) has on its own:
        // that only fires on an actual locked-state *transition*. Reopening
        // Bitwarden mode while it was already locked from before (no new
        // transition, since it's still just as locked as when it was closed)
        // sets the field's text back to the "!" prefix via setSearchingText()
        // without ever re-triggering that handler -- leaving the leading "!"
        // in place for whatever gets typed next, silently turning a correct
        // password into "!<password>" and making a real password look wrong.
        onTextChanged: {
            if (bitwardenLocked) {
                if (text === Config.options.search.prefix.bitwarden)
                    searchInput.text = ""
                return
            }
            LauncherSearch.query = text
        }

        onAccepted: {
            if (bitwardenLocked) {
                const password = searchInput.text
                searchInput.text = ""
                Bitwarden.unlockWithPassword(password)
                return
            }
            if (appResults.count > 0) {
                // Get the first visible delegate and trigger its click
                let firstItem = appResults.itemAtIndex(0);
                if (firstItem && firstItem.clicked) {
                    firstItem.clicked();
                }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                if (LauncherSearch.results.length === 0) return;
                const tabbedText = LauncherSearch.results[0].name;
                LauncherSearch.query = tabbedText;
                searchInput.text = tabbedText;
                event.accepted = true;
            }
        }

        // Entering Bitwarden mode sets the field's text to the prefix itself
        // (e.g. "!"), so it's never actually empty and the native
        // placeholderText above never gets a chance to show. This overlay hint
        // fills that in once nothing's typed past the prefix. Only needed for
        // the not-yet-locked case now -- once locked, searchInput.text gets
        // cleared to "" (see onBitwardenLockedChanged above), so the native
        // placeholderText shows correctly on its own without this overlay.
        TextMetrics {
            id: bitwardenPrefixMetrics
            font: searchInput.font
            text: Config.options.search.prefix.bitwarden
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: searchInput.leftPadding + bitwardenPrefixMetrics.width
            visible: root.searchPrefixType === SearchBar.SearchPrefixType.Bitwarden
                && !searchInput.bitwardenLocked
                && searchInput.text === Config.options.search.prefix.bitwarden
            text: Translation.tr("Type to search Bitwarden vault")
            color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
        }
    }

    IconToolbarButton {
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.searchPrefixType === SearchBar.SearchPrefixType.Clipboard
        onClicked: {
            Cliphist.wipe();
        }
        text: "mop"
        StyledToolTip {
            text: Translation.tr("Wipe clipboard (keep pinned)")
        }
    }

    MaterialLoadingIndicator {
        id: bitwardenLoadingIndicator
        Layout.alignment: Qt.AlignVCenter
        implicitSize: 22
        visible: root.searchPrefixType === SearchBar.SearchPrefixType.Bitwarden
            && (Bitwarden.status === "checking" || (Bitwarden.status === "searching" && Bitwarden.items.length === 0))
        loading: visible

        property bool hovered: hoverHandler.hovered
        HoverHandler {
            id: hoverHandler
        }

        StyledToolTip {
            text: Bitwarden.status === "checking"
                ? Translation.tr("Checking Bitwarden auth...")
                : Translation.tr("Loading Bitwarden vault...")
        }
    }

    IconToolbarButton {
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.searchPrefixType !== SearchBar.SearchPrefixType.Bitwarden
        onClicked: {
            GlobalStates.overviewOpen = false;
            Quickshell.execDetached(["bash", "-c", "pid=$(pgrep -x qs | head -n1) && exec qs ipc --pid \"$pid\" call region search"]);
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Google Lens")
        }
    }

    IconToolbarButton {
        id: songRecButton
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 4
        visible: root.searchPrefixType !== SearchBar.SearchPrefixType.Bitwarden
        toggled: SongRec.running
        onClicked: SongRec.toggleRunning()
        text: "music_cast"

        StyledToolTip {
            text: Translation.tr("Recognize music")
        }

        colText: toggled ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        background: MaterialShape {
            RotationAnimation on rotation {
                running: songRecButton.toggled
                duration: 12000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                from: 0
                to: 360
            }
            shape: {
                if (songRecButton.down) {
                    return songRecButton.toggled ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square
                } else {
                    return songRecButton.toggled ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                }
            }
            color: {
                if (songRecButton.toggled) {
                    return songRecButton.hovered ? MonitorThemes.shellColorForItem(root, "colPrimaryHover", Appearance.colors.colPrimaryHover) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                } else {
                    return songRecButton.hovered ? MonitorThemes.shellColorForItem(root, "colSurfaceContainerHigh", Appearance.colors.colSurfaceContainerHigh) : ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colSurfaceContainerHigh", Appearance.colors.colSurfaceContainerHigh))
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
