#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
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

require_policy_tools() {
  [[ -x "$verifier" ]] || {
    echo "entitlement verifier does not exist: $verifier" >&2
    return 1
  }
  [[ -f "$entitlements" ]] || {
    echo "distribution entitlements do not exist: $entitlements" >&2
    return 1
  }
}

test_entitlements_match_exact_allowlist() {
  require_policy_tools || return 1
  "$verifier" --mode entitlements --entitlements "$entitlements"
}

test_unexpected_entitlement_is_rejected() {
  require_policy_tools || return 1
  local fixture_root fixture stderr_file
  fixture_root=$(mktemp -d)
  fixture="$fixture_root/Unexpected.entitlements"
  stderr_file="$fixture_root/stderr"
  cp "$entitlements" "$fixture"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.security.files.downloads.read-write bool true" \
    "$fixture"

  if "$verifier" --mode entitlements --entitlements "$fixture" 2>"$stderr_file"; then
    echo "unexpected entitlement was accepted" >&2
    rm -rf "$fixture_root"
    return 1
  fi
  grep -q "com.apple.security.files.downloads.read-write" "$stderr_file"
  local result=$?
  rm -rf "$fixture_root"
  return "$result"
}

run_test test_entitlements_match_exact_allowlist test_entitlements_match_exact_allowlist
run_test test_unexpected_entitlement_is_rejected test_unexpected_entitlement_is_rejected

exit "$failures"
