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

      mkCasks = { pkgs, source }: import ./casks.nix { inherit pkgs source; };

      subdirs = path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
    in
    {
      # Build an attrset of cask packages from a directory containing a cask.json
      # in brew-api's format, e.g. brew-api itself.
      lib.mkCasks = mkCasks;

      # Build one mkCasks attrset per tap from a directory laid out as
      # <user>/<repo>/cask.json, e.g. the taps directory of brew-taps-api.
      lib.mkTaps =
        { pkgs, source }:
        lib.genAttrs (subdirs source) (
          user:
          lib.genAttrs (subdirs "${source}/${user}") (
            repo:
            mkCasks {
              inherit pkgs;
              source = "${source}/${user}/${repo}";
            }
          )
        );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            wget
          ];
        };
      });
    };
}
