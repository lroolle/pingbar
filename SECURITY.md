# Security Policy

PingBar has no account system, analytics SDK, or product telemetry. Its main security and privacy surface is local network inspection plus configured diagnostic probes.

## Reporting Issues

Please use GitHub Security Advisories when available. If that is not available, open an issue with enough detail to reproduce the problem and avoid posting private IP addresses, Wi-Fi names, proxy credentials, or full diagnostic reports publicly.

Useful reports include:

- Unexpected external requests.
- Sensitive data appearing in diagnostic reports.
- Unsafe handling of proxy credentials or IPinfo tokens.
- App sandbox, signing, or launch-at-login security issues.

## Supported Versions

PingBar is pre-1.0. Security fixes land on `main` until tagged releases exist.
