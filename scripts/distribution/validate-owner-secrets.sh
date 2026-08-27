#!/bin/bash
set -euo pipefail

required_names=(
  APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64
  APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
  APPLE_NOTARY_PRIVATE_KEY_BASE64
)
missing_names=()

for name in "${required_names[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing_names+=("$name")
  fi
done

if ((${#missing_names[@]} > 0)); then
  echo "owner-authorized signing is blocked; missing GitHub Actions secrets:" >&2
  for name in "${missing_names[@]}"; do
    printf '  %s\n' "$name" >&2
  done
  exit 1
fi

echo "all required owner secret names are present"
