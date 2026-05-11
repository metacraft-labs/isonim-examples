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
