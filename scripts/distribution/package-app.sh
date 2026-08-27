#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
binary=""
output=""
short_version=""
build_version=""

usage() {
  echo "usage: $0 --binary <path> --output <directory> --short-version <version> --build-version <number>" >&2
}

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

if [[ ! -f "$binary" || ! -x "$binary" ]]; then
  echo "release executable is missing or not executable" >&2
  exit 1
fi

if [[ ! "$short_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "--short-version must contain two or three numeric components" >&2
  exit 2
fi

if [[ ! "$build_version" =~ ^[1-9][0-9]*$ ]]; then
  echo "--build-version must be a positive integer" >&2
  exit 2
fi

app_path="$output/Ratatoskr Export Agent.app"
if [[ -e "$app_path" ]]; then
  echo "refusing to overwrite an existing application bundle" >&2
  exit 1
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
install -m 755 "$binary" "$app_path/Contents/MacOS/RatatoskrExportAgent"
sed \
  -e "s/__SHORT_VERSION__/$short_version/g" \
  -e "s/__BUILD_VERSION__/$build_version/g" \
  "$repo_root/Distribution/Info.plist.template" > "$app_path/Contents/Info.plist"
plutil -lint "$app_path/Contents/Info.plist" >/dev/null

printf '%s\n' "$app_path"
