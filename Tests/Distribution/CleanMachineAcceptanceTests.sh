#!/bin/bash
set -u -o pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/distribution/clean-machine-acceptance.sh"

[[ -x "$script" ]] || { echo "clean-machine acceptance script must be executable" >&2; exit 1; }
grep -q '^set -euo pipefail$' "$script" || exit 1
for phrase in Gatekeeper 'Explicitly choose' 'one-time Platform code' 'Quit and relaunch' \
  'same operation resumes' 'terminal import state' 'Check for Updates' 'Roll back'
do
  "$script" --checklist | grep -q "$phrase" || {
    echo "acceptance checklist is missing: $phrase" >&2
    exit 1
  }
done
if grep -Eq 'APPLE_|security (import|delete-keychain)|gh release create|notarytool submit' "$script"; then
  echo "clean-machine acceptance must not consume signing, publishing, or owner credentials" >&2
  exit 1
fi
echo "ok - clean-machine acceptance is complete and non-publishing"
