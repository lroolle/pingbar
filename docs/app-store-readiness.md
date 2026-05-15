# PingBar App Store Readiness

PingBar should ship as a utility that explains network quality with evidence, not as a generic speed meter.

## Product Positioning

Name: PingBar

Category: Utilities

Short promise: Menu bar network evidence for Wi-Fi, latency, proxy path, and speed tests.

Subtitle candidates:
- Network evidence in your menu bar
- Wi-Fi and latency monitor
- Diagnose bad network days

## Release Blockers

- Build on a macOS host with `xcodegen` and `xcodebuild`.
- Capture App Store screenshots from the real app, including the menu bar item, popover, pinned window, and copied report.
- Publish a privacy policy URL. App Store Connect requires this for macOS apps.
- Complete App Privacy answers for network requests:
  - Cloudflare speed test and metadata endpoints.
  - Public IP fallback endpoints.
  - No account, no tracking, no sale of data.
- Verify sandbox behavior with `com.apple.security.app-sandbox` and `com.apple.security.network.client`.
- Decide whether public IP geolocation belongs in v1. It is useful, but every external metadata call increases privacy disclosure weight.

## Icon Direction

The current generated app icon reads as "network pulse in the menu bar":

- Rounded macOS tile.
- Dark neutral background.
- Green/cyan sampled latency trace.
- Small signal/status motif.
- Amber accent for degraded path hints.

Source: `PingBar/Resources/Brand/PingBarAppIconSource.png`

Generated slots: `PingBar/Resources/Assets.xcassets/AppIcon.appiconset`

Regenerate with:

```bash
python3 scripts/generate_app_icon.py
```

Avoid:

- Generic Wi-Fi glyph alone.
- Speedometer-only icon.
- Busy charts that collapse at 16 px.

## Source Notes

- Apple documents App Sandbox as required for Mac App Store distribution.
- App Store Connect requires a Privacy Policy URL for macOS apps.
- App icons can be added through an asset catalog or Icon Composer and are uploaded with the build.
