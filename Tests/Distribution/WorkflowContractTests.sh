#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$repo_root/.github/workflows/distribution.yml"
release_script="$repo_root/scripts/distribution/sign-and-notarize.sh"
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

require_pattern() {
  local pattern=$1
  local file=$2
  grep -Eq -- "$pattern" "$file" || {
    echo "missing required pattern '$pattern' in $file" >&2
    return 1
  }
}

test_distribution_workflow_is_fail_closed() {
  [[ -f "$workflow" ]] || {
    echo "distribution workflow does not exist: $workflow" >&2
    return 1
  }
  [[ -x "$release_script" ]] || {
    echo "signing/notarization script does not exist: $release_script" >&2
    return 1
  }

  require_pattern '^  workflow_dispatch:' "$workflow" || return 1
  if grep -Eq '^  (push|pull_request|schedule):' "$workflow"; then
    echo "owner-authorized distribution must be manually triggered" >&2
    return 1
  fi
  require_pattern 'actions/upload-artifact@[0-9a-f]{40}' "$workflow" || return 1
  require_pattern '^      source_revision:' "$workflow" || return 1
  require_pattern '^      release_tag:' "$workflow" || return 1
  require_pattern 'ref:.*inputs\.source_revision' "$workflow" || return 1
  require_pattern 'git rev-parse.*inputs\.source_revision' "$workflow" || return 1
  require_pattern 'git rev-parse.*release_tag' "$workflow" || return 1
  require_pattern 'git cat-file -t.*release_tag' "$workflow" || return 1
  require_pattern '^  release:' "$workflow" || return 1
  require_pattern 'contents: write' "$workflow" || return 1
  require_pattern 'actions/download-artifact@[0-9a-f]{40}' "$workflow" || return 1
  require_pattern 'shasum -a 256 -c' "$workflow" || return 1
  require_pattern 'gh api.*releases/tags' "$workflow" || return 1
  require_pattern 'gh release create' "$workflow" || return 1

  local release_job_line release_create_line
  release_job_line=$(grep -n '^  release:' "$workflow" | cut -d: -f1)
  release_create_line=$(grep -n 'gh release create' "$workflow" | cut -d: -f1)
  [[ "$release_job_line" -lt "$release_create_line" ]] || return 1
  if sed -n "1,$((release_job_line - 1))p" "$workflow" | grep -Eq 'contents: write'; then
    echo "only the final release job may receive contents: write" >&2
    return 1
  fi

  local name
  for name in \
    APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64 \
    APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD \
    APPLE_NOTARY_KEY_ID \
    APPLE_NOTARY_ISSUER_ID \
    APPLE_NOTARY_PRIVATE_KEY_BASE64
  do
    require_pattern "secrets\\.$name" "$workflow" || return 1
  done

  require_pattern 'validate-owner-secrets\.sh' "$release_script" || return 1
  require_pattern 'trap .*cleanup.*EXIT' "$release_script" || return 1
  require_pattern 'security delete-keychain' "$release_script" || return 1
  require_pattern 'openssl pkcs12.*passin env:APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD' "$release_script" || return 1
  if grep -Eq 'security import.*-P' "$release_script"; then
    echo "certificate password must not be passed as a security command-line value" >&2
    return 1
  fi
  require_pattern 'codesign.*--options runtime' "$release_script" || return 1
  require_pattern 'codesign.*--timestamp' "$release_script" || return 1
  require_pattern 'notarytool submit' "$release_script" || return 1
  require_pattern '--wait' "$release_script" || return 1
  require_pattern 'stapler staple' "$release_script" || return 1
  require_pattern '--mode notarized' "$release_script" || return 1

  local validation_line artifact_line
  validation_line=$(grep -n -- '--mode notarized' "$release_script" | tail -1 | cut -d: -f1)
  artifact_line=$(grep -n -- 'final_zip=' "$release_script" | tail -1 | cut -d: -f1)
  [[ "$validation_line" -lt "$artifact_line" ]] || {
    echo "final artifact is created before notarized validation" >&2
    return 1
  }
}

run_test test_distribution_workflow_is_fail_closed test_distribution_workflow_is_fail_closed

exit "$failures"
