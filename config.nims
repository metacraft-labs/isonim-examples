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
