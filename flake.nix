{
  description = "Flick: trackpad gestures that snap macOS windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
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
          ];
          shellHook = ''
            if ! xcrun --find swift >/dev/null 2>&1; then
              echo "flick: Xcode command line tools not found, run: xcode-select --install" >&2
            fi
          '';
        };
      });
}
