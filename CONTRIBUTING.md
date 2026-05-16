# Contributing to PingBar

PingBar is a native macOS network evidence tool. Contributions should keep the app quiet, local-first, and technically honest.

## Development Setup

```bash
brew install xcodegen
make doctor
make build
make test
```

Use `make run` when you need to test the actual menu bar behavior.

## Contribution Guidelines

- Keep the menu bar signal compact. Put detail in the panel, settings, or diagnostic report.
- Prefer native macOS APIs before shelling out to system tools.
- Treat every external request as part of the privacy surface. Document new probe endpoints in the README.
- Add tests for pure logic. For reader/UI changes, add a focused manual verification note in `docs/devlog/`.
- Do not claim App Store or sandbox readiness unless the exact distribution build has been verified.

## Pull Request Checklist

- [ ] `make test`
- [ ] `make build`
- [ ] README updated if commands, probes, privacy behavior, or screenshots changed
- [ ] Devlog or changelog updated for user-visible behavior

## Code Style

Follow the existing SwiftUI/AppKit split:

- `App/` owns app lifecycle and status item behavior.
- `Models/` owns state and persisted configuration.
- `Readers/` collect evidence from the network or local system.
- `Services/` should stay small and testable.
- `Views/` render state and call narrow actions.

Small, focused PRs are easier to review than broad cleanup.
