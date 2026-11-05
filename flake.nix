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
          packages = [ pkgs.xcodegen ];
          shellHook = ''
            echo "xcodegen $(xcodegen --version 2>/dev/null)  —  run: xcodegen generate && open ScrollGate.xcodeproj"
          '';
        };
      });
    };
}
