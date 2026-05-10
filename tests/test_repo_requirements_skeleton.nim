## EX-M0 smoke test - asserts the repo-requirements scaffold is in place.
##
## This is the only test in the repo until EX-M1 brings real demo
## content. It verifies that every artefact listed in the EX-M0
## deliverables exists at the expected path, and that the AGENTS.md
## file documents the layered-demo forward pointer (Layer 3 + Layer 2
## shared, Layer 1 + Layer 4 per-platform).

import std/[os, strutils, unittest]

const repoRoot = currentSourcePath().parentDir().parentDir()

proc repoPath(rel: string): string =
  repoRoot / rel

suite "EX-M0 repo-requirements skeleton":
  test "flake.nix exists at repo root":
    check fileExists(repoPath("flake.nix"))

  test "Justfile exists at repo root":
    check fileExists(repoPath("Justfile"))

  test "AGENTS.md exists at repo root":
    check fileExists(repoPath("AGENTS.md"))

  test "CLAUDE.md is a symlink (per repo-requirements)":
    let p = repoPath("CLAUDE.md")
    check fileExists(p)
    check symlinkExists(p)

  test "README.md is a symlink to AGENTS.md (matches isonim-tui-serve)":
    let p = repoPath("README.md")
    check fileExists(p)
    check symlinkExists(p)

  test ".envrc exists at repo root":
    check fileExists(repoPath(".envrc"))

  test ".envrc invokes the flake":
    let envrc = readFile(repoPath(".envrc"))
    check envrc.contains("use flake")

  test "LICENSE exists at repo root":
    check fileExists(repoPath("LICENSE"))

  test "LICENSE is the MIT Metacraft Labs wording":
    let lic = readFile(repoPath("LICENSE"))
    check lic.contains("MIT License")
    check lic.contains("Metacraft Labs")

  test ".gitignore exists at repo root":
    check fileExists(repoPath(".gitignore"))

  test ".github/workflows/ci.yml exists":
    check fileExists(repoPath(".github/workflows/ci.yml"))

  test "isonim_examples.nimble exists at repo root":
    check fileExists(repoPath("isonim_examples.nimble"))

  test "AGENTS.md documents the layered-demo forward pointer":
    let agents = readFile(repoPath("AGENTS.md"))
    # Must explain the four-layer split that frames every later
    # milestone (EX-M1+).
    check agents.contains("Layer 3")
    check agents.contains("Layer 2")
    check agents.contains("Layer 1")
    check agents.contains("Layer 4")
    check agents.contains("ViewModel")
    check agents.contains("core/")
    # Cross-links into the canonical specs.
    check agents.contains("isonim-cross-platform-architecture")
    check agents.contains("isonim-render-stream.status")
