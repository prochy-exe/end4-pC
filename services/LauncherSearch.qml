pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Singleton {
    id: root

    property string query: ""

    // Kicks off the actual Bitwarden vault search/status-refresh whenever the
    // query changes. Deliberately outside the `results` computed property
    // below (which just reads Bitwarden's state to build result rows) --
    // see the comment in that property's Bitwarden branch for why.
    onQueryChanged: {
        if (root.query.startsWith(Config.options.search.prefix.bitwarden)) {
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.bitwarden).trim()
            Bitwarden.triggerSearch(searchString)
        }
    }

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.bitwarden, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }
    
    Process {
        id: keywordHarvester
        property var pendingPages: []
        property string currentPageName: ""
        
        function startHarvesting() {
            root.settingsKeywordsCache = {};
            root.settingsKeywordsList = {};
            pendingPages = root.settingsIndex.slice();
            next();
        }

        function next() {
            if (pendingPages.length === 0) {
                return;
            }
            
            let currentPage = pendingPages.shift();
            let fullPath = FileUtils.trimFileProtocol(
                Quickshell.shellPath("modules/ii/settings/pages/" + currentPage.path)
            )

            let rawCommand = "grep -oP \"title:\\s*Translation.tr\\(['\\\"].*?['\\\"]\\)\" " + fullPath + " | sed -E \"s/title:\\s*Translation.tr\\(['\\\"](.*)['\\\"]\\)/\\1/g\"";
            
            command = ["bash", "-c", rawCommand];
            
            keywordHarvester.currentPageName = currentPage.page;
            running = true;
        }

        onExited: (exitCode, exitStatus) => {
            keywordHarvester.next();
        }

        stdout: SplitParser {
            onRead: data => {
                let cache = root.settingsKeywordsCache;
                cache[keywordHarvester.currentPageName] = (cache[keywordHarvester.currentPageName] || "") + " " + data;
                root.settingsKeywordsCache = cache;

                let list = root.settingsKeywordsList;
                let pageTitles = list[keywordHarvester.currentPageName] || [];
                pageTitles.push(data);
                list[keywordHarvester.currentPageName] = pageTitles;
                root.settingsKeywordsList = list;
            }
        }
    }

    Component.onCompleted: {
        keywordHarvester.startHarvesting();
    }


    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    property var settingsKeywordsCache: ({})
    property var settingsKeywordsList: ({})

    property var settingsIndex: [
        { page: "General",    path: "GeneralConfig.qml" },
        { page: "Appearance", path: "AppearanceConfig.qml" },
        { page: "Wallpaper effects", path: "WallpaperEffectsConfig.qml" },
        { page: "Interface",  path: "InterfaceConfig.qml" },
        { page: "Services",   path: "ServicesConfig.qml" },
        { page: "Windows",    path: "WindowsConfig.qml" },
        { page: "Keybinds",   path: "KeybindsConfig.qml" },
        { page: "About",      path: "About.qml" },
        { page: "Quick",      path: "QuickConfig.qml" },
    ]

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                const monitorName = Hyprland.focusedMonitor?.name ?? "";
                Quickshell.execDetached([
                    Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh"),
                    "--monitor", monitorName
                ]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch("global quickshell:wallpaperSelectorToggle")
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
        {
            action: "ocrcopy",
            execute: () => {
                const text = `${GlobalStates.lastOcrText ?? ""}`.trim();
                if (text.length === 0) {
                    Quickshell.execDetached(["notify-send", "OCR", Translation.tr("No cached OCR text yet"), "-a", "Shell"]);
                    return;
                }
                Quickshell.clipboardText = text;
                Quickshell.execDetached(["notify-send", "OCR", Translation.tr("Copied cached OCR text"), "-a", "Shell"]);
            }
        },
        {
            action: "ocrtranslate",
            execute: () => {
                const text = `${GlobalStates.lastOcrText ?? ""}`.trim();
                if (text.length === 0) {
                    Quickshell.execDetached(["notify-send", "OCR", Translation.tr("No cached OCR text yet"), "-a", "Shell"]);
                    return;
                }
                Quickshell.execDetached([
                    "qs",
                    "-p",
                    Quickshell.shellPath(""),
                    "ipc",
                    "call",
                    "sidebarLeft",
                    "openTranslator",
                    text,
                ]);
            }
        },
        {
            action: "ocrreplace",
            execute: () => {
                const text = `${GlobalStates.lastOcrText ?? ""}`.trim();
                if (text.length === 0) {
                    Quickshell.execDetached(["notify-send", "OCR", Translation.tr("No cached OCR text yet"), "-a", "Shell"]);
                    return;
                }
                Cliphist.pasteText(text);
            }
        },
        {
            action: "unsplash",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("Usage: /unsplash YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "unsplash"], args.trim());
                Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "wallhaven",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("Usage: /wallhaven YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "wallhaven"], args.trim());
                Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "pexels",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("Usage: /pexels YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "pexels"], args.trim());
                Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const _pinRev = Cliphist.pinRevision
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            return Cliphist.fuzzyQuery(searchString).map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                const pinned = Cliphist.isPinned(entry);
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.paste(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: pinned ? Translation.tr("Unpin") : Translation.tr("Pin"),
                            iconName: pinned ? "keep_off" : "push_pin",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.togglePinEntry(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.bitwarden)) {
            // Bitwarden
            // Kicking off the actual search happens in onQueryChanged below,
            // not here -- calling a mutating function as a side effect of
            // evaluating this computed property is what caused Qt's binding
            // loop detector to fire against `results` once Bitwarden's own
            // state started changing fast enough (bw serve) to sometimes
            // still be settling while this was being (re-)evaluated.
            // Deliberately NOT reading Bitwarden.totpSecondsRemaining here (it
            // used to be, alongside _bwRev) -- that ticks every second via
            // totpCountdownTimer, and reading it here made this whole
            // property depend on it, so the *entire* results array got
            // rebuilt from scratch every second whenever a TOTP-bearing item
            // was showing. Every list view bound to `results` then saw a
            // brand new array each second and reset its selection back to
            // index 0 -- which is what looked like a highlighted row
            // "pulsing"/refusing to stay selected while navigating. The
            // per-second countdown label is instead a live Qt.binding() on
            // just that one action below, so only its own text updates.
            const _bwRev = Bitwarden.revision
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.bitwarden).trim();

            const buildBitwardenItemResult = (item, recent) => {
                const itemId = item.id ?? ""
                const itemName = item.name ?? "(unnamed)"
                const username = item.username ?? ""
                const hasTotp = item.hasTotp ?? false
                return resultComp.createObject(null, {
                    name: itemName,
                    iconName: "password",
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: recent ? Translation.tr("Recent - copy password") : Translation.tr("Copy password"),
                    type: Translation.tr("Bitwarden"),
                    comment: username,
                    dismissOnExecute: Config.options.search.bitwardenDismissOnInteract,
                    execute: () => {
                        Bitwarden.setLastInteracted(item)
                        Bitwarden.copyPassword(itemId)
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy username"),
                            iconName: "person",
                            iconType: LauncherSearchResult.IconType.Material,
                            dismissOnExecute: Config.options.search.bitwardenDismissOnInteract,
                            execute: () => {
                                Bitwarden.setLastInteracted(item)
                                Bitwarden.copyUsername(username)
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy password"),
                            iconName: "key",
                            iconType: LauncherSearchResult.IconType.Material,
                            dismissOnExecute: Config.options.search.bitwardenDismissOnInteract,
                            execute: () => {
                                Bitwarden.setLastInteracted(item)
                                Bitwarden.copyPassword(itemId)
                            }
                        }),
                        hasTotp ? resultComp.createObject(null, {
                            // Qt.binding(): keeps just this label's text live
                            // (re-evaluated every time totpSecondsRemaining
                            // ticks) without that dependency leaking out to
                            // the `results` property itself -- see the note
                            // above on _bwRev/_bwTotpRemaining for why that
                            // distinction matters.
                            name: Qt.binding(() => (Config.options.search.bitwardenTotp?.showCountdown ?? true)
                                ? Translation.tr("Copy verification code (%1s left)").arg(Bitwarden.totpSecondsRemaining)
                                : Translation.tr("Copy verification code")),
                            iconName: "shield_lock",
                            iconType: LauncherSearchResult.IconType.Material,
                            dismissOnExecute: Config.options.search.bitwardenDismissOnInteract,
                            showTotpCountdown: true,
                            execute: () => {
                                Bitwarden.setLastInteracted(item)
                                Bitwarden.copyTotp(itemId, hasTotp)
                            }
                        }) : null
                    ].filter(Boolean)
                })
            }

            // "checking" and "searching with nothing fetched yet" are shown as a
            // loading indicator in the search bar itself (see SearchBar.qml),
            // not as a fake, unselectable result row - a single no-op entry was
            // still keyboard-focusable/highlighted like a real result, which
            // looked broken when nothing was actually there yet.
            if (Bitwarden.status === "checking") {
                return []
            }

            if (Bitwarden.status === "searching" && Bitwarden.items.length === 0) {
                return []
            }

            // "locked" specifically is now handled by the search field itself
            // turning into an inline password prompt (see SearchBar.qml) --
            // showing this guidance row too, on top of that, was a highlighted,
            // auto-selected "fake" result duplicating the same message right
            // underneath the actual password field.
            if (Bitwarden.status === "locked") {
                return []
            }

            if (["unauthenticated", "missing-cli", "timeout", "error"].includes(Bitwarden.status)) {
                const guidance = (() => {
                    switch (Bitwarden.status) {
                    case "unauthenticated":
                        return Translation.tr("Login required")
                    case "missing-cli":
                        return Translation.tr("Bitwarden CLI missing")
                    case "timeout":
                        return Translation.tr("Command timed out")
                    default:
                        return Translation.tr("Bitwarden error")
                    }
                })()

                return [resultComp.createObject(null, {
                    name: Bitwarden.lastError.length > 0 ? Bitwarden.lastError : Translation.tr("Bitwarden search failed"),
                    iconName: "error",
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: guidance,
                    type: Translation.tr("Bitwarden"),
                    shown: true,
                    execute: () => {
                        Bitwarden.showHelpForCurrentState()
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Unlock now"),
                            iconName: "lock_open",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                GlobalStates.overviewOpen = false
                                Qt.callLater(() => Bitwarden.unlockFromMenu(true))
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Show help"),
                            iconName: "help",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Bitwarden.showHelpForCurrentState()
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy bw unlock"),
                            iconName: "key",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Bitwarden.copyUnlockCommand()
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy bw login"),
                            iconName: "login",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Bitwarden.copyLoginCommand()
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Clear saved session"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Bitwarden.clearSessionToken()
                            }
                        })
                    ]
                })]
            }

            if (searchString.length === 0) {
                // The "type to search" hint lives in the search bar's placeholder
                // text (see SearchBar.qml) rather than as a fake result row - a
                // no-op row was still keyboard-focusable/highlighted like a real
                // result, which looked broken when there was nothing to select.
                const rows = []
                const recent = Bitwarden.lastInteractedItem ?? ({})
                if ((recent.id ?? "").length > 0) {
                    rows.push(buildBitwardenItemResult(recent, true))
                }
                return rows
            }

            return Bitwarden.items.map(item => buildBitwardenItemResult(item, false)).filter(Boolean)
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Emojis
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Paste"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Cliphist.pasteText(entry.match(/^\s*(\S+)/)?.[1] ?? "");
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.keybinds ?? "<")) {
            // Keybinds
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.keybinds ?? "<");
            const flatBinds = (function flatten(node) {
                let result = [...(node.keybinds ?? [])];
                for (const child of (node.children ?? [])) {
                    result = result.concat(flatten(child));
                }
                return result;
            })(HyprlandKeybinds.keybinds);

            return flatBinds.filter(bind => {
                if (!bind.comment) return false;
                if (searchString.length === 0) return true;
                return bind.comment.toLowerCase().includes(searchString.toLowerCase())
                    || bind.key.toLowerCase().includes(searchString.toLowerCase());
            }).map(bind => {
                const modsStr = bind.mods.join(" + ");
                const keyStr  = modsStr.length > 0 ? `${modsStr} + ${bind.key}` : bind.key;
                return resultComp.createObject(null, {
                    name: bind.comment,
                    iconName: "keyboard",
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: keyStr,
                    type: Translation.tr("Keybind"),
                    comment: keyStr,
                    execute: () => {
                        Quickshell.clipboardText = keyStr;
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.symbols)) {
            // Material Symbols
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.symbols);
            return MaterialSymbolsSearch.fuzzyQuery(searchString).map(entry => {
                const tabIdx = entry.indexOf("\t");
                const symName = tabIdx >= 0 ? entry.slice(0, tabIdx) : entry;
                const symTags = tabIdx >= 0 ? entry.slice(tabIdx + 1) : "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: symName,
                    iconName: symName,
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: Translation.tr("Paste"),
                    type: Translation.tr("Symbol"),
                    comment: symTags,
                    execute: () => {
                        Cliphist.pasteText(symName);
                    }
                });
            }).filter(Boolean);
        }

        ////////////////// Init ///////////////////
        nonAppResultsTimer.restart();
        const mathResultObject = resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        entry.execute();
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        ////////////////// Settings search //////////////////
        const settingsQuery = root.query.toLowerCase().trim();

        const settingsResults = root.settingsIndex.reduce((acc, page) => {
            const dynamicKeywords = (root.settingsKeywordsCache[page.page] || "").toLowerCase();
            const query = root.query.toLowerCase().trim();
            if (query === "") return acc;

            if (page.page.toLowerCase().includes(query) || dynamicKeywords.includes(query)) {
                acc.push(resultComp.createObject(null, {
                    name: page.page,
                    comment: dynamicKeywords.includes(query) ? "Section: " + query : "Settings for " + page.page,
                    verb: Translation.tr("Go"),
                    type: Translation.tr("Settings"),
                    iconName: "settings",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        GlobalStates.settingsOpen = true;
                        Qt.callLater(() => {
                            GlobalStates.settingsPage = page.page + ":" + query;
                        });
                        root.query = "";
                    }
                }));
            }
            return acc;
        }, []);
        const commandResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["bash", "-c", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Qt.openUrlExternally(url);
            }
        });
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                return resultComp.createObject(null, {
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        action.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);
        ////////////// Settings ////////////////
        result = result.concat(settingsResults);
        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }
        
        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
