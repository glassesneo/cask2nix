{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [ "aarch64-darwin" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Each wraps a file taking the caller's pkgs, which can be imported
      # without this flake or its nixpkgs.

      # Build an attrset of cask packages from a directory containing a cask.json
      # in brew-api's format, e.g. brew-api itself.
      lib.mkCasks = { pkgs, source }: import ./casks.nix { inherit pkgs source; };

      # Build one mkCasks attrset per tap from a directory laid out as
      # <user>/<repo>/cask.json, e.g. the taps directory of brew-taps-api.
      lib.mkTaps = { pkgs, source }: import ./taps.nix { inherit pkgs source; };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            wget
          ];
        };
      });
    };
}
