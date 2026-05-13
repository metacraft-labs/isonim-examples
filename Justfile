## Justfile - isonim-examples.

alias t := test
alias fmt := format

# Sibling-repo paths are wired in `config.nims` (so direct `nim c`
# invocations outside `just` resolve them too); the only explicit
# search path here is `tests/` so per-test helpers under
# `tests/helpers/` resolve via `import ./helpers/...` in driver tests.
src-paths := "--path:tests"
nim-flags := "--styleCheck:usages --styleCheck:error"

# Test list — every top-level `tests/test_*.nim` (helpers under
# `tests/helpers/` are libraries, not tests, and intentionally
# excluded by anchoring the glob at the `tests/` root).
tests := `find tests -maxdepth 1 -type f -name 'test_*.nim' | sort | tr '\n' ' '`

build:
    @mkdir -p test-logs
    @echo "isonim-examples has no demo binaries yet - EX-M1+ will add them."
    @for t in {{tests}}; do \
      echo "Building $t"; \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release \
          -o:test-logs/$(basename $t .nim) $t 2>&1 | tee -a test-logs/build.log; \
    done

test: test-orc test-async-perf-matrix

test-unit:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[unit] $t"; \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release \
          -r $t 2>&1 | tee -a test-logs/test-unit.log; \
    done

test-integration:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[integration] $t"; \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release --threads:on \
          -r $t 2>&1 | tee -a test-logs/test-integration.log; \
    done

test-orc:
    just _matrix orc release on
    just _matrix orc debug on

test-arc:
    just _matrix arc release on

test-refc:
    just _matrix refc release on

test-threads-off:
    just _matrix orc release off

test-all: test-orc test-arc test-refc test-threads-off

# --- EX-M18: fake-time async perf demo, across the native async backends ---
#
# The canonical fake-time test (tests/test_async_perf_demo.nim) is the
# teaching artifact for testing async ViewModels. It exercises 100
# mixed simulated DB ops and asserts the suite completes in well under
# 100 ms wall-clock — orders of magnitude faster than the 3-5 seconds
# those ops would burn against a real event loop.
#
# The fake-time invariant must hold across every async backend
# nim-everywhere supports. The matrix below mirrors the structure of
# nim-everywhere's own `test-async-*` recipes.

test-async-perf:
    nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release \
        -r tests/test_async_perf_demo.nim

test-async-perf-asyncdispatch:
    nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release \
        -d:asyncBackend=asyncdispatch \
        -r tests/test_async_perf_demo.nim

# chronos is an optional dep — gate behind a `nim check` probe so the
# matrix degrades gracefully when chronos isn't on the nimble path.
test-async-perf-chronos:
    @if nim check --hints:off {{src-paths}} -d:asyncBackend=chronos \
        tests/test_async_perf_demo.nim >/dev/null 2>&1; then \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release \
          -d:asyncBackend=chronos \
          -r tests/test_async_perf_demo.nim; \
    else \
      echo "[test-async-perf-chronos] chronos not on nimble path; skipping"; \
    fi

test-async-perf-matrix: test-async-perf test-async-perf-asyncdispatch test-async-perf-chronos

_matrix mm mode threads:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[{{mm}}/{{mode}}/threads:{{threads}}] $t"; \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:{{mm}} -d:{{mode}} --threads:{{threads}} \
        -r $t 2>&1 | tee -a test-logs/{{mm}}-{{mode}}-threads-{{threads}}.log; \
    done

lint: lint-nim lint-nix lint-markdown

lint-nim:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "Checking $t"; \
      nim check {{nim-flags}} {{src-paths}} --mm:orc $t 2>&1 | tee -a test-logs/lint-nim.log; \
    done

lint-nix:
    nixfmt --check flake.nix

lint-markdown:
    @if command -v markdownlint-cli2 >/dev/null 2>&1; then \
      markdownlint-cli2 "**/*.md" "#**/node_modules/**" "#test-logs/**" || true; \
    else \
      echo "markdownlint-cli2 not available; skipping"; \
    fi

format: format-nim format-nix

