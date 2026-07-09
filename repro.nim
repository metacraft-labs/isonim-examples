## Reprobuild project file for isonim-examples.
##
## **Typed-Cross-Project-Deps rollout — the W3 KEYSTONE of the IsoNim
## ecosystem: the shared, canonical demo tree (SC-11 develop-mode from-source
## sibling consumption) that is BOTH a multi-sibling CONSUMER and a
## LIBRARY PRODUCER.** ``isonim-examples`` is the single home for the IsoNim
## layered demo apps (``task_app/`` + ``settings_app/``): a shared Layer-3
## ViewModel + Layer-2 view template with per-platform Layer-1 leaves and
## Layer-4 composition roots. Every renderer repo (isonim-tui, isonim-gpui,
## isonim-freya, isonim-cocoa, isonim-android, the render-serve / tui-serve
## bridges) consumes this repo's demo tree as a path-based dependency; the
## keystone role is why this recipe both declares ``library isonim_examples``
## (so isonim-tui's PASS-2 ``task_app`` edges can ``uses: "isonim-examples"``)
## and threads the widest ``uses:`` sibling set in the rollout.
##
## ===========================================================================
## SIBLING CONSUMPTION (uses:) — the SC-11 develop-mode from-source library
## producers whose ``src/`` roots this repo's ``config.nims`` hardcodes as
## ``--path:../<repo>/src`` literals, expressed here the reprobuild-native way
## ===========================================================================
##
## The repo's ``config.nims`` resolves its cross-repo imports with a wall of
## ``switch("path", "$config/../<repo>/src")`` literals. This recipe replaces
## each such literal for a LIBRARY-EXPORTING sibling with a ``uses:
## "<sibling>"`` edge: reprobuild builds the sibling from source (its
## ``library`` edge) and threads its ``src/`` root onto this repo's ``nim c
## --path:`` via the SC-11 ``nimPathDirs`` aux channel
## (Cross-Repo-Source-Consumption.md §4.2a). Editing a sibling's ``src/``
## invalidates + rebuilds this repo's affected test compiles. Mirrors the
## landed sibling consumer recipes ``isonim-tui/repro.nim`` (uses: isonim +
## nim-termctl + nim-pty + nim-everywhere), ``isonim-freya/repro.nim`` +
## ``isonim-gpui/repro.nim`` (uses: isonim + nim-everywhere), widened to the
## full demo-tree consumption set.
##
## The THIRTEEN library-exporting ``uses:`` siblings, each verified to ship a
## committed ``repro.nim`` with a ``library`` export whose default exported
## path is ``src`` (Cross-Repo-Source-Consumption.md §4.2a.4):
##
##   * ``isonim``              — ``library isonim`` (reactive core + DSL +
##     testing/mock_dom + renderers/terminal_demo; the demo cores + views +
##     every leaf import ``isonim/core/*`` / ``isonim/testing/*``).
##   * ``isonim-tui``          — ``library isonim_tui`` (the TUI renderer +
##     ``newTerminalTestHarness``; the tui leaves / tui end-to-end + parity
##     tests import ``isonim_tui`` / ``isonim_tui/{events,renderer}``).
##   * ``isonim-freya``        — ``library isonim_freya`` (``isonim_freya/
##     {renderer,bindings}``; the freya leaves / launcher / parity tests).
##   * ``isonim-gpui``         — ``library isonim_gpui`` (``isonim_gpui/
##     {renderer,bindings}``; the gpui leaves / launcher / parity tests).
##   * ``isonim-cocoa``        — ``library isonim_cocoa`` (``isonim_cocoa/
##     renderer``; the cocoa leaves compile-gate + macOS-only tests. The
##     Cocoa modules collapse to empty shells off ``-d:macosx`` so the Linux
##     compile-gate test drives ``nim check --os:macosx`` over the fixture).
##   * ``isonim-render-serve`` — ``library isonim_render_serve`` (the
##     streaming bridge + per-renderer adapters the editor launcher backends
##     and the ``*_launcher_element_tree`` tests import).
##   * ``isonim-tui-serve``    — ``library isonim_tui_serve`` (the D/M/P
##     xterm.js packet codec + element-tree/story-dispatch helpers the
##     ``tui_term`` launcher + cross-renderer-component-paths tests import).
##   * ``nim-acp``             — ``library nim_acp`` (transitive under the
##     editor's design-review ``nim_agents`` adapter).
##   * ``nim-agent-harbor``    — ``library nim_agent_harbor`` (same).
##   * ``nim-agents``          — ``library nim_agents`` (the editor's
##     design-review adapter; transitively pulls nim-acp + nim-agent-harbor).
##   * ``nim-everywhere``      — ``library nim_everywhere`` (the cross-target
##     platform seam + ``FakeAsyncContext`` / ``async_compat`` the async-perf
##     + fake-time VM tests drive; also isonim's transitive platform seam).
##   * ``nim-pty``             — ``library nim_pty`` (isonim-tui's real-pty
##     dependency, threaded transitively when a test pulls the full
##     ``isonim_tui`` umbrella).
##   * ``nim-termctl``         — ``library nim_termctl`` (isonim-tui's input
##     parser, threaded transitively via ``isonim_tui/renderer``).
##
## ===========================================================================
## NON-uses: sibling / third-party source trees — threaded via ``paths:``
## (the way ``config.nims`` and the landed sibling recipes treat them)
## ===========================================================================
##
##   * ``../nim-faststreams`` + ``../nim-stew`` — THIRD-PARTY status-im
##     upstreams EXCLUDED from the rollout (no ``repro.nim`` ``library``
##     export). They are isonim's transitive nimble deps (``requires
##     "faststreams"``), resolved by ``--path`` exactly as isonim's own
##     build resolves them, matching ``isonim-tui/repro.nim`` +
##     ``isonim-freya/repro.nim``. NOT ``uses:`` edges.
##   * ``../isonim-android/nim-lib/src`` + ``../isonim-android/src`` — the
##     Android renderer sibling. Unlike the other twelve renderer/library
##     siblings, ``isonim-android/repro.nim`` declares **NO ``library``**
##     export (its ``package isonim_android`` block has only ``uses: isonim``
##     + a test corpus; the renderer lives under the non-default
##     ``nim-lib/src/isonim_android/`` root, and ``src/`` is an empty
##     scaffold). Per Cross-Repo-Source-Consumption.md §4.2a.2 the SC-11
##     ``nimPathDirs`` channel only threads a sibling that declares a
##     ``library``, so ``uses: "isonim-android"`` would NOT thread
##     ``nim-lib/src`` (and would fail to resolve — no library, no
##     executable). It is therefore threaded the same way as the third-party
##     trees: both its roots are listed in ``paths:``. (The only modelled
##     test that transitively references the Android renderer at COMPILE time,
##     ``test_settings_parity_across_renderers``, imports ``isonim_android/
##     renderer`` under a ``when defined(android)`` guard, so on this Linux
##     host the import is inert — but the roots are listed unconditionally so
##     the guard's ``--os:android`` sibling (the ``android_leaves_compile``
##     subprocess ``nim check``) resolves them.) When isonim-android lands a
##     ``library`` export it can be promoted to a ``uses:`` edge.
##
## **``config.nims`` co-existence.** ``nim c`` reads this repo's
## ``config.nims`` from the project root, which ALSO lists every sibling
## ``--path:../<repo>/src`` literal. The ``uses:`` ``nimPathDirs`` channel and
## the ``config.nims`` literals resolve to the SAME sibling ``src/`` roots (in
## develop mode the develop-overrides point each sibling at ``../<repo>``, the
## exact location ``config.nims`` expects), so the duplicate ``--path`` entries
## are harmless (``nim`` de-duplicates its path list). ``config.nims`` also
## bakes the four launcher ``-d:with*`` defines (``withCodecWebP``,
## ``withInProcessWebP``, ``withElementTreeDelta``); those gate only the
## per-backend LAUNCHER builds (``editor/backends/*``), not the modelled test
## corpus, and are read from ``config.nims`` for any build that needs them.
##
## ===========================================================================
## LIBRARY EXPORT (the keystone half)
## ===========================================================================
##
## ``library isonim_examples`` exports this repo's importable demo tree so a
## downstream repo can consume it via ``uses: "isonim-examples"`` — the
## PASS-2 cycle-break isonim-tui's recipe documents: isonim-tui's four
## ``task_app`` tests ``import task_app/main_tui`` / ``task_app/main_web``
## (which live HERE), while this repo's tests ``import isonim_tui``. Neither
## lands fully first; isonim-tui landed PASS-1 (its library + every headless
## test EXCEPT those four), which unblocked this recipe; this recipe's
## ``library isonim_examples`` in turn unblocks isonim-tui's PASS-2, where the
## four deferred ``task_app`` edges arrive via ``uses: "isonim-examples"``.
##
## The exported path is ``src`` by convention default. This repo has **no
## ``src/`` directory** — the demo modules live under ``task_app/`` /
## ``settings_app/`` (+ shared ``services/`` / ``editor/``), consumed as
## ``import task_app/main_tui`` etc. So the export sets ``exportedPath = "."``
## (Cross-Repo-Source-Consumption.md §4.2a.4): the repo ROOT is the importable
## root, exactly what isonim-tui's ``--path:../isonim-examples`` (repo root)
## resolves against. A consumer ``uses: "isonim-examples"`` then gets
## ``../isonim-examples`` on ``--path``, and ``import task_app/main_tui``
## resolves from source.
##
## ===========================================================================
## TEST CORPUS — the ``Justfile`` ``tests`` list (every top-level
## ``tests/test_*.nim``) modelled as the two-edge test template
## ===========================================================================
##
## Compile profile reproduces ``just test`` → ``test-orc`` → ``_matrix orc
## release on`` (``nim c --mm:orc -d:release --threads:on``) — the default
## matrix point. (The ``debug`` matrix point + the arc/refc/threads-off
## matrix cells are alternate CONFIGURATIONS of the same test list, not
## additional tests; the single default point stands in for them, matching
## every landed sibling recipe.) Per file: a compile BUILD edge
## (``buildNimUnittest.build`` → ``build/test-bin/<stem>``, collected into
## ``test-builds``) + an EXECUTE edge (``edge.testBinary.run``, collected into
## ``test``) — the two-edge template from Package-Model.md §"The test
## template". Every EXECUTE edge transitively depends on its BUILD edge, so
## ``repro build test`` / ``repro test`` materialise the runnable closure.
##
## ``paths = @[".", "tests", <non-uses: trees>]`` supplies the repo ROOT (so
## ``import task_app/...`` / ``settings_app/...`` / ``services/...`` /
## ``editor/...`` resolve — the ``config.nims`` ``switch("path", "$config")``
## equivalent), the ``tests`` root (``config.nims``' ``--path:tests`` — the
## per-test helpers under ``tests/helpers/`` resolve via ``import
## ./helpers/...``), the two THIRD-PARTY status-im trees, and the two
## isonim-android roots. The THIRTEEN library-sibling ``src`` roots are
## threaded off the ``uses:`` ``nimPathDirs`` channel, NOT spelled here. The
## ``--styleCheck`` / ``--skipParentCfg`` / ``--skipUserCfg`` switches from
## the ``Justfile`` ``nim-flags`` are style/hermeticity flags that don't
## affect the produced binary and aren't part of the typed ``nim c`` surface,
## so they're omitted (style-check hints are non-fatal per the charter).
##
## **Freya-shim rpath.** The Freya renderer's ``bindings.nim`` FFI is a
## bare-soname ``{.dynlib: "libfreya_nim_shim.so".}`` (unlike the GPUI
## bindings, which resolve an ABSOLUTE ``currentSourcePath()``-derived path
## into ``../isonim-gpui/rust/target/debug`` — so the GPUI shim loads with no
## env). So every test that constructs a ``FreyaRenderer`` (the freya
## leaves / parity tests) needs ``libfreya_nim_shim.so`` reachable at run
## time. Rather than an ``LD_LIBRARY_PATH`` env, every test BUILD edge bakes
## an absolute ``-Wl,-rpath,../isonim-freya/rust/target/debug`` (the same
## intent as ``isonim-freya/repro.nim``'s own rpath), so a freya-constructing
## binary ``dlopen``s the prebuilt sibling shim from its rpath. The shim is a
## PREBUILT native artifact from the isonim-freya sibling build (reprobuild's
## dev shell has no ``cargo`` tool to rebuild it here — it is out-of-band, per
## the isonim-freya recipe header). The GPUI shim likewise must be prebuilt in
## the sibling; both are present from the landed sibling recipe builds.
##
## ===========================================================================
## DEFERRED / not-modelled tests (documented, NOT deleted or weakened)
## ===========================================================================
##
## (A) **Launcher-subprocess frame-streaming tests (6).** These tests
##     ``startProcess`` a real per-backend launcher binary
##     (``build/backends/isonim-examples-<renderer>``), wait for it to BIND a
##     TCP socket, then drive a WebSocket handshake and assert on a
##     continuous, wall-clock-timed FRAME STREAM (idle-frame counts, manifest
##     re-emission cadence, story-switch round-trips). They are live
##     subprocess frame-streaming integration paths with real socket-bind +
##     frame-cadence deadlines — genuinely environment-sensitive beyond the
##     engine's direct-binary (run-to-exit-0) runner, and the gpui/freya
##     launchers additionally need their native shim resolvable + a
##     rasterisable surface in the SPAWNED CHILD. Verified: the launchers
##     BUILD headlessly and each test's FIRST subtest ("manifest arrives" /
##     "boot") passes, but the idle-frame-streaming + story-switch subtests
##     fail under the sandbox (``framesObserved`` / ``initialManifests`` stay
##     0; gpui/freya children "did not bind within 4s"). Deferred as a
##     display/streaming-runtime env-block, NOT weakened. The six:
##       - ``test_tui_launcher_element_tree``     (idle-frame stream cadence)
##       - ``test_gpui_launcher_element_tree``    (child shim bind + stream)
##       - ``test_freya_launcher_element_tree``   (child shim bind + stream)
##       - ``test_tui_term_launcher_e2e``         (D/M/P stream + select-story)
##       - ``test_launcher_select_story_e2e``     (story-driven launcher spawn)
##       - ``test_cross_renderer_component_paths`` (spawns the tui-term
##         launcher to compare cross-renderer manifests)
##
## (B) **Android device tests (2).** These assert a real Android device /
##     emulator is reachable via ``adb`` (``adbDevicePresent()`` /
##     ``adbDeviceCount() >= 1``) and/or spawn the host-side
##     ``isonim-examples-android`` launcher that talks to a device over
##     ``adb``. No device/emulator is attachable in this headless sandbox, so
##     both hard-fail on the device precondition (they self-document the
##     failure as intentional: "requires at least one device … Attach an
##     emulator / device and re-run"). Deferred as a real-device env-block:
##       - ``test_android_launcher_device_only`` (``adb devices`` gate)
##       - ``test_android_launcher_element_tree`` (``adb`` device + launcher)
##
## (C) **``test_freya_leaves_end_to_end`` — RESOLVED + RE-INCLUDED.** This test
##     formerly SEGV'd under reprobuild's EXECUTE edge (which ``LD_PRELOAD``s
##     ``librepro_monitor_shim.so``) deep in isonim's reactive core
##     (``runTaskApp`` → ``buildTaskApp`` → ``taskList`` → ``createComputation``
##     → ``visibleTasks`` → ``trackRead`` nil read), though it passed cleanly
##     un-monitored. That SEGV was the old monitor-shim x86-64 syscall-scanner
##     defect (the INT3 syscall-trap patcher mis-identifying a ``0f 05`` byte
##     pair inside a ``call``/``jmp rel32`` displacement — the rmdir-rel32
##     SIGILL class) perturbing the reactive graph, NOT an isonim bug. That
##     defect is now durably fixed in ``nim-stackable-hooks`` (the hardened
##     ``looksLikeLinuxX8664Syscall`` / ``visitLinuxX8664SyscallMemory`` rel32
##     guard) and the reprobuild flake pin is bumped to the hardened rev.
##     Re-assessed under the HARDENED shim: the test now passes both subtests to
##     exit 0 under an ``LD_PRELOAD`` of the freshly-built hardened
##     ``librepro_monitor_shim.so`` (``[OK] scripted scenario …`` / ``[OK]
##     render plan …``), identical to its standalone (un-monitored) exit-0 run —
##     no SEGV. It is therefore RE-INCLUDED in ``testStems`` above and runs
##     green under the reprobuild EXECUTE edge. NOT weakened — every structural
##     + count + designed-checkbox-glyph assertion runs.
##
## All OTHER top-level ``tests/test_*.nim`` are MODELLED + green: the
## shared-VM / async-fake-time cores, the settings + task_app cross-renderer
## parity + round-trip suites (which construct + drive TUI / GPUI / Freya
## renderers), the tui + gpui leaves end-to-end suites, the cross-compile
## GATE tests (``test_cocoa_leaves_compile`` drives
## ``nim check --os:macosx``; ``test_android_leaves_compile`` drives ``nim
## check --os:android -d:mockJni`` — both COMPILE-check other-OS renderer
## leaves headlessly from this Linux host and pass because the renderer
## siblings resolve), the editor workspace / streaming / frame-source / input
## suites, and the ``*_macos_only`` / ``*_android_only`` / cocoa
## ``*_launcher_element_tree`` tests that self-gate ``when defined(macosx)`` /
## ``when defined(android)`` and compile to an exit-0 no-op shell on Linux.
##
## **Product fix folded in (separate commit).** ``test_freya_leaves_end_to_end``
## asserted the OLD ASCII checkbox markers ``[ ]`` / ``[x]``, but the Freya
## leaves' Round-10 "designed checkbox" redesign (``task_app/freya/leaves.nim``
## — a deliberate visual affordance) renders a hollow ``☐`` (off) / filled
## ``✓`` (on), distinct from the TUI flavour's ASCII markers. The test golden
## predated that redesign (STALE golden — the same class the landed sibling
## recipes fixed): the assertions are refreshed to the current designed
## glyphs (NOT weakened — every structural + count + class assertion stands).
##
## **Tool provisioning.** ``defaultToolProvisioning "path"`` matches the
## canonical recipes: the nix dev shell puts ``nim`` + ``gcc`` (+ the
## renderer siblings' system libs — yoga / tree-sitter — on the linker path)
## on the environment, so the weak-local PATH resolver is the right default.
## It is also required for the ``uses:`` declarations to resolve at all
## ("typed tool provisioning is required for uses declarations").

