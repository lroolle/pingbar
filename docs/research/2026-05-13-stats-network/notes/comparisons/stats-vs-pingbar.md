# Stats vs PingBar Network Comparison

Evidence mode: direct-evidence plus implementation inference.

## What PingBar Already Does Better

PingBar already fixes one Stats weakness: throughput deltas are divided by real elapsed wall-clock time (`PingBar/Readers/ThroughputReader.swift:44`). Stats stores counter deltas as bandwidth values without elapsed-time normalization (`reference/stats/Modules/Net/readers.swift:197`), which assumes stable read cadence.

PingBar's public endpoint reader is also more diagnostic than Stats' public IP reader. PingBar compares no-URL-proxy and system-path sessions and enriches Cloudflare metadata/trace (`PingBar/Readers/PublicIPReader.swift:29`, `PingBar/Readers/PublicIPReader.swift:62`). Stats uses shell `curl` calls against its own IP endpoint (`reference/stats/Modules/Net/readers.swift:456`).

PingBar's latency history preserves packet-loss samples explicitly (`PingBar/Models/NetworkState.swift:169`, `PingBar/Models/NetworkState.swift:180`). Stats' popup connectivity chart stores boolean up/down status separately from averaged latency/jitter (`reference/stats/Modules/Net/popup.swift:612`).

## What Stats Does Better

Stats has clearer reader boundaries. `Network` owns independent usage, process, and connectivity readers (`reference/stats/Modules/Net/main.swift:143`), while PingBar's `NetworkState` owns published data, timers, reader orchestration, warning evaluation, speed-test history, and diagnostic report rendering in one class (`PingBar/Models/NetworkState.swift:17`, `PingBar/Models/NetworkState.swift:72`, `PingBar/Models/NetworkState.swift:140`, `PingBar/Models/NetworkState.swift:221`).

Stats has a reusable reader lifecycle: restored last value, callback persistence, start/pause/stop, interval reset, and aligned timers (`reference/stats/Kit/module/reader.swift:86`, `reference/stats/Kit/module/reader.swift:114`, `reference/stats/Kit/module/reader.swift:134`, `reference/stats/Kit/module/reader.swift:175`). PingBar uses plain timers in `NetworkState` (`PingBar/Models/NetworkState.swift:111`).

Stats supports user-selectable interface override and auto-detection (`reference/stats/Modules/Net/settings.swift:276`). PingBar currently caches primary interface and gateway only (`PingBar/Models/NetworkState.swift:106`).

Stats has a richer active-interface evidence model: display name, BSD name, MAC address, transmit rate, connection type, DNS servers, local IPv4/IPv6, and Wi-Fi standard/security/channel details (`reference/stats/Modules/Net/readers.swift:330`, `reference/stats/Modules/Net/readers.swift:350`, `reference/stats/Modules/Net/readers.swift:375`, `reference/stats/Modules/Net/readers.swift:432`). PingBar has Wi-Fi radio fields but not DNS servers, MAC address, local IP, or user-selected interface in the visible report.

Stats exposes connectivity probe mode and interval in settings (`reference/stats/Modules/Net/settings.swift:230`, `reference/stats/Modules/Net/settings.swift:347`). PingBar has configurable hosts and interval, but the semantic mode is currently HTTP-like `HEAD` only (`PingBar/Readers/PingReader.swift:26`).

## Recommended PingBar Moves

1. Add a `NetworkPathSnapshot` model: active interface display name/BSD name, local IPv4/IPv6, DNS servers, gateway, link speed, Wi-Fi fields, proxy/tunnel trace, direct/system public endpoint. This ports Stats' evidence breadth without copying its UI.
2. Split `NetworkState` into narrower stores/readers: throughput, path details, latency, public endpoint/proxy, speed test/history, and warnings. Do this before adding more network evidence.
3. Add `SCNetworkReachability` or `NWPathMonitor` as an event trigger, not as the source of truth. Use it to force immediate refresh after path changes, while keeping active probes as truth.
4. Improve Wi-Fi SSID fallback. Prefer CoreWLAN profile fallback first; treat `system_profiler` as optional because of launch/sandbox risk.
5. Add a sandbox-aware "top talkers" investigation before implementation. `nettop` can inspire the UX, but it should not be assumed shippable.
6. Keep PingBar's current HTTP-path latency as the default. Raw ICMP is useful for advanced diagnostics, but it creates distribution and privilege questions that need a separate decision.
