## isonim-examples — repo-level Nim config.
##
## Path-based deps on sibling repositories so that `nim c` /
## `nim check` resolve cross-repo imports without needing `nimble`
## install. Mirrors the `src-paths` list in the Justfile.
##
## See `metacraft-specs/policies/repo-requirements.md` and the
## `isonim` workspace manifest in `metacraft-manifests/projects/`.

## `$config` resolves to the directory holding *this* config.nims (the
## repo root). `$projectDir` would resolve to the directory of the
## .nim file being compiled (e.g. tests/) which is not what we want.
switch("path", "$config")
switch("path", "$config/../isonim/src")
switch("path", "$config/../nim-everywhere/src")
switch("path", "$config/../nim-stew")
switch("path", "$config/../nim-faststreams")

# Phase C — the editor's design-review subsystem imports ``nim_agents``
# (transitively ``nim_acp`` + ``nim_agent_harbor``) via
# ``editor/design_review/editor_agent_adapter.nim``.  Resolving the
# sibling-repo facades here keeps ``nim c`` and ``nim js`` consistent
# regardless of how the build is invoked (``just editor-build``,
# direct ``nim``, IDE).
switch("path", "$config/../nim-agents/src")
switch("path", "$config/../nim-acp/src")
switch("path", "$config/../nim-agent-harbor/src")

# Additional paths for the EX-M1 cross-renderer compile-check tests:
# we need `isonim_tui/renderer` for the TerminalRenderer leaf surface,
# and the renderer transitively pulls a couple of nim-termctl modules.
# Pulling the top-level `isonim_tui` would also drag in tree-sitter
# (M19) which the tests don't need, so we import the `renderer`
# submodule directly.
switch("path", "$config/../isonim-tui/src")
switch("path", "$config/../nim-termctl/src")
switch("path", "$config/../nim-pty/src")

# EX-M3: GPUI leaves consume `isonim_gpui/renderer` (and its raw
# bindings module). The renderer FFI loads `libgpui_nim_shim.so` at
# run time via `dynlib`; the `LD_LIBRARY_PATH` (or a copy of the
# shared object next to the binary) must point at
# `../isonim-gpui/rust/target/debug` for tests that build the GPUI
# composition root to actually run. Compile-time resolution only needs
# the path switch below.
switch("path", "$config/../isonim-gpui/src")

# EX-M4: Freya leaves consume `isonim_freya/renderer` (and its raw
# bindings module). The renderer FFI loads `libfreya_nim_shim.so` at
# run time via `dynlib`; the `LD_LIBRARY_PATH` (or a copy of the
# shared object next to the binary) must point at
# `../isonim-freya/rust/target/debug` for tests that build the Freya
# composition root to actually run. Compile-time resolution only needs
# the path switch below.
switch("path", "$config/../isonim-freya/src")

# EX-M5: Cocoa leaves consume `isonim_cocoa/renderer`, which transitively
# imports `isonim_cocoa/objc_runtime`, `isonim_cocoa/foundation` and
# `isonim_cocoa/appkit/*`. Those modules need AppKit / the Objective-C
# runtime, so the Cocoa leaves themselves and the Cocoa composition root
# (`task_app/cocoa/leaves.nim`, `task_app/main_cocoa.nim`) gate every
# import behind `when defined(macosx)`. The `--path` switch below stays
# unconditional so the cross-compile gate test
# (`tests/test_cocoa_leaves_compile.nim`) can drive `nim check
# --os:macosx` over the Cocoa-only fixture from this Linux host. Plain
# `nim check` runs (no `--os:macosx`) on Linux are unaffected — the
# Cocoa modules collapse to empty shells.
switch("path", "$config/../isonim-cocoa/src")

# EX-M6: Android leaves consume `isonim_android/renderer`. The renderer
# itself is portable Nim (no `{.passL.}` / `{.emit.}` C blocks), but
# `isonim_android/jni_callbacks` requires either `-d:mockJni` (host-side
# test shim) or `-d:commandBuffer` (real Android JNI bridge) to be set
# at compile time — without one of those, `jni_callbacks` raises a
# hard `{.error.}`. The Android leaves and composition root
# (`task_app/android/leaves.nim`, `task_app/main_android.nim`) gate
# every import behind `when defined(android)` so plain `nim check` runs
# on Linux are unaffected (the Android modules collapse to empty
# shells). The `--path` switches below stay unconditional so the
# cross-compile gate test (`tests/test_android_leaves_compile.nim`) can
# drive `nim check --os:android -d:mockJni` over the Android-only
# fixture from this Linux host. The `nim-lib/src` path is needed
# because `isonim_android/renderer` lives under
# `isonim-android/nim-lib/src/isonim_android/`, separate from the
# `isonim-android/src/` directory that holds the broader package.
switch("path", "$config/../isonim-android/nim-lib/src")
switch("path", "$config/../isonim-android/src")

# EX-M14: the demo editor's per-backend launcher binaries
# (`editor/backends/<renderer>.nim`) reuse the isonim-render-serve
# bridge to serve frames over the streaming protocol. The launcher
# imports `isonim_render_serve` directly and announces a fixed
# backend identifier per launcher so the editor's left-edge strip
# can route to the correct one.
switch("path", "$config/../isonim-render-serve/src")

# RS-M13: the new TUI launcher (`editor/backends/tui_term.nim`)
# consumes `isonim_tui_serve`'s D/M/P packet codec + the RS-M13
# element-tree/story-dispatch helpers added in that repo. The
# sibling-repo path is resolved here so `nim c` finds the
# `isonim_tui_serve` top-level facade without a nimble install.
switch("path", "$config/../isonim-tui-serve/src")

# ELT-M8: WebP-lossless production transport. The codec is the SHIP
# tier per the ELT-M7 synthesis report. Every launcher built from
# this repo (cocoa today; gpui / freya / android in subsequent
# milestones) compiles the W-packet adapter in unconditionally. The
# bridge selects W per frame when ``--encoder webp`` (or
# ``--encoder auto``) is on the launcher CLI; without the define
# the W path silently degrades to V (or F).
switch("define", "withCodecWebP")

# FUH-M5: in-process libwebp encoder. Default-on so every per-backend
# launcher prefers the direct API call over the ~133 ms ffmpeg
# subprocess spawn (FUH-M4 audit § 5). The launcher-side runtime
# probe in ``adapters/webp_libwebp_ffi.isLibwebpAvailable`` falls
# back to the subprocess path when ``libwebp.dylib`` /
# ``libwebp.so.7`` can't be loaded; toggle off via
# ``--define:withInProcessWebP=false`` if needed.
switch("define", "withInProcessWebP")

# ETS-M3 Part B: enable the ``element-tree-delta`` wire path by
# default for every launcher built from this repo (gpui / freya /
# cocoa / android). Each backend reads ``when defined(withElementTreeDelta)``
# around its ``streamElementTreeDelta = true`` flip so the gate can
# still be turned off at build time via ``--define:withElementTreeDelta=false``
# for legacy-wire reproducibility checks. The gate-on path is
# backward compatible by construction: the bridge only flips from
# the legacy full-manifest body to the new delta sub-kind once the
# browser-side hello-accept (ETS-M4) echoes ``e/element-tree`` in
# its accept list. Pre-ETS-M4 browsers never advertise the token,
# so the launcher stays on the legacy wire shape.
switch("define", "withElementTreeDelta")
