import Foundation

/// Diffs in-process ``RIHS01`` output against the canonical rosidl oracle
/// embedded in `osrf/ros:<distro>-desktop` containers.
///
/// The verifier groups the input plan by `(package, kind, topLevelTypeName,
/// distro)` so it issues exactly one oracle JSON read per IDL source file,
/// then iterates the contained ``VerifyPlanEntry``s and pulls each one's
/// `type_hashes` row out of the cached ``OracleClient/Entry``.
public struct HashVerifier {
    public let oracle: OracleClient
    public let diagnose: Bool

    public init(oracle: OracleClient, diagnose: Bool = false) {
        self.oracle = oracle
        self.diagnose = diagnose
    }

    public struct Mismatch: Sendable {
        public let entry: VerifyPlanEntry
        public let observedHash: String
        public let oracleJSONSource: String
        public let oracleJSON: String
    }

    public struct Report: Sendable {
        public let total: Int
        public let mismatches: [Mismatch]
        public let missingFromOracle: [VerifyPlanEntry]

        public var summary: String {
            if mismatches.isEmpty && missingFromOracle.isEmpty {
                return "hash-oracle: \(total)/\(total) types match\n"
            }
            var s = ""
            if !mismatches.isEmpty {
                s += "hash-oracle: \(mismatches.count)/\(total) MISMATCH(ES):\n"
                for m in mismatches {
                    s += "  - \(m.entry.rosTypeName) (\(m.entry.distro))\n"
                    s += "      expected: \(m.entry.expectedHash)\n"
                    s += "      observed: \(m.observedHash)\n"
                }
            }
            if !missingFromOracle.isEmpty {
                s += "hash-oracle: \(missingFromOracle.count)/\(total) MISSING FROM ORACLE:\n"
                for entry in missingFromOracle {
                    s += "  - \(entry.rosTypeName) (\(entry.distro))\n"
                }
            }
            return s
        }
    }

    public func verifyAll(_ plan: [VerifyPlanEntry]) throws -> Report {
        // Cache one OracleClient.Entry per (package, kind, topLevelTypeName,
        // distro) tuple so each oracle JSON file is read at most once.
        var cache: [String: OracleClient.Entry] = [:]
        var mismatches: [Mismatch] = []
        var missing: [VerifyPlanEntry] = []
        for plannedEntry in plan {
            let cacheKey = [
                plannedEntry.package, plannedEntry.kind.rawValue,
                plannedEntry.topLevelTypeName, plannedEntry.distro,
            ].joined(separator: "|")
            let oracleEntry: OracleClient.Entry
            if let cached = cache[cacheKey] {
                oracleEntry = cached
            } else {
                oracleEntry = try oracle.read(
                    package: plannedEntry.package,
                    kind: plannedEntry.kind,
                    topLevelTypeName: plannedEntry.topLevelTypeName,
                    distro: plannedEntry.distro
                )
                cache[cacheKey] = oracleEntry
            }
            guard let observed = oracleEntry.hashesByROSTypeName[plannedEntry.rosTypeName]
            else {
                missing.append(plannedEntry)
                continue
            }
            if observed != plannedEntry.expectedHash {
                if diagnose {
                    OracleDiagnostic.dumpOnMismatch(
                        entry: plannedEntry,
                        observedHash: observed,
                        oracleJSON: oracleEntry.canonicalJSON
                    )
                }
                let oraclePath = """
                    /opt/ros/\(plannedEntry.distro)/share/\
                    \(plannedEntry.package)/\(plannedEntry.kind.rawValue)/\
                    \(plannedEntry.topLevelTypeName).json
                    """
                mismatches.append(
                    Mismatch(
                        entry: plannedEntry,
                        observedHash: observed,
                        oracleJSONSource: oraclePath,
                        oracleJSON: oracleEntry.canonicalJSON
                    ))
            }
        }
        return Report(
            total: plan.count,
            mismatches: mismatches,
            missingFromOracle: missing
        )
    }
}
