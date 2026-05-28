## editor_chrome/core/types.nim — Layer-3.5 shared type hierarchy for
## the chrome-icons showcase demo.
##
## The demo renders a horizontal row that mimics the editor's
## right-sidebar tab bar — a single wrench button, N robot/bot chat
## buttons, and a trailing plus button. The story lets the user pick
## an *icon set* (in-house, Lucide, Heroicons, Feather, Phosphor,
## Tabler, Bootstrap, Material) and observe how each library's glyphs
## look in the same chrome.
##
## *Preview-only.* The story does not affect the live editor's
## sidebar chrome — the editor keeps using the in-house set via the
## ``wrenchSvg`` / ``robotSvg`` / ``plusSvg`` aliases in
## ``isonim/src/isonim/editor/views/icons.nim``. The schema described
## by ``ChromeIconsSchema`` documents which knobs the showcase exposes
## to the editor's *Component Properties* panel.
##
## See ``isonim/src/isonim/editor/views/LICENSES.md`` for the upstream
## license attribution table.

type
  ChromeIconsStatusKind* {.pure.} = enum
    ## Overlay dot kind on a robot/bot button. The colour mapping is
    ## owned by the per-platform leaves; the VM only carries the
    ## semantic enum so a Layer-4 swap does not need a VM rebuild.
    cisIdle      ## grey dot — not running
    cisActive    ## green dot — running successfully
    cisAttention ## gold dot — running, needs review

  ChromeIconsSchema* = object
    ## The schema the showcase story exposes to the editor's
    ## *Component Properties* panel. Each field corresponds to one
    ## editable control under the preview.
    ##
    ## The shape mirrors the discriminated-union approach used by
    ## ``settings_app/core/types.nim`` (sikChoice / sikNumber /
    ## sikBoolean) but is kept as a flat record here because the
    ## chrome-icons showcase only has four knobs and they don't share
    ## the catalog-driven generality of the settings demo.
    iconSet*: string
      ## sikChoice — id of the icon set to render. Options come from
      ## ``isonim/editor/views/icons.iconSets`` (eight ids: in-house,
      ## lucide, heroicons, feather, phosphor, tabler, bootstrap,
      ## material). Default: ``"in-house"``.
    chatCount*: int
      ## sikNumber — how many robot/bot chat buttons to render.
      ## Default: 3. Clamped to [1, 8] by the VM.
    activeIndex*: int
      ## sikNumber — which chat index (0-based) carries the accent
      ## "active" styling. Default: 1. Clamped to [0, chatCount-1].
    showStatus*: bool
      ## sikBoolean — whether to overlay coloured status dots on the
      ## chat buttons (idle/active/attention). Default: true.

  ChromeIconsVM* = ref object
    ## Reactive ViewModel for the chrome-icons showcase. The fields
    ## are exposed via signals (not via the ``ChromeIconsSchema``
    ## record) because the views subscribe per-field; the schema is
    ## the *contract* with the editor's property panel while the
    ## signals are the *runtime* the leaves bind to.
    iconSetId*: string
    chatCount*: int
    activeIndex*: int
    showStatus*: bool

# ----------------------------------------------------------------------------
# Schema helpers — pure functions used by tests and by the views.
# ----------------------------------------------------------------------------

const
  ChromeIconsIconSetIds*: array[8, string] = [
    "in-house", "lucide", "heroicons", "feather",
    "phosphor", "tabler", "bootstrap", "material"]
    ## Stable id list for the iconSet choice. Order mirrors
    ## ``iconSets`` in ``isonim/editor/views/icons.nim``. Used by both
    ## the VM's validation path and by the schema-introspection helper
    ## tests.

  ChromeIconsMinChatCount* = 1
  ChromeIconsMaxChatCount* = 8
  ChromeIconsDefaultChatCount* = 3
  ChromeIconsDefaultActiveIndex* = 1

proc defaultChromeIconsSchema*(): ChromeIconsSchema =
  ## Build a schema record populated with the canonical defaults.
  ## Tests use this as the baseline; the VM's constructor delegates
  ## to it so the defaults live in exactly one place.
  ChromeIconsSchema(
    iconSet: "in-house",
    chatCount: ChromeIconsDefaultChatCount,
    activeIndex: ChromeIconsDefaultActiveIndex,
    showStatus: true)

proc statusForIndex*(index, count: int): ChromeIconsStatusKind =
  ## Deterministic status assignment for the showcase: position 0
  ## "active" (green), middle "attention" (gold), tail "idle"
  ## (grey). With three chats this yields one of each colour, which
  ## is the brief's "show all three states" requirement. With
  ## different counts the function still hits each kind at least
  ## once when count >= 3.
  if count <= 1: return cisActive
  if index == 0: cisActive
  elif index == count - 1: cisIdle
  elif index * 2 < count: cisActive
  elif index * 2 == count or (count mod 2 == 1 and index == count div 2):
    cisAttention
  else: cisIdle

proc isValidIconSetId*(id: string): bool =
  ## True when ``id`` matches one of the eight registered icon-set
  ## ids. Used by the VM to reject writes from a stale picker.
  for s in ChromeIconsIconSetIds:
    if s == id: return true
  false
