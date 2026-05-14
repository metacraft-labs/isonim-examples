## settings_app/core/story_ids.nim — canonical storyId taxonomy for
## the settings-app demo.
##
## RS-M12. Mirrors ``task_app/core/story_ids.nim``; see that file's
## header for the contract. The constants below mirror EXACTLY what
## ``isonim-examples/editor/stories.nim`` emits as
## ``item.group & " / " & item.name`` for every settings_app story.

const
  # ---- Pages ----
  SettingsAppPagesPreferences* = "Settings App / Pages / Preferences"
  SettingsAppPagesAppearanceGroup* =
    "Settings App / Pages / Appearance Group"
  SettingsAppPagesEditorGroup* = "Settings App / Pages / Editor Group"

  # ---- Components: Group ----
  SettingsAppGroupAppearance* = "Settings App / Group / Appearance"
  SettingsAppGroupEditor* = "Settings App / Group / Editor"
  SettingsAppGroupNotifications* = "Settings App / Group / Notifications"

  # ---- Components: ToggleItem ----
  SettingsAppToggleItemOff* = "Settings App / ToggleItem / Off"
  SettingsAppToggleItemOn* = "Settings App / ToggleItem / On"

  # ---- Components: ChoiceItem ----
  SettingsAppChoiceItemDefault* = "Settings App / ChoiceItem / Default"
  SettingsAppChoiceItemAlternate* = "Settings App / ChoiceItem / Alternate"

  # ---- Components: NumberItem ----
  SettingsAppNumberItemDefault* = "Settings App / NumberItem / Default"
  SettingsAppNumberItemClamped* = "Settings App / NumberItem / Clamped"

  # ---- Foundations ----
  SettingsAppFoundationsItemDensity* =
    "Settings App / Foundations / Item Density"
  SettingsAppFoundationsControlStates* =
    "Settings App / Foundations / Control States"

  # ---- Flows ----
  SettingsAppFlowOpensAppearance* =
    "Toggle Setting Flow / Opens Appearance group"
  SettingsAppFlowTogglesDark* = "Toggle Setting Flow / Toggles dark mode"
  SettingsAppFlowAdjustsFontSize* = "Toggle Setting Flow / Adjusts font size"
