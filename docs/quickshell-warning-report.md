# Quickshell Warning Report

This report was collected from the latest runtime log and updated after the monitor-aware palette, desktop-menu, Settings, and focus-stutter investigation.

## Current crash status

No current crash was found. The daemonized `qs --path /home/dominik/.config/quickshell/end4-pC` process was still running, and no recent SIGSEGV, SIGABRT, fatal assertion, or coredump was present. Older coredumps exist from previous days.

## High priority

### Focus-driven hidden window reassignment — addressed

Sources: `modules/ii/sidebarLeft/SidebarLeft.qml`, `SidebarRight.qml`, `settings/Settings.qml`, and `overview/Overview.qml`.

Hidden layer-shell windows followed `Hyprland.focusedMonitor` in their `screen:` bindings. Crossing monitors reassigned several windows even while `visible=false`, coinciding with the reported cursor stutter. They now keep a stable target screen while hidden and select the focused screen when opened. `MonitorThemes` was verified not to regenerate palettes on focus changes; its polling timer checks wallpaper/config signatures only.

### Settings eager page construction — addressed

`modules/ii/settings/SettingsContent.qml` activated every settings page and the profile page from `Component.onCompleted`, constructing the entire settings tree during opening. Page loaders now remain lazy and activate the selected page on demand.

### Desktop-menu palette fallback — addressed

`modules/ii/desktopMenu/DesktopMenu.qml` passed a raw `QScreen` to the monitor palette resolver. The resolver did not recognize `QScreen.name`, so the main menu fell back to the blended palette while submenus used the correct monitor palette. The resolver now accepts raw screen objects.

### Transparency bypass — addressed

Monitor-aware shell colors initially returned raw opaque palette values, bypassing `Appearance` transparency handling. Layer alpha is now applied at the monitor-aware color boundary: background surfaces follow background transparency while base content surfaces remain opaque.

### Undefined `Config`

Source: `services/SystemInfo.qml:23`

Error: `ReferenceError: Config is not defined`

`SystemInfo.qml` reads `Config.options.profile.showHostnameWithUsername` without importing the module exposing `Config`. This can break username display evaluation. Add the appropriate `qs.modules.common` import or otherwise expose `Config`.

### Undefined `GlobalStates`

Sources:

- `modules/ii/sidebarLeft/SidebarLeftContent.qml:55,116`
- `modules/ii/sidebarLeft/Translator.qml:110`

The files use `GlobalStates` without importing the root `qs` module. Sidebar tab requests, translator prefill, and reset behavior may fail. Verify signal ownership after adding the import.

### Popup binding loops

Sources:

- `modules/ii/bar/Resource.qml:171`
- `modules/ii/bar/NetworkSpeed.qml:160`

Errors: `Binding loop detected for property "active"`

Popup loader activation, requested visibility, hover ownership, and close timers depend on one another. Break the cycle so loader activity is driven by one-way state such as `requestedVisible || closeTimer.running`.

### Undefined bar window

Source: `modules/common/widgets/BarWidgetSwitcher.qml:7`

Error: `Cannot read property 'window' of undefined`

Loader-created widgets can evaluate before attachment to a `PanelWindow`. Use null-safe window/screen access and defer monitor-dependent work until a window exists. This can also cause incorrect monitor-specific settings.

### Read-only `mirrored` assignment

Source: `modules/ii/bar/BarContent.qml`

Error: `Cannot assign to read-only property "mirrored"`

The bar assigns the wrong mirroring property. Determine whether `LayoutMirroring.enabled` or a control-specific writable property is intended.

## Medium priority

### Invalid `Connections` signal names

Sources:

- `modules/ii/sidebarLeft/Translator.qml:109`
- `modules/ii/sidebarLeft/SidebarLeftContent.qml:115`

Handlers for `onSidebarLeftTranslatorResetNonceChanged`, `onSidebarLeftTranslatorPrefillNonceChanged`, `onSidebarLeftRequestedTabChanged`, and `onSidebarLeftOpenChanged` do not match signals on their targets. Verify target objects and remove or rename obsolete handlers.

### Anchors inside layouts

Sources:

- `modules/ii/settings/SettingsContent.qml:191`
- `modules/ii/settings/pages/About.qml:116`
- `modules/ii/settings/pages/GeneralConfig.qml:599`

Items managed by `RowLayout`, `ColumnLayout`, or `GridLayout` also use anchors. This is undefined behavior and can cause settings overlap. Replace anchors with `Layout.alignment`, `Layout.fillWidth`, `Layout.fillHeight`, and layout margins, or place the anchored item inside a plain `Item`.

### `InterfaceConfig` binding loop

Source: `modules/ii/settings/pages/InterfaceConfig.qml:61`

`MonitorConfigSwitch.checked` is bound through a `Binding`, while `onCheckedChanged` writes to the same configuration value. Add a user-change/update guard or separate model updates from binding refreshes.

Status: the write was moved to the click path; verify monitor-specific switches after a live reload.

### Duplicate `bar` IPC handler

Source: `modules/ii/bar/Bar.qml:308`

One `IpcHandler` targeting `bar` is shadowed by another. Merge the handlers or use distinct target names.

### Unsupported IPC argument type

Source: `modules/ii/regionSelector/RegionSelector.qml:242`

`recordWithOptions` exposes `systemAudio: QVariant`, which cannot cross IPC. Use IPC-safe primitive types such as `bool`, `int`, `real`, or `string`.

## Low priority and cosmetic

### Missing translations

Sources:

- `services/Translation.qml:58`
- `services/Translation.qml:68`

Requested `en_US.json` and `C.json` files are absent. Add translations or make the loader silently fall back.

### Missing avatar

Sources:

- `modules/ii/sidebarRight/SidebarRightContent.qml:203`
- `modules/ii/settings/SettingsContent.qml:131`
- `modules/ii/background/widgets/usercard/UserCardWidget.qml:282`

`/home/dominik/.face` is missing. Check existence before assigning the image source or provide a fallback avatar.

### Missing custom icon directory

The shell attempts to load `/home/dominik/.config/quickshell/end4-pC/assets/icons/`. Create the directory or make icon lookup handle absent directories.

### Missing media artwork and stale MPRIS player

Source: `modules/ii/sidebarLeft/SidebarPlayerControl.qml:118`

Cached Firefox artwork is missing, and MPRIS property updates occur after the player disappears. Invalidate artwork and stop polling when the player is unregistered.

### Missing `.qmlls.ini`

QML tooling support is disabled. This has no runtime impact; add a project `.qmlls.ini` only if language-server support is wanted.

## Recommended order

1. Undefined `Config` and `GlobalStates`.
2. Popup binding loops and undefined bar-window access.
3. Settings layout violations and the `InterfaceConfig` binding loop.
4. Duplicate IPC handlers and unsupported IPC types.
5. Missing assets, translations, and media cleanup.
6. Optional QML tooling configuration.

None of the listed warnings was shown to cause the reported crash. Focus-driven hidden-window reassignment and eager Settings construction were correlated with visible stutter and have been addressed. Remaining popup warnings, undefined window access, and layout violations remain performance candidates.
