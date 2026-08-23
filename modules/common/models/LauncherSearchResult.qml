import QtQuick
import Quickshell

QtObject {
    enum IconType { Material, Text, System, None }
    enum FontType { Normal, Monospace }

    // General stuff
    property string type: ""
    property var fontType: LauncherSearchResult.FontType.Normal
    property string name: ""
    property string rawValue: ""
    property string iconName: ""
    property var iconType: LauncherSearchResult.IconType.None
    property string verb: ""
    property bool blurImage: false
    property var execute: () => {
        print("Not implemented");
    }
    property var actions: []
    // `var`, defaulting to undefined rather than `property bool ...: false` --
    // deliberately, not an oversight. SearchItem.qml reads this two different
    // ways: the main row falls back with `?? true` (dismiss by default), sub-
    // actions check `=== true` (don't dismiss by default). Both rely on it
    // being genuinely undefined for every result type that never sets it
    // (everything except Bitwarden's actions, which set it explicitly from
    // config). A concrete bool default here, either way, would silently
    // change one of those two behaviors for every other result type in the
    // launcher, not just fix the warning for Bitwarden.
    property var dismissOnExecute: undefined
    // Set on the Bitwarden "copy verification code" action specifically, so
    // SearchItem.qml knows to draw a countdown ring around that one action
    // button showing how much of the current 30s TOTP window is left.
    property bool showTotpCountdown: false

    // Stuff needed for DesktopEntry 
    property string id: ""
    property bool shown: true
    property string comment: ""
    property bool runInTerminal: false
    property string genericName: ""
    property list<string> keywords: []

    // Extra stuff to allow for more flexibility
    property string category: type
}
