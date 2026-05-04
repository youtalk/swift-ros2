import Foundation

/// On hash-mismatch, dump (a) the canonical JSON the oracle hashed and (b)
/// the in-process generator's expected RIHS01 alongside the observed value
/// under `/tmp/swift-ros2-gen-diagnose/` so a developer can inspect the
/// drift by hand.
///
/// Standard fix workflow:
/// ```
/// less /tmp/swift-ros2-gen-diagnose/<pkg>__<Type>__<distro>.oracle.json
/// ```
/// The diff between the oracle JSON and the generator's IR usually points
/// at the bug in `Sources/SwiftROS2Gen/Hash/RIHS01.swift` (or, for nested
/// types, in IRBuilder's nested-reference materialisation).
public enum OracleDiagnostic {
    public static let dumpRoot = URL(
        fileURLWithPath: "/tmp/swift-ros2-gen-diagnose", isDirectory: true)

    public static func dumpOnMismatch(
        entry: VerifyPlanEntry,
        observedHash: String,
        oracleJSON: String
    ) {
        try? FileManager.default.createDirectory(
            at: dumpRoot, withIntermediateDirectories: true)
        let stem = "\(entry.package)__\(entry.typeName)__\(entry.distro)"
        let oraclePath = dumpRoot.appendingPathComponent("\(stem).oracle.json")
        try? oracleJSON.write(to: oraclePath, atomically: true, encoding: .utf8)
        let summary = """
            // hash-oracle mismatch for \(entry.rosTypeName) (\(entry.distro))
            //   expected RIHS01 (this generator): \(entry.expectedHash)
            //   observed RIHS01 (rosidl oracle):  \(observedHash)
            //
            // The companion `<stem>.oracle.json` file contains the canonical
            // type description rosidl_generator_type_description hashed.
            // Re-run with `swift-ros2-gen --verify-hashes <image> --diagnose`
            // after editing Sources/SwiftROS2Gen/Hash/RIHS01.swift or
            // Sources/SwiftROS2Gen/IR/IRBuilder.swift to confirm the fix.
            """
        let summaryPath = dumpRoot.appendingPathComponent("\(stem).gen.txt")
        try? summary.write(to: summaryPath, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(
            Data("hash-oracle: --diagnose dump for \(stem) at \(dumpRoot.path)\n".utf8))
    }
}
