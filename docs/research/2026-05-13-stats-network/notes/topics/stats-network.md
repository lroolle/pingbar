# Stats Network Module Notes

Evidence mode: direct-evidence from local source.

## Architecture

Stats models network as three readers owned by one `Network` module: `UsageReader`, `ProcessReader`, and `ConnectivityReader` (`reference/stats/Modules/Net/main.swift:137`, `reference/stats/Modules/Net/main.swift:143`). The module fans reader callbacks into popup, portal, notifications, menu bar widgets, text widgets, and system widgets (`reference/stats/Modules/Net/main.swift:240`, `reference/stats/Modules/Net/main.swift:259`, `reference/stats/Modules/Net/main.swift:339`).

The reader base class is a real lifecycle primitive: it restores last values from DB, owns interval startup/pause/stop, writes values back, sends remote updates, and supports aligned timers (`reference/stats/Kit/module/reader.swift:86`, `reference/stats/Kit/module/reader.swift:114`, `reference/stats/Kit/module/reader.swift:134`, `reference/stats/Kit/module/reader.swift:175`, `reference/stats/Kit/module/reader.swift:215`).

## Usage Reader

Stats finds the primary interface from `State:/Network/Global/IPv4` and lets a stored user override select a specific interface (`reference/stats/Modules/Net/readers.swift:116`, `reference/stats/Modules/Net/readers.swift:125`). It reads interface byte counters and link speed with `getifaddrs`, `ifi_obytes`, `ifi_ibytes`, and `ifi_baudrate` (`reference/stats/Modules/Net/readers.swift:224`, `reference/stats/Modules/Net/readers.swift:242`, `reference/stats/Modules/Net/readers.swift:482`).

Stats also exposes a process reader backed by `/usr/bin/nettop` (`reference/stats/Modules/Net/readers.swift:263`, `reference/stats/Modules/Net/readers.swift:570`). Useful product idea: top network consumers. Risk: shelling out to `nettop` is likely a poor fit for a sandbox-first App Store build.

## Network Details

Stats enriches the active interface with display name, BSD name, MAC address, connection type, DNS servers, local IPv4/IPv6, Wi-Fi metadata, public IPv4/IPv6, and country code (`reference/stats/Modules/Net/readers.swift:330`, `reference/stats/Modules/Net/readers.swift:350`, `reference/stats/Modules/Net/readers.swift:432`, `reference/stats/Modules/Net/readers.swift:447`).

The Wi-Fi reader has a fallback path when CoreWLAN does not return SSID: it tries saved network profile data, then `system_profiler SPAirPortDataType -json` (`reference/stats/Modules/Net/readers.swift:375`, `reference/stats/Modules/Net/readers.swift:379`, `reference/stats/Modules/Net/readers.swift:408`). Useful product idea: better SSID fallback. Risk: `system_profiler` is a shell dependency.

Stats listens for Wi-Fi SSID changes through `CWWiFiClient` events and refreshes Wi-Fi details immediately (`reference/stats/Modules/Net/readers.swift:510`, `reference/stats/Modules/Net/readers.swift:523`).

## Connectivity

Stats has two connectivity modes: ICMP and HTTP (`reference/stats/Modules/Net/readers.swift:716`, `reference/stats/Modules/Net/settings.swift:230`). HTTP mode uses a `HEAD` request and computes latency/jitter from elapsed time (`reference/stats/Modules/Net/readers.swift:833`, `reference/stats/Modules/Net/readers.swift:844`). ICMP mode uses a raw `CFSocket` with a UUID fingerprint payload, timeout timer, checksum validation, and jitter smoothing (`reference/stats/Modules/Net/readers.swift:873`, `reference/stats/Modules/Net/readers.swift:901`, `reference/stats/Modules/Net/readers.swift:925`, `reference/stats/Modules/Net/readers.swift:1002`).

Reachability is separated from active latency probes. A `SCNetworkReachability` callback triggers reachable/unreachable closures (`reference/stats/Kit/plugins/Reachability.swift:42`, `reference/stats/Kit/plugins/Reachability.swift:108`). UsageReader uses that to refresh details on reachability and reset usage on unreachable (`reference/stats/Modules/Net/readers.swift:152`).

## Charts

Stats' network chart splits download and upload into two half-height charts with independent scaling, reverse-order support, and speed tooltips (`reference/stats/Kit/plugins/Charts.swift:588`, `reference/stats/Kit/plugins/Charts.swift:600`, `reference/stats/Kit/plugins/Charts.swift:635`). Scaling supports none, square, cube, logarithmic, and fixed modes (`reference/stats/Kit/plugins/Charts.swift:14`). The popup appends live usage samples and keeps separate connectivity history (`reference/stats/Modules/Net/popup.swift:605`, `reference/stats/Modules/Net/popup.swift:612`, `reference/stats/Modules/Net/popup.swift:645`).

## Distribution Constraint

Stats main app entitlements do not enable app sandbox; widgets do (`reference/stats/Stats/Supporting Files/Stats.entitlements:4`, `reference/stats/Widgets/Supporting Files/Widgets.entitlements:5`). That matters because PingBar is aiming at a stricter release posture. Treat raw ICMP, `nettop`, `curl`, and `system_profiler` as optional/non-store paths unless tested against the final distribution target.
