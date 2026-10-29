# Checks over representative casks, run by ../test.sh. Each check is a
# derivation that builds only if the check passes, so Nix caches results and
# reruns a check only when its cask or the check itself changes.
{ pkgs, brewCasks }:
let
  inherit (pkgs) lib;

  casks = [
    { kind = "app"; name = "1kc-razer"; } # multi-partition HFS dmg, digit-start token
    { kind = "app"; name = "86box"; } # zip, digit-start token
    { kind = "app"; name = "1password@7"; } # zip, @-versioned token
    { kind = "app"; name = "rectangle"; } # HFS dmg wrapped in a volume-name folder
    { kind = "app"; name = "appcleaner"; } # zip
    { kind = "app"; name = "alfred"; } # tar.gz
    { kind = "app"; name = "ammonite"; } # tar.xz
    { kind = "app"; name = "jumpcut"; } # tar.bz2, universal binary
    { kind = "app"; name = "textmate"; } # tbz
    { kind = "app"; name = "kitty"; } # APFS dmg
    { kind = "app"; name = "sabaki"; } # 7z
    { kind = "app"; name = "raycast"; } # dmg fetched from URL with no archive extension
    { kind = "app"; name = "whatsapp"; } # extensionless zip with nested framework links
    { kind = "pkg"; name = "alfaview"; } # flat pkg
    { kind = "pkg"; name = "aquaskk"; } # flat pkg
    { kind = "pkg"; name = "sage"; } # dmg with both .app and .pkg
    { kind = "pkg"; name = "tailscale-app"; } # pkg with pbzx
    { kind = "binary"; name = "7777"; } # bare Mach-O (no archive extension)
    { kind = "binary"; name = "ngrok"; } # binary inside zip
    { kind = "binary"; name = "fly"; } # binary inside .tgz
    { kind = "binary"; name = "rar"; } # binary inside tar.gz
    { kind = "binary"; name = "matterhorn"; } # binary inside tar.bz2
    { kind = "binary"; name = "aws-vault-binary"; } # binary inside dmg
  ];

  variations = [
    { cask = "vlc"; needle = "arm64"; want = true; }
    { cask = "audacity"; needle = "arm64"; want = true; }
    { cask = "gimp"; needle = "arm64"; want = true; }
    { cask = "visual-studio-code"; needle = "darwin-arm64"; want = true; }
  ];

  mkCheck =
    id: label: script:
    {
      inherit label;
      drv = pkgs.runCommand (lib.strings.sanitizeDerivationName "cask-test-${id}") {
        nativeBuildInputs = [ pkgs.file ];
      } ''
        shopt -s nullglob dotglob
        fail() { echo "$*" >&2; exit 1; }
        # Universal binaries print one extra line per architecture after the summary.
        is_mach_o() { [ "$(file -b --mime-type "$1" | head -n 1)" = application/x-mach-binary ]; }
        ${script}
        touch $out
      '';
    };

  variationCheck =
    { cask, needle, want }:
    let
      url = builtins.tryEval brewCasks.${cask}.src.url;
    in
    mkCheck "url-${cask}" "${cask} url ${if want then "has" else "lacks"} '${needle}'" (
      if !url.success then
        "fail 'failed to evaluate the url'"
      else if lib.strings.hasInfix needle url.value != want then
        "fail ${lib.escapeShellArg "got ${url.value}"}"
      else
        ""
    );

  payloadCheck =
    { kind, name }:
    mkCheck "build-${name}" "${kind} ${name}" (
      if kind == "binary" then
        ''
          bin_dir=${brewCasks.${name}}/bin
          files=()
          for f in "$bin_dir"/*; do [ -f "$f" ] && files+=("$f"); done
          [ ''${#files[@]} -gt 0 ] || fail "no files in $bin_dir"
          for f in "''${files[@]}"; do
            { [ -x "$f" ] && is_mach_o "$f"; } || fail "$f not an executable Mach-O"
          done
        ''
      else
        ''
          store=${brewCasks.${name}}
          bundles=("$store"/Applications/*.app)
          if [ ''${#bundles[@]} -eq 0 ]; then
            ${lib.optionalString (kind == "pkg") ''[ -d "$store/Library" ] ||''} fail "no payload in $store"
          fi
          for bundle in "''${bundles[@]}"; do
            macos=$bundle/Contents/MacOS
            [ -f "$bundle/Contents/Info.plist" ] || fail "missing Info.plist in $bundle"
            [ -d "$macos" ] || fail "missing $macos"
            found=
            for f in "$macos"/*; do
              if [ -f "$f" ] && is_mach_o "$f"; then found=1; break; fi
            done
            [ -n "$found" ] || fail "no Mach-O in $macos"
          done
        ''
    );

  mainProgramCheck =
    { kind, name }:
    let
      cask = brewCasks.${name};
      entry = "bin/${cask.meta.mainProgram}";
    in
    mkCheck "main-program-${name}" "${kind} ${name} mainProgram" ''
      store=${cask}
      ${lib.optionalString (kind == "pkg") ''[ -d "$store/bin" ] || { touch $out; exit 0; }''}
      [ -f "$store/${entry}" ] || fail "${entry} missing"
      [ -x "$store/${entry}" ] || fail "${entry} not executable"
    '';

  checks = map variationCheck variations ++ map payloadCheck casks ++ map mainProgramCheck casks;
in
{
  inherit checks;

  # Builds every check, for `nix build --keep-going`.
  all = pkgs.linkFarm "cask-tests" (
    map (check: {
      inherit (check.drv) name;
      path = check.drv;
    }) checks
  );
}
