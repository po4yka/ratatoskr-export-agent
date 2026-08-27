#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
harness="$repo_root/Tests/Distribution/run-sandbox-smoke.sh"
release_binary=${RATATOSKR_RELEASE_BINARY:-"$repo_root/.build/release/RatatoskrExportAgent"}
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

test_ad_hoc_sandbox_bundle_smoke_launches_without_release_claim() {
  [[ -x "$harness" ]] || {
    echo "sandbox smoke harness does not exist: $harness" >&2
    return 1
  }
  [[ -x "$release_binary" ]] || {
    echo "release executable is unavailable: $release_binary" >&2
    return 1
  }
  "$harness" --binary "$release_binary"
}

run_test \
  test_ad_hoc_sandbox_bundle_smoke_launches_without_release_claim \
  test_ad_hoc_sandbox_bundle_smoke_launches_without_release_claim

exit "$failures"
