{
  description = "Flick: trackpad gestures that snap macOS windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Sparkle's command-line tools (sign_update, generate_keys). Keep the version equal to the
    # Sparkle package in Package.swift.
    sparkle = {
      url = "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, sparkle, ... }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # Swift, swift-format and sourcekit-lsp come from the installed Xcode, not from nix:
        # nixpkgs' Swift lags behind the macOS 26 SDK. mkShellNoCC keeps nix's compiler
        # wrappers and SDK variables out of the environment so `swift` resolves to Xcode's.
        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            go-task
            swiftlint
            pre-commit
            openssl
            shellcheck
            git-cliff
            gh
            actionlint
            librsvg
          ];
          shellHook = ''
            export PATH="${sparkle}/bin:$PATH"
            if ! xcrun --find swift >/dev/null 2>&1; then
              echo "flick: Xcode command line tools not found, run: xcode-select --install" >&2
            fi
          '';
        };
      });
}
