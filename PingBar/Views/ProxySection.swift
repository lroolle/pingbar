import SwiftUI

struct ProxySection: View {
    @EnvironmentObject var state: NetworkState
    @State private var refreshRotation = 0.0
    @State private var showAllRoutes = false
    @State private var showEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader("Network", systemImage: "network")
                Spacer()
                Button(action: refreshEgress) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .opacity(state.isRefreshingPublicIPs ? 0.55 : 1)
                            .rotationEffect(.degrees(refreshRotation))
                    }
                    .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(state.isRefreshingPublicIPs)
                .animation(.easeInOut(duration: 0.35), value: refreshRotation)
                .animation(.easeInOut(duration: 0.2), value: state.isRefreshingPublicIPs)
            }

            localLinkSummary
            systemRouteSummary
            publicEgressSummary
            destinationTraceSummary
        }
    }

    private var localLinkSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionEyebrow("Local Link")
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: state.wifiInfo?.ssid == nil ? "network" : "wifi")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.wifiInfo?.ssid == nil ? .secondary : .blue)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(interfaceTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Text(interfaceDetail)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
        }
    }

    private var interfaceTitle: String {
        if let ssid = state.wifiInfo?.ssid {
            return ssid
        }
        if let interface = state.cachedInterfaceLabel ?? state.cachedInterface {
            return interface
        }
        return "Interface unavailable"
    }

    private var interfaceDetail: String {
        var parts: [String] = []
        if state.wifiInfo?.ssid != nil, let interface = state.cachedInterfaceLabel ?? state.cachedInterface {
            parts.append(interface)
        } else if state.cachedInterface != nil {
            parts.append("Wi-Fi name unavailable")
        }
        if let gateway = state.cachedGateway {
            parts.append("Gateway \(gateway)")
        }
        if parts.isEmpty {
            return "Waiting for macOS network details"
        }
        return parts.joined(separator: " · ")
    }

    private var tunnelNote: String? {
        let directWarp = state.directEndpoint?.warp
        let proxyWarp = state.proxyEndpoint?.warp
        if directWarp == "on" || directWarp == "plus" || proxyWarp == "on" || proxyWarp == "plus" {
            return "VPN/TUN egress detected; direct and proxy probes can share one public exit."
        }
        if state.proxyStatus.hasConfiguredProxy, state.directEndpoint?.ip == state.proxyEndpoint?.ip {
            if state.proxyStatus.httpsProbeUsesDirect {
                return "CFNetwork selects DIRECT for the HTTPS public-IP probe."
            }
            return "Same public exit; explicit egress routes show each configured local proxy."
        }
        return nil
    }

    private var systemRouteSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionEyebrow("System Route")
            HStack(spacing: 6) {
                routeDot(color: state.proxyStatus.hasConfiguredProxy ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.proxyStatus.hasConfiguredProxy ? "Proxy configured" : "Direct")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(systemRouteDetail)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private var systemRouteDetail: String {
        if let route = state.proxyStatus.httpsProbeRoute {
            return "HTTPS probe: \(route)"
        }
        return state.proxyStatus.hasConfiguredProxy
            ? state.proxyStatus.configuredProxySummary
            : "macOS system proxy off"
    }

    private var publicEgressSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                sectionEyebrow("Public Egress")
                if state.isRefreshingPublicIPs {
                    Text("refreshing")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if state.egressRoutes.isEmpty {
                Text(state.isRefreshingPublicIPs ? "Checking public egress..." : "No public IP data")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(visibleRoutes) { route in egressRouteRow(route) }
                }

                if !extraRoutes.isEmpty {
                    Button(showAllRoutes ? "Hide proxy routes" : "\(extraRoutes.count) proxy route\(extraRoutes.count == 1 ? "" : "s")") {
                        withAnimation(.easeInOut(duration: 0.16)) { showAllRoutes.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 14)
                }
            }

            if let note = tunnelNote {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8, weight: .semibold))
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var destinationTraceSummary: some View {
        let enabledTargets = state.config.egressTraceTargets.filter(\.enabled)
        if !enabledTargets.isEmpty || !state.egressTraceResults.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                sectionEyebrow("Destination Trace")

                if state.egressTraceResults.isEmpty {
                    Text("Checking destination trace...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(state.egressTraceResults.prefix(3)) { result in
                            destinationTraceRow(result)
                        }
                    }
                }
            }
        }
    }

    private func egressRouteRow(_ route: EgressRouteResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            routeDot(color: routeAccent(route))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(route.label)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if let detail = route.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let ip = route.ip {
                        endpointIdentity(ip: ip, endpoint: route.endpoint)
                    } else {
                        Text("No response")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }

                    statusBadge(for: route)
                }

                if let endpoint = route.endpoint {
                    endpointMetadata(endpoint)
                }
                if shouldShowEvidence(for: route) {
                    routeSources(route)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func destinationTraceRow(_ result: EgressTraceResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            routeDot(color: result.isHealthy ? .blue : .orange)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(result.target.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text(result.target.route.label)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    if let duration = result.durationMs {
                        Text(Fmt.latency(duration))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                if let endpoint = result.endpoint {
                    endpointIdentity(ip: endpoint.ip, endpoint: endpoint)
                    endpointMetadata(endpoint)
                } else {
                    Text(result.error ?? "No response")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func routeSources(_ route: EgressRouteResult) -> some View {
        let sources: [String]
        if route.evidence.confidence == .mismatch {
            sources = route.evidence.probes.map { probe -> String in
                let source = probe.diagnostic ? "\(probe.source) diag" : probe.source
                return "\(source)=\(probe.ip ?? "--")"
            }
        } else {
            sources = route.evidence.probes.map { probe -> String in
                probe.diagnostic ? "\(probe.source) diag" : probe.source
            }
        }
        return Text(sources.isEmpty ? "No evidence" : sources.joined(separator: " · "))
            .font(.system(size: 8))
            .foregroundColor(.secondary.opacity(0.75))
            .lineLimit(1)
    }

    private var primaryRoutes: [EgressRouteResult] {
        state.egressRoutes.filter { $0.id == "no-url-proxy" || $0.id == "system-settings" }
    }

    private var extraRoutes: [EgressRouteResult] {
        state.egressRoutes.filter { route in
            route.id != "no-url-proxy" && route.id != "system-settings"
        }
    }

    private var visibleRoutes: [EgressRouteResult] {
        showAllRoutes ? primaryRoutes + extraRoutes : primaryRoutes
    }

    private func shouldShowEvidence(for route: EgressRouteResult) -> Bool {
        route.evidence.confidence == .mismatch || showEvidence || showAllRoutes && route.evidence.confidence != .verified
    }

    private func statusBadge(for route: EgressRouteResult) -> some View {
        let status = routeStatus(route)
        return Text(status.label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(status.color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.09))
            .cornerRadius(5)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            if title == "Public Egress", !state.egressRoutes.isEmpty {
                Button(showEvidence ? "Hide evidence" : "Evidence") {
                    withAnimation(.easeInOut(duration: 0.16)) { showEvidence.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }

    private func routeDot(color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.82))
            .frame(width: 6, height: 6)
    }

    private func routeAccent(_ route: EgressRouteResult) -> Color {
        if route.ip == nil { return .orange }
        if route.evidence.confidence == .mismatch { return .red }
        if route.id == "no-url-proxy" { return .secondary }
        if route.ip == directRouteIP { return .secondary }
        return .blue
    }

    private func routeStatus(_ route: EgressRouteResult) -> (label: String, color: Color) {
        if route.ip == nil {
            return ("No response", .orange)
        }
        if route.evidence.confidence == .mismatch {
            return ("Mismatch", .red)
        }
        if route.id != "no-url-proxy", route.ip == directRouteIP {
            if route.id == "system-settings", !state.proxyStatus.hasConfiguredProxy {
                return ("Direct", .secondary)
            }
            if route.id == "system-settings", state.proxyStatus.httpsProbeUsesDirect {
                return ("Direct route", .secondary)
            }
            return ("Same egress", .secondary)
        }
        if route.evidence.confidence == .verified {
            return ("Verified", .secondary)
        }
        return (route.evidence.confidence.label, .secondary)
    }

    private var directRouteIP: String? {
        state.egressRoutes.first(where: { $0.id == "no-url-proxy" })?.ip
    }

    private func endpointIdentity(ip: String, endpoint: PublicEndpointInfo?) -> some View {
        HStack(spacing: 5) {
            if let flag = endpoint?.flagEmoji {
                Text(flag)
                    .font(.system(size: 11))
            }
            Text(ip)
                .modifier(InfoValue())
                .textSelection(.enabled)
        }
    }

    private func endpointMetadata(_ endpoint: PublicEndpointInfo) -> some View {
        HStack(spacing: 5) {
            if let country = endpoint.countryCode {
                Text(country)
                    .foregroundColor(.secondary)
            }
            if let warp = endpoint.warpLabel {
                Text(warp)
                    .foregroundColor(warp == "WARP off" ? .secondary : .blue)
            }
            if let gateway = endpoint.gatewayLabel {
                Text(gateway)
                    .foregroundColor(.blue)
            }
            if let http = endpoint.httpProtocol, !http.isEmpty {
                Text(http)
            }
            if let location = endpoint.locationLabel {
                Text(location)
            }
            if let colo = endpoint.colo, !colo.isEmpty {
                Text("CF \(colo)")
            }
            if let network = endpoint.networkLabel {
                Text(network)
            }
            if let source = endpoint.source {
                Text(source)
            }
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }

    private func refreshEgress() {
        refreshRotation += 360
        state.refreshPublicIPs()
        state.refreshEgressTraces()
    }
}
