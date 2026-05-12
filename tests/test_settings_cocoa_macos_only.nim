## test_settings_cocoa_macos_only — EX-M20 macOS-host integration test.
##
## Drives the canonical settings_app scripted scenarios through the Cocoa
## composition root + Cocoa renderer's real event dispatch, asserting the
## resulting `SettingsVMSnapshot` matches the expected post-scenario state.
##
## Gated entirely `when defined(macosx):`. On Linux the body skips with a
## single `check true` and a docstring pointer to the cross-compile gate
## (`tests/test_cocoa_leaves_compile.nim`).
##
## Why a Cocoa-only acceptance test in addition to the
## `test_settings_parity_across_renderers.nim` extension?
##
##   * The parity test transitively links every renderer's runtime
##     (`libgpui_nim_shim.dylib`, `libtree-sitter.dylib`, ...), which
##     requires the workspace's full nix dev shell to be functional.
##     The macos-only test imports ONLY the Cocoa renderer + the
##     settings_app Cocoa composition root, so it runs against the
##     baseline macOS toolchain without any cross-renderer linker
##     dependencies. The single-driver acceptance gate is the
##     gating "this builds on a clean macOS host" criterion for
##     EX-M20.
##
##   * The same five scenarios from the parity matrix (A: basic, B:
##     empty, C: all-groups, D: clamp, E: choice-reject) drive the
##     Cocoa surface here. The VM snapshot assertions check the
##     post-scenario state directly rather than comparing against
##     other renderers (the parity property is the parity test's job;
##     this test verifies Cocoa-specific surface behaviour).

import std/unittest

