#!/bin/bash
set -euo pipefail

mode=""
entitlements=""
app=""

usage() {
  echo "usage: $0 --mode <entitlements|structure|signed|notarized> [--entitlements <path>] [--app <path>]" >&2
}

while (($# > 0)); do
  case "$1" in
    --mode)
      mode=${2:-}
      shift 2
      ;;
    --entitlements)
      entitlements=${2:-}
      shift 2
      ;;
    --app)
      app=${2:-}
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

verify_entitlements() {
  local source=$1
  local allowed_keys=(
    "com.apple.security.app-sandbox"
    "com.apple.security.files.user-selected.read-write"
    "com.apple.security.network.client"
  )
  plutil -lint "$source" >/dev/null

  local key key_path value
  for key in "${allowed_keys[@]}"; do
    key_path=${key//./\\.}
    value=$(plutil -extract "$key_path" raw -o - "$source" 2>/dev/null || true)
    if [[ "$value" != "true" ]]; then
      echo "required entitlement is missing or false: $key" >&2
      return 1
    fi
  done

  local stripped unexpected
  stripped=$(mktemp)
  cp "$source" "$stripped"
  for key in "${allowed_keys[@]}"; do
    key_path=${key//./\\.}
    plutil -remove "$key_path" "$stripped"
  done
  unexpected=$(plutil -p "$stripped" | sed -n 's/.*"\([^"]*\)".*/\1/p' | paste -sd, -)
  rm "$stripped"
  if [[ -n "$unexpected" ]]; then
    echo "unexpected entitlement: $unexpected" >&2
    return 1
  fi
}

plist_value() {
  local plist=$1
  local key=$2
  plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

verify_structure() {
  local bundle=$1
  local plist="$bundle/Contents/Info.plist"
  local executable="$bundle/Contents/MacOS/RatatoskrExportAgent"
  [[ -d "$bundle" ]] || {
    echo "application bundle does not exist" >&2
    return 1
  }
  [[ -f "$plist" && -x "$executable" ]] || {
    echo "application bundle layout is incomplete" >&2
    return 1
  }
  plutil -lint "$plist" >/dev/null
  [[ $(plist_value "$plist" CFBundleIdentifier) == "com.po4yka.ratatoskr.export-agent" ]] || {
    echo "application bundle identifier is invalid" >&2
    return 1
  }
  [[ $(plist_value "$plist" CFBundleExecutable) == "RatatoskrExportAgent" ]] || {
    echo "application executable metadata is invalid" >&2
    return 1
  }
  [[ $(plist_value "$plist" LSUIElement) == "true" ]] || {
    echo "application must use accessory presentation" >&2
    return 1
  }
  [[ $(plist_value "$plist" LSMinimumSystemVersion) == "14.0" ]] || {
    echo "minimum system version must be 14.0" >&2
    return 1
  }
  local short_version build_version
  short_version=$(plist_value "$plist" CFBundleShortVersionString)
  build_version=$(plist_value "$plist" CFBundleVersion)
  [[ "$short_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || {
    echo "application short version is invalid" >&2
    return 1
  }
  [[ "$build_version" =~ ^[1-9][0-9]*$ ]] || {
    echo "application build version is invalid" >&2
    return 1
  }
}

verify_signed() {
  local bundle=$1
  verify_structure "$bundle"

  local details
  if ! details=$(codesign -dvvv "$bundle" 2>&1); then
    echo "release signature must use Developer ID Application; bundle is unsigned" >&2
    return 1
  fi
  grep -q '^Authority=Developer ID Application:' <<<"$details" || {
    echo "release signature must use Developer ID Application" >&2
    return 1
  }
  grep -Eq '^flags=.*runtime' <<<"$details" || {
    echo "Developer ID Application signature is missing hardened runtime" >&2
    return 1
  }
  grep -q '^Timestamp=' <<<"$details" || {
    echo "Developer ID Application signature is missing a secure timestamp" >&2
    return 1
  }
  grep -q '^Identifier=com.po4yka.ratatoskr.export-agent$' <<<"$details" || {
    echo "signed identifier does not match the release bundle" >&2
    return 1
  }
  codesign --verify --strict --verbose=2 "$bundle"

  local signed_entitlements
  signed_entitlements=$(mktemp)
  if ! codesign -d --entitlements :- "$bundle" >"$signed_entitlements" 2>/dev/null; then
    rm "$signed_entitlements"
    echo "signed entitlements could not be read" >&2
    return 1
  fi
  if ! verify_entitlements "$signed_entitlements"; then
    rm "$signed_entitlements"
    return 1
  fi
  rm "$signed_entitlements"
}

verify_notarized() {
  local bundle=$1
  verify_signed "$bundle"
  xcrun stapler validate "$bundle"
  spctl --assess --type execute --verbose=4 "$bundle"
}

case "$mode" in
  entitlements)
    [[ -n "$entitlements" && -f "$entitlements" ]] || {
      echo "--entitlements must name a readable property list" >&2
      exit 2
    }
    verify_entitlements "$entitlements"
    ;;
  structure)
    [[ -n "$app" ]] || {
      echo "--app is required for mode $mode" >&2
      exit 2
    }
    verify_structure "$app"
    ;;
  signed)
    [[ -n "$app" ]] || {
      echo "--app is required for mode $mode" >&2
      exit 2
    }
    verify_signed "$app"
    ;;
  notarized)
    [[ -n "$app" ]] || {
      echo "--app is required for mode $mode" >&2
      exit 2
    }
    verify_notarized "$app"
    ;;
  *)
    usage
    exit 2
    ;;
esac
