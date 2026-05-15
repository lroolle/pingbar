# Evidence Registry

| # | Type | Slug | Source | Date | Relevance |
|---|------|------|--------|------|-----------|
| 1 | local-source | stats-net-reader | `/Users/eric/wrk/speedtest/reference/stats/Modules/Net/readers.swift` | 2026-05-13 | Primary implementation evidence for usage, process, Wi-Fi, public IP, reachability, and ICMP/HTTP connectivity readers. |
| 2 | local-source | stats-network-module | `/Users/eric/wrk/speedtest/reference/stats/Modules/Net/main.swift` | 2026-05-13 | Primary evidence for module orchestration, reader fan-out, widget/text templating, and background scheduling. |
| 3 | local-source | stats-reader-base | `/Users/eric/wrk/speedtest/reference/stats/Kit/module/reader.swift` | 2026-05-13 | Primary evidence for reusable reader lifecycle, persistence, intervals, lock/popup behavior, and aligned timers. |
| 4 | local-source | stats-network-chart | `/Users/eric/wrk/speedtest/reference/stats/Kit/plugins/Charts.swift` and `/Users/eric/wrk/speedtest/reference/stats/Kit/Widgets/NetworkChart.swift` | 2026-05-13 | Primary evidence for split upload/download charting, scaling modes, and menu bar chart mechanics. |
| 5 | local-source | stats-reachability | `/Users/eric/wrk/speedtest/reference/stats/Kit/plugins/Reachability.swift` | 2026-05-13 | Primary evidence for SCNetworkReachability callback handling. |
| 6 | local-source | pingbar-network-state | `/Users/eric/wrk/speedtest/worktree/pingbar/PingBar/Models/NetworkState.swift` | 2026-05-13 | Current PingBar network orchestration baseline. |
| 7 | local-source | pingbar-readers | `/Users/eric/wrk/speedtest/worktree/pingbar/PingBar/Readers` | 2026-05-13 | Current PingBar throughput, ping, Wi-Fi, proxy, public endpoint, and speed-test reader baseline. |
