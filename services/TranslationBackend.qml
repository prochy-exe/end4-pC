pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // Kept for compatibility with older QML references.
    property string backend: "trans"

    function translateCommand(text, sourceLanguage, targetLanguage) {
        const source = StringUtils.shellSingleQuoteEscape(`${sourceLanguage ?? "auto"}`)
        const target = StringUtils.shellSingleQuoteEscape(`${targetLanguage ?? "en"}`)
        const payload = StringUtils.shellSingleQuoteEscape(`${text ?? ""}`)

        switch (root.backend) {
        case "trans":
        default:
            return ["bash", "-c", `trans -brief -no-bidi -source '${source}' -target '${target}' '${payload}'`]
        }
    }

    function listLanguagesCommand() {
        switch (root.backend) {
        case "trans":
        default:
            return ["trans", "-list-languages", "-no-bidi"]
        }
    }
}
