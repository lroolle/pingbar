# Research: Stats Network Module Lessons For PingBar

> Status: initial synthesis complete
> Question: What can PingBar learn from Stats.app's network module without blindly copying unsuitable implementation details?
> Started: 2026-05-13
> Last updated: 2026-05-13 09:24 UTC

## Synthesis

Stats is useful as an architecture and product-evidence reference, not as code to port wholesale. Its best ideas are reader separation, path-detail breadth, event-driven reachability refresh, Wi-Fi fallback handling, user-selectable connectivity mode, and split upload/download chart scaling. Its riskiest ideas for PingBar are raw ICMP sockets and shelling out to `nettop`, `curl`, and `system_profiler`, because PingBar is moving toward a stricter sandbox/App Store posture.

The highest-leverage PingBar improvement is not adding more rows to the popup. It is introducing a first-class `NetworkPathSnapshot` and separating `NetworkState` into smaller reader/store units so the app can collect richer evidence without turning the state object into a dump truck.

## Key Findings

1. [direct-evidence] Stats splits network into usage, process, and connectivity readers, then fans callbacks to UI and widgets (`reference/stats/Modules/Net/main.swift:143`, `reference/stats/Modules/Net/main.swift:240`).
2. [direct-evidence] Stats has a reusable reader lifecycle with restore, persistence, callback, intervals, pause/stop, and aligned timers (`reference/stats/Kit/module/reader.swift:86`, `reference/stats/Kit/module/reader.swift:114`, `reference/stats/Kit/module/reader.swift:134`, `reference/stats/Kit/module/reader.swift:175`).
3. [direct-evidence] Stats reads more local path detail than PingBar currently surfaces: DNS servers, local IPs, interface MAC/display/type, Wi-Fi profile fallback, and Wi-Fi event refresh (`reference/stats/Modules/Net/readers.swift:330`, `reference/stats/Modules/Net/readers.swift:350`, `reference/stats/Modules/Net/readers.swift:375`, `reference/stats/Modules/Net/readers.swift:510`).
4. [direct-evidence] Stats supports ICMP and HTTP connectivity modes, but ICMP is raw `CFSocket` code (`reference/stats/Modules/Net/readers.swift:716`, `reference/stats/Modules/Net/readers.swift:1002`).
5. [direct-evidence] Stats' main app is not sandboxed, while PingBar's entitlements file is currently empty; distribution posture needs an explicit decision before copying privileged patterns (`reference/stats/Stats/Supporting Files/Stats.entitlements:4`, `PingBar/Resources/PingBar.entitlements:4`).
6. [inference] PingBar should copy the evidence model and lifecycle ideas before copying raw ICMP or `nettop`.

## Evidence Collected

| Artifact | Type | Location |
|----------|------|----------|
| Stats Net reader | local source | `/Users/eric/wrk/speedtest/reference/stats/Modules/Net/readers.swift` |
| Stats module orchestration | local source | `/Users/eric/wrk/speedtest/reference/stats/Modules/Net/main.swift` |
| Stats reader base | local source | `/Users/eric/wrk/speedtest/reference/stats/Kit/module/reader.swift` |
| Stats charts | local source | `/Users/eric/wrk/speedtest/reference/stats/Kit/plugins/Charts.swift` |
| PingBar network baseline | local source | `/Users/eric/wrk/speedtest/worktree/pingbar/PingBar/Models/NetworkState.swift` |

## Notes

- [Stats Network Module Notes](notes/topics/stats-network.md)
- [Stats vs PingBar Network Comparison](notes/comparisons/stats-vs-pingbar.md)

## Open Questions

See [open_questions.md](open_questions.md).
