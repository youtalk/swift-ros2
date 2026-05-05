import Foundation
import Testing

@testable import SwiftROS2Gen

/// Diffs the generator's in-process RIHS01 hashes against the canonical
/// `rosidl_generator_type_description` output bundled inside an
/// `osrf/ros:<distro>-desktop` Docker container.
///
/// The suite is env-gated: when `SWIFT_ROS2_GEN_HASH_ORACLE_IMAGE` is unset
/// (the default for every developer who has not opted in, and for every CI
/// job that does not run on Linux with Docker), every parameterised row
/// short-circuits via `#require(...)` and reports as a skip. Set the env
/// var to `osrf/ros:jazzy-desktop` (or kilted / rolling) to opt in.
@Suite("Hash oracle corpus diff")
struct HashOracleCorpusTests {
    struct Manifest: Decodable {
        let packages: [PackageSpec]
    }

    struct PackageSpec: Decodable, Sendable, CustomStringConvertible {
        let name: String
        let vendor: String
        let types: String
        let distros: [String]
        let excludeTypes: String?

        var description: String { name }
    }

    static let manifest: Manifest = {
        let url = Bundle.module.url(forResource: "expected-corpus", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Manifest.self, from: data)
    }()

    /// Optional per-job override: when `SWIFT_ROS2_GEN_HASH_ORACLE_DISTRO` is
    /// set, every corpus row is scoped to that single distro regardless of
    /// the per-package `distros` list in `expected-corpus.json`. Lets the
    /// kilted / rolling matrix jobs in the hash-oracle workflow reuse the
    /// same corpus file as the jazzy job without per-distro JSON copies.
    /// Treat empty strings the same as unset (matches the
    /// `SWIFT_ROS2_GEN_HASH_ORACLE_IMAGE` gate below).
    static let distroOverride: String? = {
        guard
            let value = ProcessInfo.processInfo.environment[
                "SWIFT_ROS2_GEN_HASH_ORACLE_DISTRO"
            ],
            !value.isEmpty
        else { return nil }
        return value
    }()

    /// Cartesian product of (package, distro). One test row per (package,
    /// distro) pair so a failure surfaces as a discrete row in the test log.
    static let perDistroRows: [(PackageSpec, String)] = manifest.packages.flatMap { pkg in
        let distros = distroOverride.map { [$0] } ?? pkg.distros
        return distros.map { (pkg, $0) }
    }

    static let oracleImage: String? = {
        guard
            let value = ProcessInfo.processInfo.environment[
                "SWIFT_ROS2_GEN_HASH_ORACLE_IMAGE"
            ],
            !value.isEmpty
        else { return nil }
        return value
    }()

    @Test(
        "in-process RIHS01 matches docker oracle",
        .enabled(if: HashOracleCorpusTests.oracleImage != nil),
        arguments: perDistroRows
    )
    func matches(_ row: (pkg: PackageSpec, distro: String)) throws {
        // The `.enabled(if:)` trait above already short-circuits this row
        // when SWIFT_ROS2_GEN_HASH_ORACLE_IMAGE is unset — the assertion
        // here is just defensive against test-runner quirks.
        let image = try #require(Self.oracleImage)
        // Resolve the vendor path against the package root so the test runs
        // identically from `swift test` and from CI's working directory.
        let packageRoot = try resolvePackageRoot()
        let pkgDir = packageRoot.appendingPathComponent(row.pkg.vendor, isDirectory: true)
        let allowList = Set(row.pkg.types.split(separator: ",").map(String.init))
        let denyList: Set<String> =
            row.pkg.excludeTypes
            .map { Set($0.split(separator: ",").map(String.init)) } ?? []
        // Build the cross-package registry by feeding *all* packages from
        // the manifest so nested references (e.g. sensor_msgs/Imu ->
        // std_msgs/Header) resolve. The verify plan is then filtered down
        // to the package under test. When a distro override is in effect
        // (kilted / rolling matrix jobs), every package contributes its
        // IDLs since the on-disk vendor directories are the same regardless
        // of the distro under test — the rosidl JSON files inside the
        // matching docker image provide the per-distro ground truth.
        var runs: [Pipeline.PackageRun] = []
        for spec in Self.manifest.packages
        where Self.distroOverride != nil || spec.distros.contains(row.distro) {
            let dir = packageRoot.appendingPathComponent(spec.vendor, isDirectory: true)
            let specAllow = Set(spec.types.split(separator: ",").map(String.init))
            runs.append(
                .init(
                    input: PackageInput(name: spec.name, directory: dir, distro: row.distro),
                    typesAllowList: specAllow
                ))
        }
        _ = allowList  // already applied via PackageRun above; kept for symmetry.
        _ = pkgDir  // ditto; the per-package run is built in the loop above.

        let plan = try Pipeline.buildVerifyPlan(runs, distros: [row.distro])
        let scopedPlan = plan.filter { entry in
            entry.package == row.pkg.name
                && !denyList.contains(entry.typeName)
                && !denyList.contains(entry.topLevelTypeName)
        }
        let oracle = OracleClient(dockerImage: image)
        let verifier = HashVerifier(oracle: oracle, diagnose: false)
        let report = try verifier.verifyAll(scopedPlan)
        #expect(
            report.mismatches.isEmpty && report.missingFromOracle.isEmpty,
            """
            hash mismatch for \(row.pkg.name) on \(row.distro):
            \(report.summary)
            Reproduce locally:
              swift run swift-ros2-gen \\
                --verify-hashes \(image) \\
                --diagnose \\
                --distros \(row.distro) \\
                --input "\(row.pkg.name)=\(row.pkg.vendor)@\(row.distro)"
            """
        )
    }

    /// Walks up from the test bundle's URL until we find the package root —
    /// the first ancestor directory containing `Package.swift`. Lets the
    /// test run from any cwd (CI's sandbox / Xcode's build dir / a user's
    /// shell) without hard-coding a path.
    private func resolvePackageRoot() throws -> URL {
        var dir = Bundle.module.bundleURL.deletingLastPathComponent()
        for _ in 0..<12 {
            let probe = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: probe.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        // Fall back to cwd — same behaviour as the CLI invocation in CI.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