import std/os
import repro_project_dsl

# ``ct_test_nim_unittest`` supplies the ``buildNimUnittest.build(...)`` typed
# tool used by every test BUILD edge and the ``edge.testBinary.run(...)`` UFCS
# dispatch for the EXECUTE edges. It re-exports ``repro_project_dsl`` so the
# import order is unimportant. Like the other consumer sibling recipes this
# file does NOT import ``ct_test_runner_install`` (engine-coupled,
# reprobuild-internal): the execute edges route through the engine's default
# direct-binary runner (run the binary, key on exit status), which is exactly
# the exit-0 verification this corpus needs — Nim ``unittest`` prints per-suite
# results and exits non-zero on failure.
import ct_test_nim_unittest

# Absolute rpath to the prebuilt Freya Rust cdylib directory (see the
# Freya-shim rpath note in the module docstring). ``currentSourcePath`` is
# this ``repro.nim`` at the repo root, so ``parentDir`` is the repo root;
# joining ``../isonim-freya/rust/target/debug`` + ``absolutePath`` yields the
# directory that holds ``libfreya_nim_shim.so``.
const repoRoot = currentSourcePath().parentDir()
let freyaShimRpath =
  absolutePath(repoRoot / ".." / "isonim-freya" / "rust" / "target" / "debug")

