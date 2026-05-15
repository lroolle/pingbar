import Foundation

struct PublicIPProbeResult: Identifiable, Equatable, Sendable {
    var id: String { source }
    let source: String
    let endpoint: PublicEndpointInfo?
    let diagnostic: Bool
    var providerID: String? = nil

    var ip: String? { endpoint?.ip }
}

struct PublicIPEvidence: Equatable, Sendable {
    let probes: [PublicIPProbeResult]

    var primaryEndpoint: PublicEndpointInfo? {
        if let ipinfo = probes.first(where: { $0.source.lowercased().hasPrefix("ipinfo") })?.endpoint {
            return enriched(ipinfo)
        }

        let nonDiagnosticIPs = Set(probes.filter { !$0.diagnostic }.compactMap(\.ip))
        if let enriched = probes.first(where: { probe in
            guard probe.diagnostic, let endpoint = probe.endpoint else { return false }
            return nonDiagnosticIPs.isEmpty || nonDiagnosticIPs.contains(endpoint.ip)
        })?.endpoint {
            return enriched
        }

        if let endpoint = probes.first(where: { !$0.diagnostic && $0.endpoint != nil })?.endpoint {
            return enriched(endpoint)
        }
        return probes.first(where: { $0.endpoint != nil })?.endpoint
    }

    var primaryIP: String? {
        primaryEndpoint?.ip
    }

    var observedIPs: [String] {
        Array(Set(probes.compactMap(\.ip))).sorted()
    }

    var confidence: PublicIPConfidence {
        let nonDiagnosticIPs = Array(Set(probes.filter { !$0.diagnostic }.compactMap(\.ip)))
        if nonDiagnosticIPs.isEmpty {
            return probes.contains(where: { $0.ip != nil }) ? .diagnosticOnly : .noResponse
        }
        if nonDiagnosticIPs.count > 1 { return .mismatch }
        if probes.filter({ !$0.diagnostic && $0.ip != nil }).count >= 2 { return .verified }
        return .singleSource
    }

    private func enriched(_ endpoint: PublicEndpointInfo) -> PublicEndpointInfo {
        var copy = endpoint
        for evidence in probes where evidence.diagnostic {
            guard let diagnostic = evidence.endpoint, diagnostic.ip == endpoint.ip else { continue }
            if copy.city == nil { copy.city = diagnostic.city }
            if copy.region == nil { copy.region = diagnostic.region }
            if copy.country == nil { copy.country = diagnostic.country }
            if copy.asn == nil { copy.asn = diagnostic.asn }
            if copy.organization == nil { copy.organization = diagnostic.organization }
            if copy.colo == nil { copy.colo = diagnostic.colo }
            if copy.warp == nil { copy.warp = diagnostic.warp }
            if copy.gateway == nil { copy.gateway = diagnostic.gateway }
            if copy.httpProtocol == nil { copy.httpProtocol = diagnostic.httpProtocol }
            if copy.traceLocation == nil { copy.traceLocation = diagnostic.traceLocation }
        }
        return copy
    }
}

enum PublicIPConfidence: String, Equatable, Sendable {
    case verified
    case mismatch
    case singleSource
    case diagnosticOnly
    case noResponse

    var label: String {
        switch self {
        case .verified: return "Verified"
        case .mismatch: return "Mismatch"
        case .singleSource: return "Single source"
        case .diagnosticOnly: return "Diagnostic"
        case .noResponse: return "No response"
        }
    }
}

struct EgressRouteResult: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let detail: String?
    let evidence: PublicIPEvidence

    var endpoint: PublicEndpointInfo? { evidence.primaryEndpoint }
    var ip: String? { evidence.primaryIP }
}
