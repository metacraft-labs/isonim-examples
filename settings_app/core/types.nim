## settings_app/core/types.nim — Layer-3.5 shared type hierarchy.
##
## Plain-value type definitions for the settings demo's catalog: a
## settings *catalog* is a list of *groups*, each group is a list of
## typed *items* (toggle / number / choice). The hierarchy is the
## single source of truth for both the renderer-agnostic Layer-2
## components (groups + items) and the per-platform Layer-3 shells
## (sidebar+pane on web, expand-collapse on TUI, grid on GPUI).
##
## This module owns the *shape* of the catalog only — no signals, no
## reactive primitives, no actions. The reactive `SettingsVM` lives in
## `vm.nim` and references these types.
##
## The discriminated `SettingsItem` keeps every item kind in a single
## seq while preserving Nim's exhaustive `case` checking at every
## consumer (components/leaves both pattern-match on `kind`). Each
## variant carries its own validation surface (min/max/step for
## numbers, options for choices) so the VM can validate user input
## without reaching into a parallel schema.
##
## EX-M8 milestone reference:
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.
##
## Cross-platform architecture:
## `codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`
## §"3-layer alternation".

type
  SettingsItemKind* {.pure.} = enum
    ## Tag for the `SettingsItem` discriminated union. Order is stable
    ## (used in snapshots / wire formats); add new kinds at the end.
    sikToggle
    sikNumber
    sikChoice

  SettingsItem* = object
    ## A single settings item. Value type — copied freely. The `id`
    ## field uniquely identifies the item within a catalog and is the
    ## key the VM uses for its per-item value tables (so it must be
    ## stable across catalog rebuilds).
    ##
    ## Convention: ids are dotted, group-prefixed, e.g.
    ## `"appearance.dark_mode"`. The VM does not enforce the dot
    ## convention; it only requires uniqueness.
    id*: string
    label*: string
    description*: string
    case kind*: SettingsItemKind
    of sikToggle:
      toggleDefault*: bool
    of sikNumber:
      numberMin*: int
      numberMax*: int
      numberStep*: int
      numberDefault*: int
      numberSuffix*: string
        ## Display-only suffix shown by the leaf, e.g. "px", "ms",
        ## "%". The VM never inspects this field.
    of sikChoice:
      choiceOptions*: seq[string]
      choiceDefault*: string

  SettingsGroup* = object
    ## A logical group of items. Each platform shell decides how to
    ## render the grouping (sidebar pane on web, expandable section on
    ## TUI, card on GPUI), but the grouping itself is part of the
    ## shared catalog so every platform exposes the same logical
    ## taxonomy.
    id*: string
    label*: string
    description*: string
    items*: seq[SettingsItem]

  SettingsCatalog* = ref object
    ## Static catalog of all groups + items for a settings UI. Per-app
    ## constant — created once at startup and handed to `newSettingsVM`.
    ## Wrapped in a ref so the VM can hold a single reference rather
    ## than a deep value copy (the catalog can be large).
    groups*: seq[SettingsGroup]

# ----------------------------------------------------------------------------
# Smart constructors — shorter call sites for catalog literals.
# ----------------------------------------------------------------------------

proc toggleItem*(id, label: string; default: bool;
                 description: string = ""): SettingsItem =
  ## Build a `sikToggle` item.
  SettingsItem(
    id: id,
    label: label,
    description: description,
    kind: sikToggle,
    toggleDefault: default)

proc numberItem*(id, label: string;
                 min, max, default: int;
                 step: int = 1;
                 suffix: string = "";
                 description: string = ""): SettingsItem =
  ## Build a `sikNumber` item. Caller is responsible for `min <= max`
  ## and `min <= default <= max`; the VM clamps writes but the catalog
  ## is expected to be well-formed.
  SettingsItem(
    id: id,
    label: label,
    description: description,
    kind: sikNumber,
    numberMin: min,
    numberMax: max,
    numberStep: step,
    numberDefault: default,
    numberSuffix: suffix)

proc choiceItem*(id, label: string;
                 options: seq[string];
                 default: string;
                 description: string = ""): SettingsItem =
  ## Build a `sikChoice` item. Caller is responsible for `default in
  ## options`; the VM rejects writes with values outside `options` but
  ## the catalog is expected to be well-formed.
  SettingsItem(
    id: id,
    label: label,
    description: description,
    kind: sikChoice,
    choiceOptions: options,
    choiceDefault: default)

proc group*(id, label: string;
            items: seq[SettingsItem];
            description: string = ""): SettingsGroup =
  ## Build a `SettingsGroup`.
  SettingsGroup(
    id: id,
    label: label,
    description: description,
    items: items)

proc newSettingsCatalog*(groups: seq[SettingsGroup]): SettingsCatalog =
  ## Build a `SettingsCatalog` from a sequence of groups.
  SettingsCatalog(groups: groups)

# ----------------------------------------------------------------------------
# Read-only lookups over the catalog. Pure functions, no side effects.
# ----------------------------------------------------------------------------

proc findGroup*(catalog: SettingsCatalog; groupId: string): SettingsGroup =
  ## Return the group with the given id. Raises `KeyError` if missing.
  ## Use `hasGroup` first if the id might be unknown.
  for g in catalog.groups:
    if g.id == groupId:
      return g
  raise newException(KeyError, "settings group not found: " & groupId)

proc hasGroup*(catalog: SettingsCatalog; groupId: string): bool =
  for g in catalog.groups:
    if g.id == groupId:
      return true
  false

proc findItem*(catalog: SettingsCatalog; itemId: string): SettingsItem =
  ## Return the item with the given id, regardless of which group it
  ## belongs to. Raises `KeyError` if missing.
  for g in catalog.groups:
    for it in g.items:
      if it.id == itemId:
        return it
  raise newException(KeyError, "settings item not found: " & itemId)

proc hasItem*(catalog: SettingsCatalog; itemId: string): bool =
  for g in catalog.groups:
    for it in g.items:
      if it.id == itemId:
        return true
  false

proc firstGroupId*(catalog: SettingsCatalog): string =
  ## Convenience: id of the first group, or empty string if the
  ## catalog has no groups. The VM uses this to seed `activeGroupId`
  ## at construction time.
  if catalog.groups.len == 0: ""
  else: catalog.groups[0].id
