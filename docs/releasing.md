# Releasing Tern

Tern copies Sift's reusable delivery structure at `7638e6252fee5b09d2b84a76e1824e146505561e`. Sift itself is unchanged. Legacy DevSweep identities and migration artifacts are omitted. Tern adds Automation entitlements, URL handling, PR CI, shared updater validation, and signing-material cleanup.

## Local builds

`./scripts/build-app.sh release` produces `build/Tern Dev.app` (`com.dominikbura.tern.dev`, version 0.0.0, no updater repository). The optimized compiler configuration does not select the production identity.

A production artifact requires:

```sh
TERN_BUILD_CHANNEL=production \
TERN_VERSION=0.1.1 \
TERN_BUILD_NUMBER=1 \
TERN_UPDATE_REPOSITORY=dominik-bura/tern \
TERN_UNIVERSAL=1 \
./scripts/build-app.sh release
./scripts/verify-bundle.sh build/Tern.app universal
```

`TERN_CODESIGN_IDENTITY` defaults to `-` (ad-hoc). Set it to a Developer ID identity for signed distribution. The helper is signed first; the app gets the hardened runtime and `App/Tern.entitlements`. Both identities carry a Git reference and dirty suffix in metadata. Dev/production preferences and rules are separate.

## GitHub automation

PR CI runs tests, a development bundle build, and bundle verification. The release workflow runs on pushes to main and manual dispatch on `macos-26`, serializes with non-cancelling `tern-release`, and uses pinned checkout v5. It has not run remotely as part of local implementation; no push or release is implied.

Production versions are `0.1.${github.run_number}` and build numbers are `${github.run_number}`. The workflow tests, builds both architectures, verifies app/helper signatures and Automation metadata, packages ZIP/DMG and SHA-256 sidecars, then creates tag `vVERSION` at the checked-out commit with generated notes. Reruns upload replacement assets to the existing release.

All six signing secrets must be present together:

- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

All absent produces an explicitly unsigned/ad-hoc release; a partial set fails. Values are never inherited from Sift or committed. Signed builds import a temporary keychain, notarize/staple the app before the updater ZIP is made, then sign/notarize/staple the DMG and assess Gatekeeper. Signing material is removed in an always-run cleanup step.

## Packaging and update rehearsal

```sh
mkdir -p dist
ditto -c -k --norsrc --keepParent build/Tern.app dist/Tern-0.1.1.zip
./scripts/create-dmg.sh build/Tern.app dist/Tern-0.1.1.dmg
shasum -a 256 dist/Tern-0.1.1.zip > dist/Tern-0.1.1.zip.sha256
shasum -a 256 dist/Tern-0.1.1.dmg > dist/Tern-0.1.1.dmg.sha256
TERN_UPDATE_TEST_APP="$PWD/build/Tern.app" swift test --filter UpdaterIntegrationTests
```

The integration tests copy a production bundle into temporary directories, create and sign a candidate, rehearse replacement and rollback with an injected launcher, and reject tampering before replacement. They do not alter an installed app or launch a browser. The real helper waits up to 30 seconds for its parent, revalidates the candidate after exit, and uses explicit `open` to relaunch. A failed helper writes an update error to Application Support for the next launch.

Recovery: retain the installed app if validation fails. If relaunch fails after replacement, the helper restores the saved `.Tern-previous-UUID.app`. If restoration itself fails, retain that backup and restore it manually. Keep rules in Application Support; an app replacement must not delete them. Restore the previous default browser explicitly in Tern settings if retiring the app.

Before publishing, complete the live matrix, test a downloaded DMG installation, exercise a real same-identity update including Automation consent/default handlers, and check terminal CI results. Developer ID notarization and Gatekeeper acceptance require real signing credentials and remain separate from local ad-hoc validation.

## Homebrew

Every release generates a cask with `scripts/generate-cask.sh` (version, DMG SHA-256, repository, signing mode) and syntax-checks it. The release then updates a tap when both are configured:

- secret `HOMEBREW_TAP_TOKEN`: a fine-grained token with contents write access to the tap repository only
- variable `HOMEBREW_TAP_REPOSITORY`: `dominik-bura/homebrew-tern`

Users then install with `brew tap dominik-bura/tern`, `brew trust dominik-bura/tern` (Homebrew requires trusting third-party taps), and `brew install --cask dominik-bura/tern/tern`. The cask sets `auto_updates true`, because Tern updates itself; Homebrew won't fight the in-app updater. For unsigned releases the cask prints a note after install explaining how to approve Tern on first launch; it never clears the quarantine flag itself. Users who install the DMG directly approve Tern once in System Settings → Privacy & Security.
