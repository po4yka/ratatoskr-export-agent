#!/bin/bash
set -euo pipefail

print_checklist() {
  cat <<'EOF'
Clean-machine acceptance checklist
1. Verify the downloaded SHA-256 sidecar, Developer ID signature, notarization ticket, and Gatekeeper acceptance.
2. Launch the app and confirm the status item appears without requesting broad filesystem access.
3. Explicitly choose a disposable inbox folder and confirm no other folder is observed.
4. Pair with a one-time Platform code; confirm no token or provider credential is visible or written to configuration.
5. Quit and relaunch; confirm the paired identity restores from Keychain-backed credentials.
6. Add synthetic ChatGPT and Claude exports, interrupt one upload, relaunch, and confirm the same operation resumes.
7. Confirm terminal import state and a generic notification, then exercise pause, retry, and cancel.
8. Open Check for Updates and confirm it reaches the immutable GitHub Releases page.
9. Roll back by replacing the app with the previously accepted ZIP; confirm journals and managed archives remain intact.
EOF
}

if [[ ${1:-} == "--checklist" ]]; then
  print_checklist
  exit 0
fi

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <RatatoskrExportAgent-version-notarized.zip> <sha256-sidecar>" >&2
  exit 2
fi

artifact=$1
checksum=$2
[[ -f "$artifact" && -f "$checksum" ]] || { echo "artifact or checksum is missing" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/ratatoskr-acceptance.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
cp "$artifact" "$checksum" "$work/"
(cd "$work" && shasum -a 256 -c "$(basename "$checksum")")
ditto -x -k "$work/$(basename "$artifact")" "$work/unpacked"
app=$(find "$work/unpacked" -maxdepth 1 -type d -name '*.app' -print -quit)
[[ -n "$app" ]] || { echo "application bundle is missing" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"
print_checklist
