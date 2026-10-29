#!/usr/bin/env bash
# Run the checks in tests/cask-tests.nix and report each one.
set -uo pipefail
cd "$(dirname "$0")"

tests=./tests#caskTests

listing=$(nix eval --raw "$tests.checks" --apply \
  'checks: builtins.concatStringsSep "" (map (c: c.drv.outPath + "\t" + c.label + "\n") checks)') || exit 1

# Failures are reported with their build logs here; the summary below follows.
nix build --keep-going --no-link --max-jobs "${TEST_JOBS:-4}" "$tests.all"

echo
passed=0
total=0
while IFS=$'\t' read -r out label; do
  total=$((total + 1))
  if [ -e "$out" ]; then
    echo "[PASS] $label"
    passed=$((passed + 1))
  else
    echo "[FAIL] $label"
  fi
done <<<"$listing"

echo
echo "Passed: $passed/$total"
[ "$passed" -eq "$total" ]