# The HEADLESS-runnable native corpus — every top-level ``tests/test_*.nim``
# in the ``Justfile`` ``tests`` list MINUS the six launcher-subprocess
# frame-streaming tests (set A) and the two Android device tests (set B),
# per the module docstring = 29 modelled files. (``test_freya_leaves_end_to_end``,
# formerly set C, is now RE-INCLUDED — the monitor-shim scanner defect that
# caused its reactive-core SEGV is durably fixed.) Each compiles + runs to
# exit 0 under the reprobuild EXECUTE edge (monitor-shim ``LD_PRELOAD``) with
# the default matrix flags (``--mm:orc -d:release --threads:on``); the
# ``*_macos_only`` / ``*_android_only`` / cocoa ``*_launcher_element_tree``
# files self-``skip()`` / compile to an empty shell via their
# ``when defined(<os>)`` guards (verified exit 0).
const testStems: seq[string] = @[
  # ---- shared-VM / async-fake-time cores ----
  "test_vm_round_trip",
  "test_task_app_async_vm",
  "test_async_perf_demo",
  "test_fake_db",
  "test_repo_requirements_skeleton",
  # ---- task_app views / web target ----
  "test_views_compile_cross_renderer",
  "test_web_target_compiles",
  "test_vm_parity_across_renderers",
  # ---- task_app per-renderer leaves end-to-end ----
  "test_tui_leaves_end_to_end",
  "test_gpui_leaves_end_to_end",
  # ``test_freya_leaves_end_to_end`` is RE-INCLUDED: the reactive-core
  # ``trackRead`` SEGV that formerly appeared only under reprobuild's
  # monitor-shim ``LD_PRELOAD`` was the old monitor-shim x86-64 syscall-scanner
  # defect (now durably fixed in ``nim-stackable-hooks``; reprobuild flake pin
  # bumped). Under the fixed shim it runs the real Freya composition root
  # through the sibling Rust shim and passes every subtest.
  "test_freya_leaves_end_to_end",
  # ---- cross-compile GATE tests (nim check --os:<other> over a fixture) ----
  "test_cocoa_leaves_compile",     # nim check --os:macosx
  "test_android_leaves_compile",   # nim check --os:android -d:mockJni
  # ---- per-renderer *_only self-skip / compile-shell tests (Linux no-op) ----
  "test_cocoa_leaves_macos_only",
  "test_cocoa_launcher_macos_only",
  "test_cocoa_launcher_element_tree",
  "test_settings_cocoa_macos_only",
  "test_android_leaves_android_only",
  # ---- settings_app suites ----
  "test_settings_vm_round_trip",
  "test_settings_app_async_vm",
  "test_settings_tui_end_to_end",
  "test_settings_web_end_to_end",
  "test_settings_gpui_end_to_end",
  "test_settings_parity_across_renderers",
  "test_settings_components_compile_cross_renderer",
  # ---- editor workspace / streaming / frame-source / input suites ----
  "test_editor_workspace",
  "test_editor_streaming_preview",
  "test_editor_backend_frame_sources",
  "test_editor_backends_input_dispatch",
]

