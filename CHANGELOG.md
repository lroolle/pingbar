# Changelog

All notable changes to PingBar will be documented here.

## Unreleased

- Added an OSS-ready README with quick start, privacy notes, project structure, roadmap, and contributor guidance.
- Added CI/test scaffolding for the generated Xcode project.
- Added initial XCTest coverage for formatting, latency state, and warning evaluation logic.
- Fixed default IPinfo providers to use the legacy JSON endpoints supported by standard IPinfo tokens.
- Moved built-in public-IP providers and compatibility normalization into a provider catalog.
- Removed undersized SwiftUI progress indicators that triggered AppKit layout warnings.

## 0.1.0

- Initial native macOS menu bar app.
- Added live throughput, latency targets, Wi-Fi evidence, proxy/egress checks, Cloudflare speed tests, history, warnings, settings, and copyable diagnostic reports.
