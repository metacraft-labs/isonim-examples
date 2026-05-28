## editor_chrome/core/vm.nim — Layer-3 ViewModel for the chrome-icons
## showcase demo.
##
## The VM is intentionally small: four signals matching the four
## fields of ``ChromeIconsSchema``. There is no async surface — the
## chrome-icons demo is preview-only and has no persistent state, so
## the EX-M17 ``FakeDb`` / ``Resource`` machinery the settings demo
## uses is unnecessary here.
##
## The setter procs *clamp* / *reject* inputs the same way
## ``SettingsVM`` does — out-of-range numbers clamp, unknown iconSet
## ids are rejected. This keeps the schema-driven property panel's
## inputs safe even when the editor framework dispatches a stale
## value from a previous story selection.

import isonim/core/signals

import ./types

export types, signals

type
  ChromeIconsReactiveVM* = ref object
    ## The reactive surface — one ``Signal`` per schema field. The
    ## per-platform leaves subscribe to these signals via
    ## ``createRenderEffect`` so a programmatic mutation (e.g. the
    ## editor's property-panel write) propagates to the rendered tree
    ## without a re-mount.
    iconSetId*: Signal[string]
    chatCount*: Signal[int]
    activeIndex*: Signal[int]
    showStatus*: Signal[bool]

proc createChromeIconsVM*(schema: ChromeIconsSchema =
                                  defaultChromeIconsSchema()):
                          ChromeIconsReactiveVM =
  ## Construct a VM from a schema record. The default argument runs
  ## the canonical baseline (in-house set, 3 chats, middle active,
  ## status dots on) — the brief's "shows all three states" preview.
  let safeIcon =
    if isValidIconSetId(schema.iconSet): schema.iconSet
    else: "in-house"
  var count = schema.chatCount
  if count < ChromeIconsMinChatCount: count = ChromeIconsMinChatCount
  if count > ChromeIconsMaxChatCount: count = ChromeIconsMaxChatCount
  var active = schema.activeIndex
  if active < 0: active = 0
  if active >= count: active = count - 1
  ChromeIconsReactiveVM(
    iconSetId: createSignal[string](safeIcon),
    chatCount: createSignal[int](count),
    activeIndex: createSignal[int](active),
    showStatus: createSignal[bool](schema.showStatus))

proc setIconSet*(vm: ChromeIconsReactiveVM; id: string): bool
              {.discardable.} =
  ## Switch the rendered icon set. Rejected (returns ``false``) when
  ## ``id`` is not one of the eight registered ids — that's the same
  ## guard ``SettingsVM.setChoice`` uses.
  if not isValidIconSetId(id):
    return false
  vm.iconSetId.val = id
  true

proc setChatCount*(vm: ChromeIconsReactiveVM; n: int): bool
                 {.discardable.} =
  ## Set the rendered chat count. Value is clamped to
  ## ``[ChromeIconsMinChatCount, ChromeIconsMaxChatCount]`` and the
  ## active index is re-clamped against the new count so the showcase
  ## never references a non-existent chat.
  var clamped = n
  if clamped < ChromeIconsMinChatCount: clamped = ChromeIconsMinChatCount
  if clamped > ChromeIconsMaxChatCount: clamped = ChromeIconsMaxChatCount
  vm.chatCount.val = clamped
  if vm.activeIndex.val >= clamped:
    vm.activeIndex.val = clamped - 1
  true

proc setActiveIndex*(vm: ChromeIconsReactiveVM; idx: int): bool
                   {.discardable.} =
  ## Set which chat carries the accent styling. Clamped to
  ## ``[0, chatCount-1]``.
  var clamped = idx
  if clamped < 0: clamped = 0
  let upper = vm.chatCount.val - 1
  if clamped > upper: clamped = upper
  vm.activeIndex.val = clamped
  true

proc setShowStatus*(vm: ChromeIconsReactiveVM; v: bool) {.discardable.} =
  ## Toggle the per-chat status dot overlay.
  vm.showStatus.val = v

proc currentSchema*(vm: ChromeIconsReactiveVM): ChromeIconsSchema =
  ## Read the current schema state — convenience for tests that want
  ## to assert against a value type without subscribing.
  ChromeIconsSchema(
    iconSet: vm.iconSetId.val,
    chatCount: vm.chatCount.val,
    activeIndex: vm.activeIndex.val,
    showStatus: vm.showStatus.val)
