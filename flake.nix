{
  description = "ScrollGate dev shell (xcodegen). Xcode itself comes from the App Store.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          # Xcode itself cannot be packaged (Apple license, signed 10 GB bundle that
          # writes into itself). `xcodes` downloads it from Apple with any Apple ID.
          packages = [ pkgs.xcodegen pkgs.xcodes ];
          shellHook = ''
            if ! xcode-select -p >/dev/null 2>&1 || [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ]; then
              echo "No Xcode found. Install with:  xcodes install --latest && sudo xcodebuild -license accept"
            fi
            echo "Then:  xcodegen generate && open ScrollGate.xcodeproj"
          '';
        };
      });
    };
}
