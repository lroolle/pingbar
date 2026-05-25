<p align="center">
  <img src="PingBar/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="96" alt="PingBar app icon">
</p>

<h1 align="center">PingBar</h1>

<p align="center">
  <strong>Network evidence in your macOS menu bar.</strong>
</p>

<p align="center">
  <a href="https://github.com/lroolle/PingBar/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/lroolle/PingBar/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111111?logo=apple&logoColor=white">
  <img alt="Swift 6 compiler" src="https://img.shields.io/badge/Swift-6%20compiler-F05138?logo=swift&logoColor=white">
  <img alt="Xcode 26" src="https://img.shields.io/badge/Xcode-26-147EFB?logo=xcode&logoColor=white">
  <img alt="XcodeGen" src="https://img.shields.io/badge/project-XcodeGen-147EFB">
  <a href="LICENSE"><img alt="License: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-0E7A5F"></a>
</p>

<p align="center">
  <img src="docs/assets/pingbar-readme-art.png" width="860" alt="Abstract PingBar artwork showing luminous signal paths and latency pulses">
</p>

PingBar is a native macOS menu bar utility for engineers, remote workers, and anyone who needs proof when the network feels wrong. It keeps a compact live signal in the menu bar, then opens into a focused evidence panel with throughput, latency, Wi-Fi radio quality, proxy/egress routes, process traffic, and native Cloudflare speed tests.

Most network meters stop at "up" and "down." PingBar is built for the next question: is this the Wi-Fi, the gateway, the proxy, the VPN path, a busy app, or the internet?

> Status: early source-first macOS app. Signed DMG releases are built from tags once Developer ID signing secrets are configured.

## Why PingBar

| Signal | What it answers |
| --- | --- |
| Menu bar health + throughput | Is the network busy or degraded right now? |
| Gateway and external latency | Is the problem local Wi-Fi/router latency or upstream internet latency? |
| Wi-Fi radio details | Is RSSI, SNR, channel, band, or link rate the likely cause? |
| Public egress comparison | Does the system path differ from a no-URL-proxy path? |
| Proxy route probes | Which configured HTTP/SOCKS route is actually active? |
| Top network processes | Which local apps are currently moving traffic? |
| Cloudflare speed test | What are the current latency, jitter, download, and upload numbers? |
| Copyable report | Can you send IT/support evidence instead of a vague complaint? |

## Quick Start

Requirements:

- macOS 13 or newer
- Xcode 26 or newer. Xcode 26.5 is the current recommended baseline.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/lroolle/PingBar.git
cd PingBar
brew install xcodegen
make doctor
make run
```

PingBar starts as a menu bar app. Left-click the menu bar item for the evidence panel. Right-click for actions such as pinning the window, opening settings, or quitting.

## What It Shows

```text
● ↑128KB/s ↓4.8MB/s
```

The menu bar item is intentionally small: live upload/download, optional health dot, and selectable compact, detailed, stacked, or icon-only display styles.

Open the panel for the full picture:

- **Throughput:** upload/download history with stable menu bar sampling.
- **Latency:** gateway plus configurable external hosts, packet loss, jitter, and recent history.
- **Wi-Fi:** SSID, BSSID, channel, band, width, PHY mode, RSSI, noise, SNR, transmit rate, and quality.
- **Egress:** direct/no-URL-proxy path, system route, configured proxy probes, Cloudflare metadata, WARP/Gateway hints, and IP evidence confidence.
- **Speed test:** quick, standard, and thorough native Cloudflare presets with optional no-proxy mode.
- **Process traffic:** top local network talkers using macOS process evidence.
- **Report:** one-click diagnostic report for support tickets, office Wi-Fi debugging, or before/after comparisons.

## Example Report

```text
PingBar Network Evidence Report
Generated: 2026-05-15T09:00:00Z

== Summary ==
  Health: Degraded
  Wi-Fi: Office-5G
  Interface: Wi-Fi
  Public IP: system proxy differs (203.0.113.10 -> 198.51.100.20)

== Latency Evidence ==
  Gateway (192.168.1.1)
    Last: 42.5 ms  Avg: 38.2 ms  Jitter: 8.1ms  Loss: 0%

== Last Speed Test ==
  Server: SJC (San Jose, US)
  Latency: 24.0 ms
  Download: 238.4 Mbps
  Upload:   31.7 Mbps
```

## Privacy And Network Behavior

PingBar has no account system, analytics SDK, or product telemetry. It reads local network state and makes the network probes needed for the diagnostics you enable.

Default external requests may include:

- Cloudflare speed test, metadata, and trace endpoints.
- ipify and AWS public-IP endpoints.
- Optional IPinfo endpoints when you add an IPinfo token.
- Application probe URLs you configure in settings.

Current developer builds also use local macOS tools for some evidence paths (`/sbin/ping`, `/sbin/ping6`, and `/usr/bin/nettop`). That is useful for diagnostics, but it is also why signed distribution and App Store sandbox hardening are tracked separately before a packaged release.

## Development

```bash
make doctor    # Print the selected Xcode, Swift compiler, and macOS SDK
make project   # Generate PingBar.xcodeproj from project.yml
make build     # Build Debug app into ./build
make test      # Run XCTest coverage for the pure core logic
make run       # Build and launch PingBar
make ci        # Local equivalent of the GitHub Actions build/test path
make release-dmg VERSION=0.2.0
make clean
```

CI runs the same generated Xcode project on macOS 26 with XcodeGen. The project uses the active Xcode macOS SDK (`SDKROOT = macosx`), the Swift 6 compiler, and Swift 5 language mode with complete strict-concurrency checking enabled as the migration bridge before flipping to Swift 6 language mode.

Release packaging is documented in [docs/releasing.md](docs/releasing.md).

## Project Structure

```text
PingBar/
  App/                         NSStatusBar, popover, settings window lifecycle
  Models/                      Network state, config, history, warning models
  Readers/                     Throughput, latency, Wi-Fi, proxy, public IP, speed test
  Services/                    Formatting and warning evaluation
  Views/                       SwiftUI menu bar panel, graphs, sections, settings
  Resources/                   Info.plist, entitlements, app icon assets
PingBarTests/                  Focused XCTest coverage for pure core logic
docs/
  app-store-readiness.md       Release hardening notes
  devlog/                      Decision history and implementation notes
  research/                    Network-monitoring references and comparisons
project.yml                    XcodeGen project definition
Makefile                       Local build/test/run shortcuts
```

## Roadmap

- Notarized release smoke test on a clean macOS account.
- Screenshots and short usage demo captured from the real app.
- More XCTest coverage around readers and route evidence parsing.
- Sandbox/App Store review of `ping` and `nettop`-based diagnostics.
- Clear privacy policy for packaged distribution.

## Contributing

Contributions should keep PingBar native, quiet, and evidence-first. Before opening a PR:

1. Run `make test`.
2. Run `make build` on a macOS host.
3. Update the README or devlog when behavior, probes, privacy surface, or release posture changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor notes.

## License

Apache License 2.0. See [LICENSE](LICENSE).
