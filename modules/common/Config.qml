pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    function ensureProfileDisplayNameInitialized() {
        if (!root.ready) return
        if (root.options.profile.displayNameInitialized) return

        const envUser = (Quickshell.env("USER") ?? "").trim()
        if ((root.options.profile.displayName ?? "").trim().length === 0 && envUser.length > 0) {
            root.options.profile.displayName = envUser
        }
        root.options.profile.displayNameInitialized = true
    }

    onReadyChanged: {
        if (root.ready) {
            root.ensureProfileDisplayNameInitialized()
        }
    }

    function resolvePathValue(target, path, fallbackValue) {
        let current = target
        const keys = Array.isArray(path) ? path : path.split(".")
        for (let i = 0; i < keys.length; i++) {
            if (current === undefined || current === null || !(keys[i] in current)) {
                return fallbackValue
            }
            current = current[keys[i]]
        }
        return current
    }

    function getBarSetting(monitorName, path, fallbackValue) {
        const keys = Array.isArray(path) ? path : path.split(".")
        const entry = (root.options?.bar?.monitorSettings ?? []).find(item => item.name === monitorName)
        const overrideValue = root.resolvePathValue(entry?.values ?? {}, keys, undefined)
        if (overrideValue !== undefined) {
            return overrideValue
        }
        return root.resolvePathValue(root.options?.bar ?? {}, keys, fallbackValue)
    }

    function hasDistinctMonitorWallpapers(lock) {
        const background = root.options?.background
        const mode = lock ? background?.lockWallpaperMode : background?.wallpaperMode
        const entries = lock ? background?.lockMonitorWallpapers : background?.monitorWallpapers
        if (mode !== "perMonitor") return false
        return new Set((entries ?? []).map(entry => entry?.path).filter(path => path)).size > 1
    }

    function backgroundWidgetsShown(monitorName) {
        const screens = root.options?.background?.screenList ?? []
        return screens.length === 0 || screens.includes(monitorName)
    }

    function lockWidgetsShown(monitorName) {
        const screens = root.options?.lock?.screenList ?? []
        return screens.length === 0 || screens.includes(monitorName)
    }

    function getBackgroundWidgetSetting(monitorName, widgetName, fallbackValue) {
        const entry = (root.options?.background?.monitorWidgets ?? []).find(item => item.name === monitorName)
        const value = entry?.widgets?.[widgetName]
        return value === undefined ? fallbackValue : value
    }

    function setBackgroundWidgetSetting(monitorName, widgetName, value) {
        const list = (root.options.background.monitorWidgets ?? []).slice()
        const index = list.findIndex(item => item.name === monitorName)
        const widgets = {}
        const existingWidgets = index >= 0 ? (list[index].widgets ?? {}) : {}
        for (const key in existingWidgets) widgets[key] = existingWidgets[key]
        const entry = { name: monitorName, widgets: widgets }
        entry.widgets[widgetName] = value
        if (index >= 0) list[index] = entry; else list.push(entry)
        root.options.background.monitorWidgets = list
    }

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 1 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "spark-symbolic", // Not mandatory
                        "key_get_link": "https://openrouter.ai/settings/keys", // Not mandatory
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool useWallpaperColorForApps: true
                    property string accentMonitor: ""
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            // Control-plane settings for the two external hardware bridge
            // daemons (dx5ii-bridge, wamp-bridge) - both are standalone C
            // apps with their own WebSocket control API; this only holds
            // where to find/launch them and which port to talk to.
            property JsonObject audioBridges: JsonObject {
                property JsonObject dx5ii: JsonObject {
                    property string binaryPath: "/mnt/github/dx5ii-bridge/build/dx5iibridge"
                    property string wsBind: "127.0.0.1"
                    property int wsPort: 8765
                }
                property JsonObject wamp: JsonObject {
                    property string binaryPath: "/mnt/github/wamp-bridge/build/wamp-bridge"
                    property string wsBind: "127.0.0.1"
                    property int wsPort: 8790
                }
            }

            property JsonObject profile: JsonObject {
                property string avatarPath: ""
                property string avatarPicture: ""
                property string descriptionText: "::distro::"
                property string displayName: ""
                property bool displayNameInitialized: false
                property bool onlinePresets: false
                property bool showHostnameWithUsername: true

            }

            property JsonObject hyprland: JsonObject {
                property JsonObject animations: JsonObject {
                    property string animation: "normal"
                    property bool enable: true
                }
                property string primaryMonitor: ""
                property int primaryWorkspaceStart: 1
                property int primaryWorkspaceEnd: 1
                property JsonObject autostartApps: JsonObject {
                    property bool enable: false
                    property list<var> apps: []
                }
                property JsonObject decoration: JsonObject {
                    property int rounding: 22
                    property real activeOpacity: 1.0
                    property real inactiveOpacity: 0.9
                    property JsonObject blur: JsonObject {
                        property bool enabled: true
                        property int size: 1
                        property int passes: 3
                    }
                    property JsonObject shadow: JsonObject {
                        property bool enabled: true
                        property int range: 4
                    }
                }
                property JsonObject general: JsonObject {
                    property int borderSize: 1
                    property int gapsIn: 2
                    property int gapsOut: 5
                    property string layout: "dwindle"
                    // Window border colors. Disabled by default so the colors
                    // generated by matugen in hyprland/colors.lua keep applying.
                    property JsonObject borderColor: JsonObject {
                        property bool enable: false
                        // Palette roles, resolved by Appearance.getColorFromName()
                        property string activeRole: "layer0Border"
                        property string inactiveRole: "layer0Border"
                        property real activeOpacity: 0.47
                        property real inactiveOpacity: 0.2
                    }
                }
                property JsonObject idle: JsonObject {
                    property int lock: 300
                    property int screenOff: 600
                    property int suspend: 10800
                }
                property JsonObject input: JsonObject {
                    property string kbLayout: "us"
                    property bool showLayoutVariantInBar: true
                    property int appleFnMode: 2
                    property bool numlock: true
                    property int repeatDelay: 250
                    property int repeatRate: 35
                    property int followMouse: 1
                    property JsonObject touchpad: JsonObject {
                        property bool naturalScroll: false
                        property bool disableWhileTyping: true
                        property bool clickfingerBehavior: false
                        property real scrollFactor: 0.7
                    }
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "kcmshell6 kcm_networkmanagement"
                property string manageUser: "kcmshell6 kcm_users"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            property JsonObject settings: JsonObject {
                property string style: "default" // default - minimal
                property real borderSize: 1
                property string borderColor: "layer0Border"
                property list<string> collapsedSections: []
            }

            property JsonObject background: JsonObject {
                property string lockWall: ""
                property bool widgetsLocked: false
                property bool showGrid: true
                property bool showBlur: false
                property real blurRadius: 32
                property string splitRatio: "100" // 25 50 100
                property string splitSide: "left"
                property bool showSnapLines: true
                property JsonObject widgets: JsonObject {
                    property bool blurWidgets: false
                    property real blurRadius: 32
                    property bool shadow: true
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property real z: 0
                        property string style: "cookie"        // Options: "cookie", "digital"
                        property string color: ""
                        property string styleLocked: "cookie"  // Options: "cookie", "digital"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property int sides: 14
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject pixel: JsonObject {
                            property string orientation: "vertical"
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                            property bool followClock: false
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "1x3"
                        property bool expanded: false
                    }

                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "2x2"
                    }
                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "2x2"
                        property int clockCount: 4
                    }

                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject todo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject userCard: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string sizeMode: "1x2"
                    }

                    property JsonObject images: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                    }

                    property JsonObject reverseSearch: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                    }

                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 0
                        property real y: 0
                        property real z: -1000
                        property string style: "bars" // "bars", "mirror", "aurora", "ring", "dots"
                        property string colorSource: "theme" // "theme", "cover"
                        property real sensitivity: 1
                        property int height: 260 // mirror, aurora and dots
                        property int ringSize: 380
                    }

                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string path: ""
                        property string shape: "Cookie4Sided"
                        property real size: 200
                    }

                    property JsonObject sticker: JsonObject {
                        property bool enable: false
                        property list<var> items: [] // if someone sees this and wants to add more stickers, make a PR too lazy
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property string path: ""
                        property real size: 200
                        property real rotation: 0
                        property string outlineColor: "#ffffff" //dont work =(
                        property real outlineWidth: 8
                    }

                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property bool vertical: false
                    }

                    property JsonObject timers: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property real z: 0
                        property bool vertical: false
                    }

                    property JsonObject media: JsonObject {
                        property bool enable: false
                        property bool showOnLock: true
                        property bool showControls: true
                        property bool showLyrics: false
                        property bool showTitles: true
                        property string backgroundShape: "Cookie4Sided"
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 800
                        property real y: 500
                        property real z: 0
                        property string sizeMode: "1x3"
                    }

                    property JsonObject customText: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 300
                        property real z: 0
                        property string content: "Hello world"
                        property string fontFamily: "Caveat"
                        property int fontSize: 72
                        property string color: "" // "" = automatic, otherwise an Appearance color name
                        property string alignment: "center" // "left", "center", "right"
                        property bool shadow: true
                    }
                }
                property list<string> screenList: [] 
                property list<var> monitorWidgets: [] // [{ name, widgets: { clock: true, weather: false, ... } }]
                property string wallpaperPath: ""
                // "perMonitor" consults monitorWallpapers below; a monitor with
                // no entry there falls back to wallpaperPath so it's never blank.
                property string wallpaperMode: "shared" // "shared" | "perMonitor"
                property list<var> monitorWallpapers: [] // [{ name, path }]
                property string sharedWallpaperLayout: "independent" // "independent" | "span"
                property list<string> sharedWallpaperSpanScreens: [] // Empty means all monitors
                property string lockWallpaperMode: "shared" // "shared" | "perMonitor"
                property list<var> lockMonitorWallpapers: [] // [{ name, path }]
                property bool useMonitorSpecificColors: false
                property bool blendMonitorColors: false
                property string componentColorMonitor: ""
                property bool centeredWallpaper: false
                property string centeredWallpaperShape: "Cookie7Sided"
                property int centeredWallpaperSize: 400
                property string centeredWallpaperColor: "primaryContainer"
                property bool centeredWallpaperOnlyWhenLocked: false
                property string wallpaperAnimation: "magic"
                property int transitionDuration: 1200 // ms, applies to every wallpaper animation
                property bool enableWallpaperPreview: false
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.0 // Relative to wallpaper size
                    property bool enableSidebar: true
                    property real widgetsFactor: 1.2
                }
                // Shader wallpaper: datamosh/pixel-sort effects that react to
                // music. See modules/ii/background/wallpaperEffects/README.md.
                //
                // This block is the *ambient* effect, i.e. what happens to the
                // wallpaper that is already set. The datamosh switch transition
                // is not toggled here - it is one of the wallpaperAnimation
                // choices ("datamosh"), alongside magic/stripes/etc.
                property JsonObject effects: JsonObject {
                    property bool enable: false
                    property bool musicReactive: true
                    // Which player the *wallpaper effect* reacts to: an MPRIS
                    // identity / desktop entry, or "" for anything playing.
                    // This only gates the wallpaper - the player cards and the
                    // ticker always follow their own app, see AudioLevels.qml.
                    property string player: ""
                    // Where the effect runs: "all", "allButPrimary" (primary is
                    // Config.options.hyprland.primaryMonitor), or a monitor name.
                    property string screenMode: "all"
                    // When true, each monitor's ambient look is picked
                    // independently from the preset list (see
                    // EffectPresets.qml) instead of every monitor sharing the
                    // sliders below. monitorPresetAssignments is where each
                    // monitor's pick is persisted, so it stays put across
                    // restarts until rerolled.
                    property bool randomizePerMonitor: false
                    property list<var> monitorPresetAssignments: []
                    // Cross-monitor seam effect. By default the primary
                    // wallpaper spills outward; "mutual" lets every monitor
                    // exchange fragments with its touching neighbour.
                    property bool neighborBleed: false
                    property string neighborBleedMode: "primary" // "primary" | "mutual"
                    property bool neighborBleedMusicReactive: true
                    property real neighborBleedWidth: 0.16
                    property real neighborBleedStrength: 0.9
                    property real neighborBleedFragmentThreshold: 0.08
                    property real neighborBleedFragmentSoftness: 0.24
                    property bool neighborBleedColorTrails: true
                    property real neighborBleedColorThreshold: 0.12
                    property real neighborBleedColorSoftness: 0.20
                    property real neighborBleedColorStrength: 0.7
                    // LiDAR is a wallpaper-level accent. With a seam active it
                    // also traces imported fragments; otherwise it scans the
                    // current wallpaper directly.
                    property bool neighborBleedLidar: false
                    // "scan" traces a raster/sweep, while "outlines" traces
                    // the current image's luminance and colour edges.
                    property string neighborBleedLidarMode: "outlines" // "scan" | "outlines"
                    property real neighborBleedLidarStrength: 0.55
                    property real neighborBleedLidarDensity: 24
                    property real neighborBleedLidarSpeed: 0.75
                    property real neighborBleedEdgeSoftness: 0.32
                    property real neighborBleedRaggedness: 1.0
                    property real neighborBleedGrain: 1.0
                    property real neighborBleedMotionSpeed: 1.0
                    property real neighborBleedFeedback: 1.0
                    property bool neighborBleedBattle: true
                    property real neighborBleedBattleStrength: 1.0
                    property real neighborBleedPrimaryPush: 1.0
                    property real neighborBleedSecondaryResistance: 1.0
                    // "synchronized" only takes effect when wallpaperAnimation
                    // is "datamosh" - see Background.qml's transitionDirection.
                    property string transitionMode: "independent" // "independent" | "synchronized"
                    // The states saturate rather than stack, so each number is
                    // the level that state actually reaches. All three at 0
                    // makes the wallpaper a still image with no per-frame work.
                    property real musicIntensity: 0.35 // continuous, scales with loudness
                    property real beatIntensity: 0.75
                    // Per-effect audio source. "auto" preserves the existing
                    // tuned mixes; explicit sources let a kick, bass band, or
                    // another band own an effect outright.
                    property JsonObject audioRouting: JsonObject {
                        property string melt: "auto"
                        property string pointCloud: "auto"
                        property string feedback: "auto"
                        property string pixelSort: "auto"
                        property string blockCorruption: "auto"
                        property string chromaticAberration: "auto"
                        property string noise: "auto"
                        property string lidar: "auto"
                    }

                    // Look of the ambient effect. The "datamosh" transition
                    // deliberately ignores all of these and rerolls its own
                    // character on every switch - only transitionDuration above
                    // applies to it. Audio scales these up.
                    property real pointCloud: 0.6    // sparse point dissolve
                    property int pointSpacing: 10     // point grid spacing, px
                    property real melt: 0.7          // drip / melt strength
                    property real meltReach: 0.55     // how high the spectrum curve climbs
                    property int meltWidth: 14        // paint-run width, px
                    property real feedback: 0.6
                    property real pixelSort: 0.5
                    property real sortThreshold: 0.65
                    property real sortLength: 0.1
                    // One axis for melt, block slide and pixel sort alike:
                    // "vertical", "horizontal", or "random" (each wallpaper
                    // switch rolls its own; the ambient effect stays vertical).
                    property string glitchDirection: "random"
                    property int blockSize: 8
                    property real blockCorruption: 0.7
                    property real chromaticAberration: 0.35
                    property real noise: 0.25

                    // The wallpaper switch has its own look, separate from the
                    // ambient effect above, and deliberately no monitor option:
                    // a switch happens on every screen, with the same seed, so
                    // it looks identical everywhere.
                    property JsonObject transition: JsonObject {
                        // Roll the strengths per switch instead of using the
                        // values below. The spatial character (which blocks
                        // detach when, how far they slide, debris size) is
                        // always seeded either way.
                        property bool randomize: true
                        property string glitchDirection: "random"
                        property real melt: 0.80
                        property real pointCloud: 0.55
                        property real pixelSort: 0.70
                        property real feedback: 0.70
                        property real blockCorruption: 0.60
                        property real chromaticAberration: 0.40
                        property real noise: 0.40
                    }

                    // Passed straight through to qs-audiotap. The analysis all
                    // happens there, so these are the only reactivity knobs.
                    property JsonObject audio: JsonObject {
                        // Keep qs-audiotap running even when nothing is drawing
                        // a visualiser, so the first beat after one appears is
                        // not lost to process start + PipeWire connect. Costs
                        // ~0.6% of one core. Never auto-starts the microphone
                        // tap - that one still only runs when it is on screen.
                        property bool autoStart: true
                        property int updateRate: 90        // max output lines/sec
                        property int beatDecay: 100        // ms, beat envelope fall
                        property int beatMinInterval: 110  // ms between beats
                        property real beatSensitivity: 1.35 // x above running average
                        property real beatFloor: 0.15      // bass below this is never a beat
                        property real gainRelease: 0.9995  // auto gain release per hop
                        property real barDecay: 0.035      // spectrum fall per hop
                        property int bars: 50
                        property int rangeLow: 50
                        property int rangeHigh: 16000
                    }
                }
                // User-saved looks for the shader wallpaper - same shape as
                // the built-in ones in EffectPresets.qml (name + the same 14
                // ambient effect values), so both are applied and matched
                // the same way.
                property list<var> customEffectPresets: []
            }

            property JsonObject bar: JsonObject {
                property string colorSource: "wallpaper" // "wallpaper" | "appAccent"
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }
                property bool showFrame: false
                property real frameThickness: 4
                property string frameColor: "black"
                property bool followFrameColor: false
                property bool centerOnlyReserveFrame: false
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property string groupColor: "layer1"
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                property string borderless: "pills"
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property bool showBackground: true
                property bool verbose: true
                property bool vertical: false
                property JsonObject resources: JsonObject {
                    property string style: "filled"
                    property bool showValue: false
                    property bool alwaysShowSwap: false
                    property bool alwaysShowCpu: true
                    property bool alwaysShowCpuTemp: false
                    property bool alwaysShowDisk: false
                    property bool alwaysShowGpu: false
                    property bool alwaysShowRam: true
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                }

                property JsonObject dynamicIsland: JsonObject {
                    property string visualizerStyle: "dots" // "dots", "wave", "none"
                    property bool showMediaControls: false
                    property string leftWidget: "none"
                    property string rightWidget: "none"
                }
                property JsonObject divider: JsonObject {
                    property string style: "rect" // rect - dot - space
                    property int spacing: 20
                }

                property JsonObject layouts: JsonObject {
                    property list<string> leftLayout: ["launcherButton", "workspaces", "activeWindow"]
                    property list<string> middleLayout: ["clockWidget"]
                    property list<string> rightLayout: ["sysTray", "utilButtons", "systemIcons", "powerButton"]
                }
                
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property list<var> monitorLayouts: []
                property list<var> monitorSettings: []
                property list<var> monitorVisibility: []
                // User-defined toggle buttons shown alongside CPU/RAM/etc in the bar's
                // resources area. Each: {id, name, mode: "command"|"service", command,
                // serviceName, iconOn, iconOff}. See services/CustomBarResources.qml.
                property list<var> customResources: []
                property JsonObject utilButtons: JsonObject {
                    property list<string> order: ["screenSnip", "keyboardToggle", "darkModeToggle", "caffeineToggle"]
                    property bool showScreenSnip: true
                    property bool showColorPicker: true
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: false
                    property bool showWallpaperToggle: true
                    property bool showDarkModeToggle: false
                    property bool showPerformanceProfileToggle: false
                    property bool showCaffeineToggle: true
                    property bool showScreenRecord: false       
                    property bool showScreenRecordingIndicator: false
                    property bool isRecording: false
                }

                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: false
                    property string indicatorStyle: "dot" // "dot" or "icon"
                    property bool alwaysShowNumbers: true
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
                property JsonObject tooltips: JsonObject {
                    property bool enable: true
                    property bool clickToShow: false
                }
                property JsonObject media: JsonObject {
                    property bool alwaysVisible: false
                    property bool onlyTitle: false
                    property int maxWidth: 280
                    property int minWidth: 100
                    property string preferredPlayer: ""
                    property bool showLyrics: false
                }
                property JsonObject visualizer: JsonObject {
                    // outputSource: "auto" follows whichever app is playing,
                    // "app:<name>" pins one application, anything else is a
                    // PipeWire node name. inputSource is a node name or "auto".
                    property string outputSource: "auto"
                    property string inputSource: "auto"
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool showBackground: true
                property bool showPinButton: true
                property bool showAppsButton: true
                property bool showMedia: true
                property bool monochromeIcons: true
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "auto" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: [ "org.kde.dolphin", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property bool showWidgets: false
                property list<string> screenList: [] // Monitors where showWidgets applies; empty means all monitors
                property bool showMedia: true
                property bool showToolbars: true
                // Idle timeout (seconds) before the lock screen activates,
                // and how much longer after that before the system sleeps -
                // written into hypridle.conf, which has no live-reload, so
                // changing these restarts the hypridle process (see
                // scripts/hypridle/set_timeouts.sh).
                property int idleTimeoutSec: 300
                property int sleepAfterLockTimeoutSec: 600
                // Extra seconds after the lock screen activates before the
                // display itself is powered off, giving the lock surface
                // time to actually be up first.
                property int dpmsDelaySec: 10
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                    property int size: 20
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property string keyboardLayout: "" // Empty keeps the current layout
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
                // Player identifiers (desktopEntry/identity, lowercased), most-preferred first.
                // The first entry that matches a currently-open player wins control of media
                // keys/the active-player display, regardless of which player is actually playing.
                property list<string> priorityOrder: []
                // When true, whichever prioritized player is actually playing wins over
                // strict rank - priority order only breaks ties between multiple playing
                // players, or applies when none of them are playing at all.
                property bool priorityPreferActive: false
                // Which control elements show in the Super+M menu, and in what order.
                // Valid ids: visualizer, progressBar, skipButtons, playPauseButton,
                // lyricsToggle, volumeBar.
                property list<string> menuElements: ["visualizer", "progressBar", "skipButtons", "playPauseButton", "lyricsToggle"]
                // The ticker is a fixed, minimal Player card: album art,
                // title/artist, and the visualizer background - no buttons,
                // no progress bar, nothing clickable to fumble in a popup
                // you can't interact with without dismissing it.
                property bool tickerEnabled: true
                property int tickerTimeout: 2000
                // "bar" (default, hugs whichever edge the bar is on), or a
                // fixed corner/edge/center: top_left, top_center, top_right,
                // center_left, center, center_right, bottom_left,
                // bottom_center, bottom_right.
                property string tickerPosition: "bar"
                // Also flashes the ticker when the track changes without any
                // key/bind press (e.g. a song ending and the next one
                // starting on its own).
                property bool tickerOnTrackChange: false
                // Skips showing the ticker if the player's own app window is
                // already visible (mapped, on a workspace currently shown on
                // some monitor) - matched by desktopEntry/identity against
                // open windows' class, so there's no point popping up a
                // ticker for something already on screen.
                property bool tickerHideIfPlayerVisible: true
                // "focused" follows whichever monitor currently has input
                // focus; "specific" pins to tickerMonitorName regardless.
                property string tickerMonitorMode: "focused"
                property string tickerMonitorName: ""
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property bool expandPopups: false
                property string position: "top_right"
                // "focused" follows whichever monitor currently has input
                // focus; "specific" pins to monitorName regardless.
                property string monitorMode: "focused"
                property string monitorName: ""
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
                // Same preset vocabulary as media.tickerPosition (including
                // "bar"). Default "bar" preserves the OSD's original
                // hardcoded look (hugs the bar edge, centered).
                property string position: "bar"
                // "focused" follows whichever monitor currently has input
                // focus; "specific" pins to monitorName regardless.
                property string monitorMode: "focused"
                property string monitorName: ""
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property string style: "default"
                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool centerIcons: true
            }

            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: [ "Fcitx" ]
                property bool filterPassive: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property list<string> clipboardPinnedEntries: []
                property bool clipboardVideoProcessing: true
                property JsonObject clipboardSmartPaste: JsonObject {
                    property bool enable: true
                    property bool autoRewriteClipboardOnCopy: true
                    property bool stripTrackingParams: true
                    property bool rewriteSocialEmbeds: true
                    property bool rewriteXTwitter: true
                    property string xTwitterReplacementDomain: "fxtwitter.com"
                    property bool rewriteInstagram: true
                    property string instagramReplacementDomain: "vxinstagram.com"
                }
                property bool bitwardenDismissOnInteract: false
                property JsonObject bitwardenTotp: JsonObject {
                    property bool showCountdown: true
                    property bool autoClearClipboard: false
                    property int autoClearSeconds: 20
                    property bool protectRecentClipboard: true
                    property int protectRecentClipboardSeconds: 8
                }
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string bitwarden: "!"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string keybinds: "<"
                    property string symbols: "."
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
            }

            property JsonObject sidebar: JsonObject {
                property bool banner: true
                property bool bottomGroup: true
                property bool mediaPlayer: false
                property string bannerImage: ""
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject media: JsonObject {
                    property bool enable: true
                    property bool artColors: false
                    property string artShape: "Oval"
                    property bool showLyrics: true
                    property bool shapeArt: false
                    property bool blurredBackground: false
                }
                
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: true
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property string bottomLeftAction: "sidebarLeftOpen"
                    property string bottomRightAction: "sidebarRightOpen"
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: true
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
            }

            property JsonObject custom: JsonObject {
                property string distroIcon: "google-gemini-symbolic"
                property bool colorizeIcon: true
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://","") // strip "file://"
                property bool recordSystemAudio: false
                property bool recordMicAudio: false
                property bool showInputOverlay: false
                property bool showMouseInput: true
                property bool onlyShowInputChords: false
                property int inputOverlayVerticalOffset: 24
                property int frameRate: 30
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: "" // only copy to clipboard when empty
            }

            property JsonObject sounds: JsonObject {
                property bool battery: false
                property bool pomodoro: false
                property string theme: "freedesktop"
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property bool showDate: true
                property string shortDateFormat: "dd/MM"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "ddd, dd/MM"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages
            }
            
            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property bool showBlurBackground: false
                property bool showHomePath: true
                property string userPath: "" // This can be set to any path and it will show up as a quick access in the wallpaper selector"
                property string liveWallpapersPath: ""
                property bool showSearchbar: true
                property int columns: 4
                property bool closeAfterSelection: true
                property int changeInterval: 0 
                property string sortMode: "time"
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }
        }
    }
}
