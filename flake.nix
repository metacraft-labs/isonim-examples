{
  description = "isonim-examples - canonical home for IsoNim layered demo applications";

  inputs = {
    nixos-modules.url = "github:metacraft-labs/nixos-modules";
    nixpkgs.follows = "nixos-modules/nixpkgs-unstable";
    flake-parts.follows = "nixos-modules/flake-parts";
    git-hooks.follows = "nixos-modules/git-hooks-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem =
        { pkgs, system, ... }:
        let
          isLinux = pkgs.lib.hasSuffix "linux" system;
          preCommit = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              check-added-large-files = {
                enable = true;
                args = [ "--maxkb=1200" ];
              };
              check-merge-conflicts.enable = true;
              lint = {
                enable = true;
                name = "just lint";
                entry = "just lint";
                language = "system";
                pass_filenames = false;
              };
            };
          };
        in
        {
          checks.pre-commit = preCommit;
          devShells.default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                nim
                nimble
                just
                nixfmt-rfc-style
                markdownlint-cli2
                shellcheck
                shfmt
                # EX-M2: the migrated TUI leaves import the full
                # `isonim_tui` module, which transitively pulls the M19
                # tree-sitter FFI (`{.passl: "-ltree-sitter".}`). Provide
                # the runtime library here so leaf-driving tests link.
                tree-sitter
                pkg-config
                # FUH-M5: each per-backend launcher (`build/backends/
                # isonim-examples-{cocoa,gpui,freya,...}`) compiles in
                # the FUH-M5 in-process WebP encoder via the path-
                # imported ``isonim-render-serve`` adapter. The FFI in
                # ``adapters/webp_libwebp_ffi.nim`` resolves
                # ``libwebp.dylib`` / ``libwebp.so.7`` at compile time
                # via ``pkg-config --variable=libdir libwebp`` and
                # bakes the absolute Nix-store path into the
                # ``{.dynlib.}`` pragma — necessary on macOS because
                # SIP strips ``DYLD_FALLBACK_LIBRARY_PATH`` from child
                # processes the editor's Playwright tests spawn.
                # Without ``libwebp`` here the FFI falls back to bare
                # SONAME lookup and the spawned launcher fails with
                # ``[cocoa-webp] could not load: libwebp.dylib``.
                libwebp
                # EX-M14: the demo editor's `just editor-serve` target
                # uses python3's http.server to serve the static bundle
                # on port 8091, and the Playwright spec under
                # `tests/browser/` invokes `npx playwright` for the
                # end-to-end M57 chrome + RS-M7 streaming-preview test.
                python3
                nodejs_22
                # EX-M21 / EX-M23c: `adb` is the host-side bridge to the
                # Android device the launcher (`build/backends/isonim-
                # examples-android`) talks to via `adb exec-out
                # screencap`. The launcher hard-fails (no skip) when
                # adb is missing per the user's real-environment-tests
                # rule, so the dev shell ships it as a first-class
                # dep. Works on both Linux and macOS Apple Silicon.
                android-tools
              ]
              ++ pkgs.lib.optionals isLinux [
                # EX-M3: the GPUI leaves load `libgpui_nim_shim.so` from
                # `../isonim-gpui/rust/target/debug` at run time via
                # `{.dynlib.}`. The shim itself is built in the
                # `isonim-gpui` repo (`just rust-build`). Even in stub
                # mode (no `gpui-backend` feature), the shim has no
                # extra link-time deps, so the only thing this dev shell
                # needs to provide is a search path for the shim. We
                # extend `LD_LIBRARY_PATH` in `shellHook` below.
                #
                # When the shim is built with `--features gpui-backend`,
                # the additional GPU/font/X11/Wayland deps live in the
                # `isonim-gpui` flake — switch into that dev shell when
                # rebuilding the shim with the real GPUI backend.
                #
                # EX-M4: same arrangement for `libfreya_nim_shim.so`.
                # In stub mode (no `freya-backend` Cargo feature), the
                # shim has no extra link-time deps; the additional
                # Skia/WGPU/X11/Wayland deps for full Freya rendering
                # live in the `isonim-freya` flake — switch into that
                # dev shell when rebuilding the shim with the real
                # Freya backend. The shellHook extension below adds
                # `../isonim-freya/rust/target/debug` to the loader
                # search path.
                #
                # EX-M5 (Cocoa): the Cocoa target needs AppKit and the
                # Objective-C runtime, both macOS-only. The Linux dev
                # shell provides nothing here on purpose — the leaves
                # and composition root in `task_app/cocoa/` and
                # `task_app/main_cocoa.nim` are gated `when
                # defined(macosx)` and the cross-compile gate
                # (`tests/test_cocoa_leaves_compile.nim`) drives `nim
                # check --os:macosx` over a Cocoa-only fixture without
                # needing AppKit at compile time. When the macOS
                # engineer ships the macOS-host portion (per the EX-M5
                # status notes' hand-off checklist), they should add a
                # `darwin`-gated branch here that exposes AppKit /
                # Foundation framework search paths if the macOS
                # `nim` toolchain doesn't already pick them up via
                # Xcode's Command Line Tools.
                #
                # EX-M6 (Android): the Android target needs either an
                # Android emulator (real JNI runtime, end-to-end tests)
                # or the in-process MockJNI shim (`-d:mockJni`,
                # host-side smoke tests). The Android emulator runs
                # natively on Apple Silicon — that's why EX-M6 is split
                # the same partial-linux way as EX-M5: the Linux side
                # ships the scaffold + cross-compile gate; the macOS M1
                # engineer runs the emulator-driven integration test.
                # The Linux dev shell provides nothing here on purpose
                # — the leaves and composition root in
                # `task_app/android/` and `task_app/main_android.nim`
                # are gated `when defined(android)` and the
                # cross-compile gate
                # (`tests/test_android_leaves_compile.nim`) drives
                # `nim check --os:android -d:mockJni` over an
                # Android-only fixture without needing the NDK at
                # compile time (the `isonim_android/renderer` Nim
                # module is portable Nim — no `{.passL.}` / `{.emit.}`
                # C blocks — and `mockJni` satisfies the JNI-callbacks
                # error gate). When the macOS engineer ships the
                # emulator-host portion (per the EX-M6 status notes'
                # hand-off checklist), they should add a `darwin`-
                # gated branch here that exposes the Android NDK / SDK
                # paths if the macOS `nim` toolchain doesn't already
                # pick them up via Android Studio.
              ];
            shellHook = ''
              ${preCommit.shellHook}
              # EX-M3: extend LD_LIBRARY_PATH so `nim c -r` driven tests
              # that import `isonim_gpui/renderer` find the shim cdylib.
              # The shim is built once via `cd ../isonim-gpui && just
              # rust-build`; this hook just makes the loader find it.
              if [ -d "$PWD/../isonim-gpui/rust/target/debug" ]; then
                export LD_LIBRARY_PATH="$PWD/../isonim-gpui/rust/target/debug''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              fi
              # EX-M4: same shape for `isonim_freya/renderer`'s shim
              # cdylib (`libfreya_nim_shim.so`). The shim is built once
              # via `cd ../isonim-freya && just rust-build`; this hook
              # just makes the loader find it.
              if [ -d "$PWD/../isonim-freya/rust/target/debug" ]; then
                export LD_LIBRARY_PATH="$PWD/../isonim-freya/rust/target/debug''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              fi
              # FUH-M5: make libwebp.dylib loadable from spawned
              # launcher binaries. macOS strips DYLD_* on SIP-aware
              # binaries; setting it here covers the in-shell direct
              # ``nim c -r`` invocations and the editor-build chain
              # that runs from this shell. The compile-time pkg-
              # config path bake-in in
              # ``isonim-render-serve/.../webp_libwebp_ffi.nim`` is
              # the load-bearing fix for spawn-from-node scenarios.
              ${
                if pkgs.stdenv.isDarwin then
                  ''
                    export DYLD_FALLBACK_LIBRARY_PATH="${pkgs.libwebp}/lib''${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
                  ''
                else
                  ''
                    export LD_LIBRARY_PATH="${pkgs.libwebp}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                  ''
              }
              echo "isonim-examples dev shell - nim $(nim --version 2>&1 | head -1)"
            '';
          };
          packages.default = pkgs.stdenvNoCC.mkDerivation {
            pname = "isonim-examples";
            version = "0.1.0";
            src = ./.;
            installPhase = ''
              mkdir -p $out
              cp -R isonim_examples.nimble README.md LICENSE AGENTS.md $out/
            '';
          };
        };
    };
}
