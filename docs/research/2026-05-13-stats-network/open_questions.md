# Open Questions

## Active (ranked by priority)

1. Can PingBar ship raw ICMP or `nettop`-based per-process traffic while staying in the intended distribution model?
2. Should PingBar add a reusable reader lifecycle abstraction now, or wait until one more reader requires lifecycle complexity?
3. Should PingBar expose user-facing connectivity modes, or keep the product opinionated around URL path evidence and gateway/external targets?

## Resolved

1. Stats' most portable ideas are reader separation, event-driven reachability refresh, Wi-Fi fallback handling, configurable connectivity mode, and split upload/download chart scaling.
2. Stats' least portable ideas are shelling out to `nettop`, `curl`, and `system_profiler`, plus raw ICMP sockets, because they create sandbox and App Store risk for PingBar.
