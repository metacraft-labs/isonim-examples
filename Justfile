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

test: test-orc

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
