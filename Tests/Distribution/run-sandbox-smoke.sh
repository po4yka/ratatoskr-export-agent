#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
binary=""

while (($# > 0)); do
  case "$1" in
    --binary)
      binary=${2:-}
      shift 2
      ;;
    *)
      echo "usage: $0 --binary <release-executable>" >&2
      exit 2
      ;;
  esac
done

[[ -x "$binary" ]] || {
  echo "--binary must name an executable" >&2
  exit 2
}

fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
app=$(
  "$repo_root/scripts/distribution/package-app.sh" \
    --binary "$binary" \
    --output "$fixture_root" \
    --short-version "1.0.0" \
    --build-version "1"
)

"$repo_root/scripts/distribution/verify-app.sh" --mode structure --app "$app"
codesign \
  --force \
  --sign - \
  --options runtime \
  --entitlements "$repo_root/Distribution/RatatoskrExportAgent.entitlements" \
  "$app"
codesign --verify --strict --verbose=2 "$app"

signed_entitlements="$fixture_root/signed-entitlements.plist"
codesign -d --entitlements :- "$app" >"$signed_entitlements" 2>/dev/null
"$repo_root/scripts/distribution/verify-app.sh" \
  --mode entitlements \
  --entitlements "$signed_entitlements"

"$app/Contents/MacOS/RatatoskrExportAgent" --smoke

release_stderr="$fixture_root/release-stderr"
if "$repo_root/scripts/distribution/verify-app.sh" --mode signed --app "$app" 2>"$release_stderr"; then
  echo "ad hoc sandbox smoke bundle unexpectedly qualified as a release" >&2
  exit 1
fi
grep -q "Developer ID Application" "$release_stderr"
