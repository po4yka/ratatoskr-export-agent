#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
packager="$repo_root/scripts/distribution/package-app.sh"
verifier="$repo_root/scripts/distribution/verify-app.sh"
entitlements="$repo_root/Distribution/RatatoskrExportAgent.entitlements"
failures=0

run_test() {
  local name=$1
  shift
  if "$@"; then
    echo "ok - $name"
  else
    echo "not ok - $name" >&2
    failures=$((failures + 1))
  fi
}

make_bundle() {
  local fixture_root=$1
  "$packager" \
    --binary /usr/bin/true \
    --output "$fixture_root" \
    --short-version "1.0.0" \
    --build-version "1" >/dev/null
  printf '%s\n' "$fixture_root/Ratatoskr Export Agent.app"
}

assert_release_rejected_for_authority() {
  local app=$1
  local stderr_file=$2
  if "$verifier" --mode signed --app "$app" 2>"$stderr_file"; then
    echo "non-release bundle was accepted" >&2
    return 1
  fi
  grep -q "Developer ID Application" "$stderr_file" \
    && ! grep -q "release-ready\|notarized" "$stderr_file"
}

test_unsigned_bundle_is_not_release_ready() {
  local fixture_root app stderr_file
  fixture_root=$(mktemp -d)
  app=$(make_bundle "$fixture_root")
  stderr_file="$fixture_root/stderr"
  assert_release_rejected_for_authority "$app" "$stderr_file"
  local result=$?
  rm -rf "$fixture_root"
  return "$result"
}

test_ad_hoc_bundle_is_not_release_ready() {
  local fixture_root app stderr_file
  fixture_root=$(mktemp -d)
  app=$(make_bundle "$fixture_root")
  stderr_file="$fixture_root/stderr"
  codesign --force --sign - --entitlements "$entitlements" "$app"
  assert_release_rejected_for_authority "$app" "$stderr_file"
  local result=$?
  rm -rf "$fixture_root"
  return "$result"
}

run_test test_unsigned_bundle_is_not_release_ready test_unsigned_bundle_is_not_release_ready
run_test test_ad_hoc_bundle_is_not_release_ready test_ad_hoc_bundle_is_not_release_ready

exit "$failures"
