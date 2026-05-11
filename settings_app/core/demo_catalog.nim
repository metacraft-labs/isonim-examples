## settings_app/core/demo_catalog.nim — concrete catalog used by the
## settings demo's composition roots and parity tests.
##
## The `SettingsVM` itself is generic over a `SettingsCatalog`. This
## module ships the *specific* catalog the demo apps render — three
## groups (Appearance, Editor, Notifications), three items each, one
## of every kind. The shape is small enough to fit on a phone screen
## but rich enough that the parity tests exercise toggle, number
## (with clamping) and choice (with rejection) on every renderer.
##
## Renderer repositories should not edit this file — the catalog is
## the cross-renderer contract. New items only land here together
## with corresponding leaf coverage on every platform.

import ./types

proc buildDemoSettingsCatalog*(): SettingsCatalog =
  ## Build a fresh catalog instance. Returned ref is owned by the
  ## caller; the demo composition roots build it once at startup and
  ## hand it to `newSettingsVM`. Tests build a fresh catalog per test
  ## so each VM owns its own catalog reference.
  newSettingsCatalog(@[
    group("appearance", "Appearance", @[
      toggleItem(
        id = "appearance.dark_mode",
        label = "Dark mode",
        default = false,
        description = "Use the dark colour palette."),
      choiceItem(
        id = "appearance.theme",
        label = "Theme",
        options = @["Default", "Solarized", "Dracula"],
        default = "Default",
        description = "Named colour palette."),
      numberItem(
        id = "appearance.font_size",
        label = "Font size",
        min = 10, max = 32, default = 14, step = 1,
        suffix = "pt",
        description = "Editor font size in points."),
    ]),
    group("editor", "Editor", @[
      toggleItem(
        id = "editor.tabs_to_spaces",
        label = "Insert spaces for tabs",
        default = true),
      numberItem(
        id = "editor.tab_width",
        label = "Tab width",
        min = 1, max = 8, default = 4),
      choiceItem(
        id = "editor.line_endings",
        label = "Line endings",
        options = @["LF", "CRLF", "CR"],
        default = "LF",
        description = "Line ending convention for new files."),
    ]),
    group("notifications", "Notifications", @[
      toggleItem(
        id = "notifications.enable_sounds",
        label = "Play sounds",
        default = true),
      toggleItem(
        id = "notifications.show_badges",
        label = "Show badges",
        default = false),
      numberItem(
        id = "notifications.poll_interval_ms",
        label = "Poll interval",
        min = 500, max = 60000, default = 5000, step = 500,
        suffix = "ms",
        description = "How often to check for new notifications."),
    ]),
  ])
