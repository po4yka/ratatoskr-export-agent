# Export Agent distribution

Ratatoskr Export Agent uses direct distribution as a sandboxed, hardened, Developer ID-signed and Apple-notarized application inside a ZIP archive. The repository can assemble and validate the unsigned bundle locally; only the owner-authorized GitHub Actions workflow may produce an artifact described as notarized.

## Current evidence and blocker

As observed on 2026-08-27:

- local bundle assembly, exact entitlement policy, unsigned/ad hoc rejection, and an ad hoc sandbox smoke launch pass;
- the local login Keychain has no `Developer ID Application` identity;
- the GitHub repository has none of the required Actions secret names configured;
- no owner-authorized `distribution.yml` run, Apple notary submission, stapled application, hosted artifact, or clean-machine installation has been observed.

Notarized-build acceptance is therefore **blocked**, not passed. The exact missing GitHub Actions secrets are:

```text
APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64
APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD
APPLE_NOTARY_KEY_ID
APPLE_NOTARY_ISSUER_ID
APPLE_NOTARY_PRIVATE_KEY_BASE64
```

The owner must supply these Apple account assets:

1. One valid Developer ID Application certificate and its private key, exported together as a password-protected PKCS#12 file. A Developer ID Installer certificate is not needed for the ZIP deliverable.
2. One active App Store Connect API key authorized for the team's notarization submissions: key ID, issuer ID, and original `.p8` private-key bytes.
3. Authority to revoke and replace both assets if either is exposed.

Encode the PKCS#12 and `.p8` bytes as single-line base64 values before saving them as GitHub Actions secrets. Never commit the source files, encoded values, passwords, or decoded temporary material.

## Owner-authorized workflow

After the five secrets are configured and this workflow exists on `main`, dispatch an explicit version:

```bash
gh workflow run distribution.yml \
  --repo po4yka/ratatoskr-export-agent \
  --ref main \
  -f short_version=1.0.0 \
  -f build_version=1 \
  -f source_revision=<full-40-character-commit-sha> \
  -f release_tag=v1.0.0
```

The build job validates the exact source and existing tag before materializing credentials, builds the release executable, runs unsigned distribution tests, imports the identity into an ephemeral Keychain, signs with hardened runtime and a secure timestamp, submits with `notarytool --wait`, staples the accepted ticket, and validates with `stapler`, `codesign`, and Gatekeeper. A separate final job has the only `contents: write` permission: it revalidates source and tag, refuses an existing release, verifies the downloaded ZIP checksum, and creates the immutable GitHub Release with ZIP and SHA-256 assets. Any failed stage prevents publication.

After downloading those assets on a clean Mac, run `scripts/distribution/clean-machine-acceptance.sh <zip> <sha256-sidecar>` and follow its displayed product checklist. This is the required human boundary for first launch, folder authorization, Keychain relaunch, interrupted resume, terminal state, manual update, and rollback.

Required release evidence is the workflow URL, source commit SHA, uploaded ZIP digest, notary submission ID, post-staple validation output, and Gatekeeper result. A successful workflow does not prove clean-machine folder bookmarks, Keychain pairing, or upload behavior; those remain a separate macOS acceptance run.

## Local structure validation

Build through the machine-wide gate, then run the distribution suite:

```bash
build-gate -- swift build -c release
Tests/Distribution/run.sh
```

The resulting ad hoc sandbox smoke bundle is intentionally temporary. `verify-app.sh --mode signed` rejects it because ad hoc signing is not Developer ID release evidence.

## Recovery

If signing material may be compromised, remove the GitHub secret immediately, revoke the affected certificate or API key in the Apple account, retain the impacted workflow and notary submission IDs, and issue a replacement with new owner material. Deleting a workflow run or repository secret does not revoke an already distributed binary or Apple notarization ticket.
