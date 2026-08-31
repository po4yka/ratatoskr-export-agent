#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
binary=""
output=""
short_version=""
build_version=""
work_root=""
keychain_path=""

usage() {
  echo "usage: $0 --binary <path> --output <directory> --short-version <version> --build-version <number>" >&2
}

cleanup() {
  if [[ -n "$keychain_path" ]]; then
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  fi
  if [[ -n "$work_root" && -d "$work_root" ]]; then
    rm -rf "$work_root"
  fi
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --binary)
      binary=${2:-}
      shift 2
      ;;
    --output)
      output=${2:-}
      shift 2
      ;;
    --short-version)
      short_version=${2:-}
      shift 2
      ;;
    --build-version)
      build_version=${2:-}
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$binary" || -z "$output" || -z "$short_version" || -z "$build_version" ]]; then
  usage
  exit 2
fi

"$repo_root/scripts/distribution/validate-owner-secrets.sh"

mkdir -p "$output"
work_root=$(mktemp -d "$output/.notarize.XXXXXX")
keychain_path="$work_root/signing.keychain-db"
p12_path="$work_root/developer-id.p12"
identity_pem="$work_root/developer-id.pem"
notary_key="$work_root/AuthKey_${APPLE_NOTARY_KEY_ID}.p8"
notary_response="$work_root/notary-response.json"
notary_log="$work_root/notary-log.json"
bundle_output="$work_root/bundle"
pre_notary_zip="$work_root/RatatoskrExportAgent-pre-notary.zip"

printf '%s' "$APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64" | /usr/bin/base64 -D > "$p12_path"
printf '%s' "$APPLE_NOTARY_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$notary_key"
chmod 600 "$p12_path" "$notary_key"
openssl pkcs12 -in "$p12_path" -passin env:APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD -nodes -out "$identity_pem"
chmod 600 "$identity_pem"

keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$identity_pem" -k "$keychain_path" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path"

identities=$(security find-identity -v -p codesigning "$keychain_path" | grep '"Developer ID Application:' || true)
identity_count=$(grep -c '"Developer ID Application:' <<<"$identities" || true)
if [[ "$identity_count" -ne 1 ]]; then
  echo "the PKCS#12 must contain exactly one valid Developer ID Application identity" >&2
  exit 1
fi
identity=$(sed -E 's/.*"([^"]+)".*/\1/' <<<"$identities")

app=$(
  "$repo_root/scripts/distribution/package-app.sh" \
    --binary "$binary" \
    --output "$bundle_output" \
    --short-version "$short_version" \
    --build-version "$build_version"
)
"$repo_root/scripts/distribution/verify-app.sh" --mode structure --app "$app"
codesign --force --sign "$identity" --keychain "$keychain_path" --options runtime --timestamp --entitlements "$repo_root/Distribution/RatatoskrExportAgent.entitlements" "$app"
"$repo_root/scripts/distribution/verify-app.sh" --mode signed --app "$app"

ditto -c -k --keepParent "$app" "$pre_notary_zip"
xcrun notarytool submit "$pre_notary_zip" --key "$notary_key" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --output-format json > "$notary_response"
notary_status=$(plutil -extract status raw -o - "$notary_response" 2>/dev/null || true)
submission_id=$(plutil -extract id raw -o - "$notary_response" 2>/dev/null || true)
if [[ "$notary_status" != "Accepted" || -z "$submission_id" ]]; then
  echo "Apple notarization did not return Accepted status" >&2
  exit 1
fi
xcrun notarytool log "$submission_id" --key "$notary_key" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" "$notary_log" >/dev/null
echo "notary submission accepted: $submission_id"

xcrun stapler staple "$app"
xcrun stapler validate "$app"
"$repo_root/scripts/distribution/verify-app.sh" --mode notarized --app "$app"

final_zip="$output/RatatoskrExportAgent-$short_version-notarized.zip"
[[ ! -e "$final_zip" ]] || {
  echo "refusing to overwrite an existing distribution artifact" >&2
  exit 1
}
ditto -c -k --keepParent "$app" "$final_zip"
(cd "$output" && shasum -a 256 "$(basename "$final_zip")" > "$(basename "$final_zip").sha256")
printf 'notarized artifact: %s\nchecksum: %s\n' "$final_zip" "$final_zip.sha256"
