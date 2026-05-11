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