when defined(macosx):
  import services/fake_db
  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/main_cocoa as cocoa_app
  import isonim_cocoa/renderer as cocoaR
  import ./helpers/settings_parity_snapshot
  import ./helpers/async_drive

  # ----------------------------------------------------------------------------
  # Helpers — locate the disclosure / group section / items in the Cocoa
  # element tree. The Cocoa shell renders a disclosure-list layout: only
  # the active group's items are mounted; clicking a different group's
  # header materialises that group's items in place via
  # `createRenderEffect`.
  # ----------------------------------------------------------------------------

  proc disclosureOf(r: cocoaR.CocoaRenderer;
                    root: cocoaR.CocoaElement;
                    groupId: string): cocoaR.CocoaElement =
    for i in 0 ..< r.childCount(root):
      let c = r.nthChild(root, i)
      if r.getAttribute(c, "data-disclosure-id") == groupId:
        return c
    cast[cocoaR.CocoaElement](nil)

  proc groupSectionOf(r: cocoaR.CocoaRenderer;
                      disclosure: cocoaR.CocoaElement): cocoaR.CocoaElement =
    for i in 0 ..< r.childCount(disclosure):
      let c = r.nthChild(disclosure, i)
      if r.getAttribute(c, "class") == "settings-group":
        return c
    cast[cocoaR.CocoaElement](nil)

  proc headerOf(r: cocoaR.CocoaRenderer;
                disclosure: cocoaR.CocoaElement): cocoaR.CocoaElement =
    let section = groupSectionOf(r, disclosure)
    for i in 0 ..< r.childCount(section):
      let c = r.nthChild(section, i)
      if r.getAttribute(c, "class") == "settings-group-header":
        return c
    cast[cocoaR.CocoaElement](nil)

  proc itemRows(r: cocoaR.CocoaRenderer;
                disclosure: cocoaR.CocoaElement): seq[cocoaR.CocoaElement] =
    let section = groupSectionOf(r, disclosure)
    for i in 0 ..< r.childCount(section):
      let c = r.nthChild(section, i)
      if r.getAttribute(c, "class") == "settings-item":
        result.add c

  proc itemRowByLabel(r: cocoaR.CocoaRenderer;
                      disclosure: cocoaR.CocoaElement;
                      label: string): cocoaR.CocoaElement =
    for row in itemRows(r, disclosure):
      if r.childCount(row) == 0: continue
      let labelNode = r.nthChild(row, 0)
      if r.getAttribute(labelNode, "class") == "settings-label" and
         r.textContent(labelNode) == label:
        return row
    cast[cocoaR.CocoaElement](nil)

  proc toggleOf(r: cocoaR.CocoaRenderer;
                row: cocoaR.CocoaElement): cocoaR.CocoaElement =
    let last = r.nthChild(row, r.childCount(row) - 1)
    if r.getAttribute(last, "type") == "checkbox": return last
    cast[cocoaR.CocoaElement](nil)

  proc numberInputOf(r: cocoaR.CocoaRenderer;
                     row: cocoaR.CocoaElement): cocoaR.CocoaElement =
    let host = r.nthChild(row, r.childCount(row) - 1)
    if r.getAttribute(host, "class") != "settings-number":
      return cast[cocoaR.CocoaElement](nil)
    for i in 0 ..< r.childCount(host):
      let c = r.nthChild(host, i)
      if r.getAttribute(c, "type") == "number": return c
    cast[cocoaR.CocoaElement](nil)

  proc choiceSelectOf(r: cocoaR.CocoaRenderer;
                      row: cocoaR.CocoaElement): cocoaR.CocoaElement =
    let host = r.nthChild(row, r.childCount(row) - 1)
    if r.getAttribute(host, "class") != "settings-choice":
      return cast[cocoaR.CocoaElement](nil)
    for i in 0 ..< r.childCount(host):
      let c = r.nthChild(host, i)
      if r.getAttribute(c, "class") == "": return c
    cast[cocoaR.CocoaElement](nil)

  # ----------------------------------------------------------------------------
  # Per-scenario apply.
  # ----------------------------------------------------------------------------

  proc applyBasic(vm: SettingsVM; drv: AsyncDriver) =
    let r = cocoaR.CocoaRenderer()
    let root = cocoa_app.buildSettingsApp(r, vm)
    drv.flush()
    let appearance = disclosureOf(r, root, "appearance")
    r.fireEvent(headerOf(r, appearance), "click"); drv.flush()
    let darkCb = toggleOf(r, itemRowByLabel(r, appearance, "Dark mode"))
    r.fireEvent(darkCb, "click"); drv.flush()
    let fontInp = numberInputOf(r, itemRowByLabel(r, appearance, "Font size"))
    r.setAttribute(fontInp, "data-value", "18")
    r.fireEvent(fontInp, "click"); drv.flush()
    let themeSel = choiceSelectOf(r, itemRowByLabel(r, appearance, "Theme"))
    r.setAttribute(themeSel, "data-value", "Solarized")
    r.fireEvent(themeSel, "click"); drv.flush()

  proc applyAllGroups(vm: SettingsVM; drv: AsyncDriver) =
    let r = cocoaR.CocoaRenderer()
    let root = cocoa_app.buildSettingsApp(r, vm)
    drv.flush()
    for g in vm.catalog.groups:
      let disclosure = disclosureOf(r, root, g.id)
      r.fireEvent(headerOf(r, disclosure), "click"); drv.flush()
      for row in itemRows(r, disclosure):
        let cb = toggleOf(r, row)
        if pointer(cb) != nil:
          r.fireEvent(cb, "click"); drv.flush()
          break

  proc applyClamp(vm: SettingsVM; drv: AsyncDriver) =
    let r = cocoaR.CocoaRenderer()
    let root = cocoa_app.buildSettingsApp(r, vm)
    drv.flush()
    let appearance = disclosureOf(r, root, "appearance")
    r.fireEvent(headerOf(r, appearance), "click"); drv.flush()
    let fontInp = numberInputOf(r, itemRowByLabel(r, appearance, "Font size"))
    r.setAttribute(fontInp, "data-value", "5")
    r.fireEvent(fontInp, "click"); drv.flush()

  proc applyEmpty(vm: SettingsVM; drv: AsyncDriver) =
    let r = cocoaR.CocoaRenderer()
    discard cocoa_app.buildSettingsApp(r, vm)
    drv.flush()

  proc applyChoiceReject(vm: SettingsVM; drv: AsyncDriver) =
    discard vm.setChoice("appearance.theme", "InvalidName"); drv.flush()

  proc seedVm(): (SettingsVM, AsyncDriver) =
    let drv = newAsyncDriver(seed = 42)
    drv.db.seedSettings(buildDemoSettingsCatalog())
    let vm = newSettingsVM(drv.db)
    (vm, drv)

  # ----------------------------------------------------------------------------
  # Test suite.
  # ----------------------------------------------------------------------------

  suite "EX-M20: Cocoa settings shell drives the canonical SettingsVM through real AppKit":

    test "A: basic — appearance.dark_mode=true, font_size=18, theme=Solarized":
      let (vm, drv) = seedVm()
      applyBasic(vm, drv)
      check vm.toggleValue("appearance.dark_mode") == true
      check vm.numberValue("appearance.font_size") == 18
      check vm.choiceValue("appearance.theme") == "Solarized"
      drv.shutdown()

    test "B: empty — initial state matches catalog defaults":
      let (vm, drv) = seedVm()
      applyEmpty(vm, drv)
      # Initial defaults from the catalog. Dark mode default = false,
      # font size default = 14, theme default = "Default".
      check vm.toggleValue("appearance.dark_mode") == false
      check vm.numberValue("appearance.font_size") == 14
      check vm.choiceValue("appearance.theme") == "Default"
      drv.shutdown()

    test "C: all-groups — toggle the first toggle in every group":
      let (vm, drv) = seedVm()
      applyAllGroups(vm, drv)
      # At least one toggle per group should now be flipped. The
      # catalog defines the first toggle in each group; here we use
      # the snapshot's sorted toggle entries to check that *some*
      # toggle is now true (the initial state has all toggles at the
      # catalog's defaults, which include `false` for the canonical
      # demo's first toggles).
      let snap = settingsVmSnapshot(vm)
      var anyToggled = false
      for (k, v) in snap.toggles:
        if v: anyToggled = true; break
      check anyToggled
      drv.shutdown()

    test "D: clamp — font_size=5 below min=10 clamps to 10":
      let (vm, drv) = seedVm()
      applyClamp(vm, drv)
      check vm.numberValue("appearance.font_size") == 10
      drv.shutdown()

    test "E: choice-reject — invalid theme leaves VM unchanged":
      let (vm, drv) = seedVm()
      applyChoiceReject(vm, drv)
      check vm.choiceValue("appearance.theme") == "Default"
      drv.shutdown()

else:
  ## Linux / non-macOS host. Skips so `just test` keeps passing.
  suite "EX-M20: Cocoa settings shell (macOS host)":
    test "skipped on Linux — see test_cocoa_leaves_compile.nim for the gate":
      check true
