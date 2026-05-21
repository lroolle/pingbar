# Releasing PingBar

PingBar ships outside the Mac App Store as a Developer ID signed and notarized DMG.

The release path is:

1. Build and test with Xcode 26 on macOS.
2. Archive a universal `arm64 x86_64` app with a Developer ID Application certificate.
3. Export the signed app.
4. Create and sign a DMG containing `PingBar.app` plus an `/Applications` shortcut.
5. Submit the DMG to Apple notarization with `notarytool`.
6. Staple the notarization ticket to the DMG.
7. Upload the DMG and SHA-256 checksum to a GitHub release.

Apple's notarization requirements are strict: use a Developer ID certificate, keep Hardened Runtime enabled, include a secure timestamp, and do not ship `com.apple.security.get-task-allow=true`.

## Local Release

Export or unlock a Developer ID Application certificate in your login keychain, then run:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example LLC (TEAMID)" \
APPLE_TEAM_ID="TEAMID" \
APPLE_ID="apple-id@example.com" \
APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
make release-dmg VERSION=0.2.0
```

The outputs are written to:

```text
build/releases/PingBar-0.2.0.dmg
build/releases/PingBar-0.2.0.dmg.sha256
```

For a private signing-only smoke test, add `SKIP_NOTARIZATION=1`. Do not publish that DMG.

If you prefer a stored notarytool credential, set `NOTARYTOOL_PROFILE` instead of `APPLE_ID` and `APPLE_APP_SPECIFIC_PASSWORD`.

The script builds a universal app by default. Override `ARCHS` only for an internal test build:

```bash
ARCHS=arm64 SKIP_NOTARIZATION=1 make release-dmg VERSION=0.2.0
```

## GitHub Release

The release workflow runs on tag pushes:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Required repository secrets:

```text
APPLE_TEAM_ID
APPLE_ID
APPLE_APP_SPECIFIC_PASSWORD
DEVELOPER_ID_APPLICATION
MACOS_CERTIFICATE_P12
MACOS_CERTIFICATE_PASSWORD
```

`DEVELOPER_ID_APPLICATION` must match the code signing identity name from:

```bash
security find-identity -v -p codesigning
```

Create `MACOS_CERTIFICATE_P12` by exporting the Developer ID Application certificate and private key from Keychain Access as a `.p12`, then base64-encoding it:

```bash
base64 < DeveloperIDApplication.p12 | pbcopy
```

Use the `.p12` export password as `MACOS_CERTIFICATE_PASSWORD`.

## Verification

The packaging script verifies the exported app signature, signs the DMG, notarizes it, staples the ticket, validates stapling, checks Gatekeeper acceptance for the DMG, and writes a SHA-256 checksum.

Useful manual checks:

```bash
codesign --verify --deep --strict --verbose=2 build/release/export/PingBar.app
xcrun stapler validate build/releases/PingBar-0.2.0.dmg
spctl -a -vv --type open build/releases/PingBar-0.2.0.dmg
(cd build/releases && shasum -a 256 -c PingBar-0.2.0.dmg.sha256)
```

## References

- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- GitHub: [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/github-hosted-runners-reference)
