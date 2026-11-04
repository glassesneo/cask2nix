# Build one mkCasks attrset per tap from a directory laid out as
# <user>/<repo>/cask.json, e.g. the taps directory of brew-taps-api.
{ pkgs, source }:
let
  inherit (pkgs) lib;
  subdirs =
    path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
in
lib.genAttrs (subdirs source) (
  user:
  lib.genAttrs (subdirs "${source}/${user}") (
    repo:
    import ./casks.nix {
      inherit pkgs;
      source = "${source}/${user}/${repo}";
    }
  )
)