package isonim_examples:
  defaultToolProvisioning "path"

  uses:
    # Toolchain floor — the PATH-resolvable binaries the build needs. ``nim``
    # compiles every test binary (the ``buildNimUnittest.build`` edges below,
    # matching the nimble file's ``requires "nim >= 2.0.0"``); ``gcc`` is the
    # C back-end ``nim c`` shells out to and links through (it also compiles
    # isonim's vendored Yoga C++ + the tree-sitter grammar C sources the
    # renderer siblings pull in). Sufficient for the path-mode resolver under
    # ``nix develop``.
    "nim >=2.0"
    "gcc >=12"

    # The THIRTEEN landed sibling Nim-library producers this repo consumes
    # from source (SC-11 develop-mode). Naming each workspace project here
    # makes reprobuild build the sibling from source (its ``library`` edge)
    # and thread its ``src/`` root onto this repo's ``nim c --path:`` via the
    # ``nimPathDirs`` aux channel — replacing the ``config.nims``
    # ``--path:../<repo>/src`` literals. See the SIBLING CONSUMPTION section
    # of the module docstring for the per-sibling import mapping. (isonim-
    # android is threaded via ``paths:`` instead — it declares no ``library``
    # export; see the NON-uses: section.)
    "isonim"              # library isonim
    "isonim-tui"          # library isonim_tui
    "isonim-freya"        # library isonim_freya
    "isonim-gpui"         # library isonim_gpui
    "isonim-cocoa"        # library isonim_cocoa
    "isonim-render-serve" # library isonim_render_serve
    "isonim-tui-serve"    # library isonim_tui_serve
    "nim-acp"             # library nim_acp
    "nim-agent-harbor"    # library nim_agent_harbor
    "nim-agents"          # library nim_agents
    "nim-everywhere"      # library nim_everywhere
    "nim-pty"             # library nim_pty
    "nim-termctl"         # library nim_termctl

  # Library declaration — the demo tree is importable when this package is
  # consumed via ``uses: "isonim-examples"`` (the isonim-tui PASS-2
  # ``task_app`` edges; see the LIBRARY EXPORT note in the module docstring).
  # The exported root is the repo ROOT (``exportedPath = "."``) because the
  # demo modules live under ``task_app/`` / ``settings_app/`` — there is no
  # ``src/`` directory. A consumer then ``import task_app/main_tui`` etc.
  library isonim_examples:
    exportedPath: "."

  build:
    # Two-edge test template (Package-Model.md §"The test template"): one
    # compile BUILD edge + one EXECUTE edge per test file. BUILD halves
    # collect into ``test-builds`` (compile verification); EXECUTE halves
    # into ``test`` so ``repro test`` / ``repro build test`` materialise the
    # runnable closure (each execute edge transitively depends on its build
    # edge).
    #
    # ``basePaths`` supplies the repo ROOT (``import task_app/... /
    # settings_app/... / services/... / editor/...``), the ``tests`` root
    # (per-test ``./helpers/...``), the two THIRD-PARTY status-im trees, and
    # the two isonim-android roots (no ``library`` export → threaded here, not
    # via ``uses:``; see the module docstring). The THIRTEEN library-sibling
    # ``src`` roots are threaded off the ``uses:`` ``nimPathDirs`` channel,
    # NOT listed here. Compile flags reproduce ``just test`` → ``_matrix orc
    # release on``: ``--mm:orc`` (``mm``), ``-d:release`` (``defines``),
    # ``--threads:on`` (``threadsOn`` default).
    const basePaths = @[
      ".", "tests",
      "../nim-faststreams", "../nim-stew",
      "../isonim-android/nim-lib/src", "../isonim-android/src",
    ]

    # Every test BUILD edge bakes the absolute Freya-shim rpath so a binary
    # that constructs a ``FreyaRenderer`` ``dlopen``s the prebuilt sibling
    # ``libfreya_nim_shim.so`` at run time with no ``LD_LIBRARY_PATH`` (see
    # the Freya-shim rpath note in the module docstring). It is harmless on
    # binaries that never load the shim (an unused rpath entry).
    let freyaRpathPassL = @["-Wl,-rpath," & freyaShimRpath]

    var testBuildActions: seq[BuildActionDef] = @[]
    var testExecuteActions: seq[BuildActionDef] = @[]

    for stem in testStems:
      let source = "tests/" & stem & ".nim"
      let binary = "build/test-bin/" & stem

      let edge = buildNimUnittest.build(
        source = source,
        binary = binary,
        defines = @["release"],
        paths = basePaths,
        mm = "orc",
        extraPassL = freyaRpathPassL,
        actionId = "isonim-examples.test_build." & stem,
        # The demo tree + shared helper dirs + the nimble file are declared
        # inputs so the monitor tracks the transitively imported
        # ``task_app/**`` / ``settings_app/**`` / ``services/**`` /
        # ``editor/**`` / ``tests/helpers/**`` module trees.
        extraInputs = @[
          "task_app", "settings_app", "services", "editor",
          "tests/helpers", "isonim_examples.nimble"])
      testBuildActions.add(edge.action)

      # ``registerImplicitName = false``: the BUILD edge already owns the
      # binary basename as the implicit target name; the explicit ``actionId``
      # is the execute edge's selector (two-edge shape).
      let executeEdge = edge.testBinary.run(
        actionId = "isonim-examples.test_execute." & stem,
        registerImplicitName = false)
      testExecuteActions.add(executeEdge)

    discard collect("test", testExecuteActions)
    discard collect("test-builds", testBuildActions)
