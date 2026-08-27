#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
validator="$repo_root/scripts/distribution/validate-owner-secrets.sh"
secret_names=(
  APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64
  APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
  APPLE_NOTARY_PRIVATE_KEY_BASE64
)
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

without_owner_secrets() {
  env \
    -u APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64 \
    -u APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD \
    -u APPLE_NOTARY_KEY_ID \
    -u APPLE_NOTARY_ISSUER_ID \
    -u APPLE_NOTARY_PRIVATE_KEY_BASE64 \
    "$@"
}

test_missing_secrets_lists_every_name_without_values() {
  [[ -x "$validator" ]] || {
    echo "owner-secret validator does not exist: $validator" >&2
    return 1
  }

  local fixture_root stderr_file canary
  fixture_root=$(mktemp -d)
  stderr_file="$fixture_root/stderr"
  canary="PRIVATE-CERTIFICATE-VALUE-MUST-NOT-APPEAR"
  if without_owner_secrets \
    env APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64="$canary" \
    "$validator" 2>"$stderr_file"; then
    echo "validator unexpectedly accepted an incomplete secret set" >&2
    rm -rf "$fixture_root"
    return 1
  fi

  local name result=0
  for name in "${secret_names[@]:1}"; do
    grep -q "$name" "$stderr_file" || result=1
  done
  grep -q "${secret_names[0]}" "$stderr_file" && result=1
  grep -q "$canary" "$stderr_file" && result=1
  rm -rf "$fixture_root"
  return "$result"
}

test_complete_secret_set_passes() {
  [[ -x "$validator" ]] || {
    echo "owner-secret validator does not exist: $validator" >&2
    return 1
  }

  without_owner_secrets env \
    APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64="fixture-p12" \
    APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD="fixture-password" \
    APPLE_NOTARY_KEY_ID="fixture-key-id" \
    APPLE_NOTARY_ISSUER_ID="fixture-issuer-id" \
    APPLE_NOTARY_PRIVATE_KEY_BASE64="fixture-private-key" \
    "$validator"
}

run_test test_missing_secrets_lists_every_name_without_values test_missing_secrets_lists_every_name_without_values
run_test test_complete_secret_set_passes test_complete_secret_set_passes

exit "$failures"
