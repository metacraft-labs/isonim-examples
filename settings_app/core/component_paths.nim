## settings_app/core/component_paths.nim — canonical ``componentPath``
## taxonomy for the settings-app demo.
##
## RS-M11b / EX-M23b: same shape as ``task_app/core/component_paths``.
## The strings here mirror what the EX-M23 TUI settings leaves
## already embed — verified against
## ``settings_app/tui/leaves.nim``.
##
## The settings demo only annotates the layout containers + the
## group header today; individual control rows (toggle / number /
## choice) consume the surrounding ``SettingsRow`` container's path
## so the hit-test surface stays flat. Future per-control paths
## (e.g. ``settings_app/views/SettingsItem#dark-mode``) would be
## added here.

const
  SettingsRowPath* = "settings_app/views/SettingsRow"
    ## Single horizontal control row inside a group. One entry per
    ## visible item.

  SettingsGroupPath* = "settings_app/views/SettingsGroup"
    ## ``<section class="settings-group">`` container. One entry per
    ## visible group.

  SettingsGroupHeaderPath* = "settings_app/views/SettingsGroupHeader"
    ## Header (label + description) shown inside each group
    ## container. One entry per visible group.
