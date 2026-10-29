# cask2nix

[![test](https://github.com/glassesneo/cask2nix/actions/workflows/test.yml/badge.svg)](https://github.com/glassesneo/cask2nix/actions/workflows/test.yml)

An experimental Nix library that packages macOS [Homebrew Casks](https://brew.sh/) from their JSON data, including casks from third-party taps.

> cask2nix is a fork of [BatteredBunny/brew-nix](https://github.com/BatteredBunny/brew-nix), reworked into a data-agnostic library with third-party tap support. See [Acknowledgements](#acknowledgements).

## Benefits over nix-darwin's homebrew module

1. No homebrew installation needed; packages are fully managed by nix.
2. Pure nix, package derivations; everything is type checked and it will give you an error when you specify an invalid package for example.

## Limitations/Flaws

1. Running most programs with `nix run` won't work, you'll have to build them first.
2. Some programs refuse to run from non-standard locations, since this is automatic there isn't a good way to fix it.
3. There're about 700 casks without hashes, so you have to [override the derivation attributes & provide a hash explicitly](#overriding-casks-derivation-attributes-for-casks-with-no-hash).
4. Having several generations with this will take A LOT of disk space, so keep that in mind.
5. Only `aarch64-darwin` is supported. Intel Macs are not tested.

## Related projects

- [mac-app-util](https://github.com/hraban/mac-app-util)
- [nixcasks](https://github.com/jcszymansk/nixcasks)

# Design

cask2nix is only the mechanism; the cask data comes from elsewhere.

- `cask2nix.lib.mkCasks { pkgs, source }` turns one data source into an attrset of cask packages. `source` is a directory containing a `cask.json`: a JSON array of casks as printed by `brew info --json=v2 --variations`.
- `cask2nix.lib.mkTaps { pkgs, source }` does the same for many taps at once. `source` is a directory laid out as `<user>/<repo>/cask.json`, and the result is an attrset `<user>.<repo>.<cask>`.
- [`brew-api`](https://github.com/BatteredBunny/brew-api) provides `cask.json` for the official `homebrew/cask` tap.
- [`brew-taps-api`](https://github.com/glassesneo/brew-taps-api) generates the `mkTaps` layout for third-party taps.

cask2nix pins no data and provides no overlay. You bind data to it once in your own flake and decide where the packages live.

# Setup

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    cask2nix = {
      url = "github:glassesneo/cask2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, cask2nix, brew-api, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      legacyPackages.${system} = {
        brewCasks = cask2nix.lib.mkCasks {
          inherit pkgs;
          source = brew-api;
        };
      };
    };
}
```

Then reference the packages explicitly wherever you need them:

```nix
let
  brewCasks = self.legacyPackages.${system}.brewCasks;
in
[
  brewCasks.marta
  brewCasks."firefox@developer-edition" # Casks with special characters in their name need to be defined in quotes
]
```

or build them directly:

```bash
nix build .#brewCasks.blender
./result/Applications/Blender.app/Contents/MacOS/Blender
```

`mkCasks` is a plain function, so you can just as well hand its result to modules through `_module.args`, a `let` binding, or an overlay if you prefer.

## Third-party taps

Third-party taps need `brew` to evaluate their Ruby casks, so their data is generated outside of Nix by [`brew-taps-api`](https://github.com/glassesneo/brew-taps-api) or a repository made from it. Add it as a non-flake input and bind its `taps` directory next to `brewCasks`:

```nix
inputs.brew-taps-api = {
  url = "github:glassesneo/brew-taps-api";
  flake = false;
};

legacyPackages.${system} = {
  brewCasks = cask2nix.lib.mkCasks { inherit pkgs; source = brew-api; };
  brewTaps = cask2nix.lib.mkTaps { inherit pkgs; source = "${brew-taps-api}/taps"; };
};
```

```nix
brewTaps.nikitabobko.tap.aerospace
```

cask2nix never merges sources, so tap casks cannot shadow `homebrew/cask` ones unless you merge them yourself.

# Overriding

## Overriding cask's derivation attributes for casks with no hash

Many casks do not come with their hash so you'll have to provide one explicitly.

```nix
(brewCasks.marta.overrideAttrs (oldAttrs: {
  src = pkgs.fetchurl {
    url = builtins.head oldAttrs.src.urls;
    hash = lib.fakeHash; # Replace with actual hash after building once
  };
}))
```

## Overriding cask's variation

Some casks ship different builds per macOS version or architecture. To pick a specific one, override the cask variant chosen.
You can look up each cask's respective variations at [brew.sh](https://brew.sh/).

```nix
brewCasks.visual-studio-code.override { variation = "sequoia"; }
```

## Overriding both cask's variation & derivation attributes

```nix
(brewCasks.visual-studio-code.override { variation = "sequoia"; }).overrideAttrs (oldAttrs: {
  src = pkgs.fetchurl {
    url = lib.lists.head oldAttrs.src.urls;
    hash = lib.fakeHash; # Replace with actual hash after building once
  };
})
```

# Development

[`tests/flake.nix`](tests/flake.nix) binds cask2nix to brew-api and to the tap fixtures in [`tests/fixtures/taps`](tests/fixtures/taps), and serves as the test fixture.

```bash
nix flake check ./tests # evaluate every cask
./test.sh               # build representative casks
```

# Acknowledgements

cask2nix started as a fork of [BatteredBunny/brew-nix](https://github.com/BatteredBunny/brew-nix), and the way it turns casks into derivations comes from there. Many thanks to BatteredBunny and the brew-nix contributors, and to [brew-api](https://github.com/BatteredBunny/brew-api), which keeps the official cask data available to Nix.
