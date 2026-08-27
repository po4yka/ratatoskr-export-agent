#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
packager="$repo_root/scripts/distribution/package-app.sh"
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

make_fixture_binary() {
  local path=$1
  printf '#!/bin/sh\nexit 0\n' > "$path"
  chmod 755 "$path"
}

test_package_requires_versions() {
  [[ -x "$packager" ]] || {
    echo "packaging entry point does not exist: $packager" >&2
    return 1
  }

  local fixture_root binary output stderr_file
  fixture_root=$(mktemp -d)
  binary="$fixture_root/RatatoskrExportAgent"
  output="$fixture_root/output"
  stderr_file="$fixture_root/stderr"
  make_fixture_binary "$binary"

  if "$packager" --binary "$binary" --output "$output" 2>"$stderr_file"; then
    echo "packaging unexpectedly accepted missing versions" >&2
    rm -rf "$fixture_root"
    return 1
  fi
  grep -q -- "--short-version" "$stderr_file" && grep -q -- "--build-version" "$stderr_file"
  local result=$?
  rm -rf "$fixture_root"
  return "$result"
}

test_package_builds_expected_bundle() {
  [[ -x "$packager" ]] || {
    echo "packaging entry point does not exist: $packager" >&2
    return 1
  }

  local fixture_root binary output app plist
  fixture_root=$(mktemp -d)
  binary="$fixture_root/RatatoskrExportAgent"
  output="$fixture_root/output"
  app="$output/Ratatoskr Export Agent.app"
  plist="$app/Contents/Info.plist"
  make_fixture_binary "$binary"

  "$packager" \
    --binary "$binary" \
    --output "$output" \
    --short-version "1.2.3" \
    --build-version "42"

  [[ -x "$app/Contents/MacOS/RatatoskrExportAgent" ]] \
    && [[ $(plutil -extract CFBundleIdentifier raw -o - "$plist") == "com.po4yka.ratatoskr.export-agent" ]] \
    && [[ $(plutil -extract CFBundleShortVersionString raw -o - "$plist") == "1.2.3" ]] \
    && [[ $(plutil -extract CFBundleVersion raw -o - "$plist") == "42" ]] \
    && [[ $(plutil -extract LSUIElement raw -o - "$plist") == "true" ]] \
    && [[ $(plutil -extract LSMinimumSystemVersion raw -o - "$plist") == "14.0" ]]
  local result=$?
  rm -rf "$fixture_root"
  return "$result"
}

run_test test_package_requires_versions test_package_requires_versions
run_test test_package_builds_expected_bundle test_package_builds_expected_bundle

exit "$failures"