format-nim:
    @if command -v nimpretty >/dev/null 2>&1; then \
      nimpretty tests/*.nim; \
    else \
      echo "nimpretty not available; skipping Nim formatting"; \
    fi

format-nix:
    nixfmt flake.nix

bump-version version:
    sed -i 's/^version[[:space:]]*=.*/version       = "{{version}}"/' isonim_examples.nimble

bench *FLAGS:
    @echo "isonim-examples has no benchmark suite yet - cross-renderer parity benches will land in a follow-up milestone."

bench-quick:
    just bench --quick

clean:
    rm -rf test-logs nim-cache build

# --- IsoNim Editor (EX-M14) ---
#
# The editor instance ships a single Nim → JS bundle plus per-backend
# demo binaries built natively from this repo. The bundle is served on
# port 8091 (8090 is the upstream wanderlust editor in `isonim`).

# Build per-backend demo binaries (Linux: web, tui, gpui, freya). Each
# binary is a single launcher that dispatches to the right demo via
# the `--demo=<task|settings>` CLI flag; the editor's BackendBinaryRegistry
# registers one launcher per backend (see editor/workspace.nim).
build-backends:
    @mkdir -p build/backends
    @for renderer in tui web gpui freya; do \
      echo "[build-backends] isonim-examples-$renderer"; \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release --threads:on \
          -o:build/backends/isonim-examples-$renderer \
          editor/backends/$renderer.nim 2>&1 | tee -a test-logs/build-backends.log; \
    done

# Build the macOS-only Cocoa launcher (EX-M19). The launcher
# `editor/backends/cocoa.nim` is gated `when defined(macosx)`: on
# Linux it compiles as an empty shell (no `runDemoBridge` symbol)
# and the editor's BackendBinaryRegistry leaves `pbCocoa`
# unregistered. On macOS this recipe produces
# `build/backends/isonim-examples-cocoa`, which the registry picks
# up via `BackendBinaryNames[pbCocoa]`.
#
# Run AFTER `just build-backends` so the four Linux launchers are
# already built; together they give the macOS host's editor a 5-backend
# matrix (Web / TUI / GPUI / Freya / Cocoa).
build-backends-macos:
    @mkdir -p build/backends
    @echo "[build-backends-macos] isonim-examples-cocoa"
    nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release --threads:on \
        -o:build/backends/isonim-examples-cocoa \
        editor/backends/cocoa.nim 2>&1 | tee -a test-logs/build-backends.log

# Build the Android launcher (EX-M21). The launcher
# `editor/backends/android.nim` is a host-side binary (macOS or Linux)
# that talks to a connected Android device via `adb` and streams the
# device's framebuffer through the bridge. Gated `when defined(macosx)
# or defined(linux)`; other hosts compile as an empty shell and the
# editor's BackendBinaryRegistry leaves `pbAndroid` unregistered.
#
# Pairs with EX-M22's settings_app Android composition root and the
# RS-M6 Android adapter; the on-device runtime is the `nimexamples`
# flavor of `isonim-android` (`MainActivity` + `libtask_app.so`).
build-backends-android:
    @mkdir -p build/backends
    @echo "[build-backends-android] isonim-examples-android"
    nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release --threads:on \
        -d:mockJni \
        -o:build/backends/isonim-examples-android \
        editor/backends/android.nim 2>&1 | tee -a test-logs/build-backends.log

# Build the editor (Nim → JS).
editor-build:
    @mkdir -p build/editor
    nim js --path:. --path:../isonim/src --path:../nim-everywhere/src \
        -o:build/editor/editor.js editor/main.nim
    cp editor/index.html build/editor/index.html
    @echo "Built: build/editor/ - open build/editor/index.html"

# Serve the editor at http://localhost:8091.
editor-serve: editor-build build-backends
    @echo "Serving editor on http://localhost:8091"
    cd build/editor && python3 -m http.server 8091

# Screenshot all editor views at all sizes -> build/editor/screenshots/.
editor-screenshot:
    node tools/editor-screenshot.mjs

# Screenshot a specific view (shell, sidebar-only, ...).
editor-screenshot-view view:
    node tools/editor-screenshot.mjs --view {{view}}

# Screenshot at a specific size (wide, laptop, ...).
editor-screenshot-size size:
    node tools/editor-screenshot.mjs --size {{size}}
