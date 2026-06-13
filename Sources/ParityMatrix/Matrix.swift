import Foundation

/// Per-backend support level for a capability row.
public enum BackendStatus: String, Codable, Sendable {
    case supported
    case partial
    case missing
    case notApplicable = "n-a"
    case pending
}

/// Gap severity for a capability the RCL backend does not yet fully match.
public enum Severity: String, Codable, Sendable {
    case blocker
    case major
    case minor
    case notApplicableByDesign = "n-a-by-design"
    case pending
}

/// Verdict for one verification axis.
public enum AxisVerdict: String, Codable, Sendable {
    case pass
    case fail
    case pending
}

/// One verification-axis result: a verdict plus an optional free-form measured value.
public struct AxisResult: Codable, Sendable, Equatable {
    public var verdict: AxisVerdict
    public var value: String?

    public init(verdict: AxisVerdict = .pending, value: String? = nil) {
        self.verdict = verdict
        self.value = value
    }
}

/// The four verification axes from the design (§5).
public struct Verification: Codable, Sendable, Equatable {
    public var latency: AxisResult
    public var soak: AxisResult
    public var correctness: AxisResult
    public var resource: AxisResult

    public init(
        latency: AxisResult = .init(),
        soak: AxisResult = .init(),
        correctness: AxisResult = .init(),
        resource: AxisResult = .init()
    ) {
        self.latency = latency
        self.soak = soak
        self.correctness = correctness
        self.resource = resource
    }
}

/// One public-API capability row.
public struct Capability: Codable, Sendable {
    public var id: String
    public var apiSymbol: String
    public var pureSwift: BackendStatus
    public var rcl: BackendStatus
    public var platforms: [String]
    public var typeApplicability: String
    public var severity: Severity
    public var verification: Verification
    public var evidence: String?
}

/// The whole parity matrix — source of truth for `docs/parity-matrix.json`.
public struct ParityMatrix: Codable, Sendable {
    public var schemaVersion: Int
    public var capabilities: [Capability]

    public init(schemaVersion: Int, capabilities: [Capability]) {
        self.schemaVersion = schemaVersion
        self.capabilities = capabilities
    }
}
