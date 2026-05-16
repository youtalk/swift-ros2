import Foundation

/// Reads canonical `type_description` JSON files out of an
/// `osrf/ros:<distro>-desktop` container so the in-process
/// ``RIHS01/hash(_:registry:)`` output can be diffed against the
/// rosidl-authored ground truth.
///
/// Design choice: we read
/// `/opt/ros/<distro>/share/<pkg>/{msg,srv,action}/<TopLevelType>.json`
/// directly out of the container rather than scraping
/// `ros2 interface show --type-description-hashes`. The JSON file is the
/// raw output of `rosidl_generator_type_description` at package-build time
/// and contains a `type_hashes` array with one entry per type that the IDL
/// references (the top-level type plus, for `.srv` / `.action`, every
/// generated sub-type and every transitive dependency). One `docker run`
/// per IDL file therefore covers every sub-type in that file, which is
/// dramatically faster than spinning up `ros2 interface show` per type.
public struct OracleClient: Sendable {
    public let dockerImage: String

    public init(dockerImage: String) {
        self.dockerImage = dockerImage
    }

    /// Parsed contents of a single rosidl `<TopLevelType>.json` file.
    public struct Entry: Sendable {
        public let package: String  // "example_interfaces"
        public let kind: MessageKind  // .msg / .srv / .action
        public let topLevelTypeName: String  // "Fibonacci"
        public let canonicalJSON: String  // raw bytes of `<TopLevelType>.json`
        /// `type_name` -> `RIHS01_<sha256>` for every entry in `type_hashes`.
        public let hashesByROSTypeName: [String: String]

        public init(
            package: String,
            kind: MessageKind,
            topLevelTypeName: String,
            canonicalJSON: String,
            hashesByROSTypeName: [String: String]
        ) {
            self.package = package
            self.kind = kind
            self.topLevelTypeName = topLevelTypeName
            self.canonicalJSON = canonicalJSON
            self.hashesByROSTypeName = hashesByROSTypeName
        }
    }

    /// Reads the JSON for one top-level ROS 2 IDL file from the container.
    /// `kind` selects between `share/<pkg>/{msg,srv,action}/<typeName>.json`.
    public func read(
        package: String,
        kind: MessageKind,
        topLevelTypeName: String,
        distro: String
    ) throws -> Entry {
        let path =
            "/opt/ros/\(distro)/share/\(package)/\(kind.rawValue)/\(topLevelTypeName).json"
        let raw = try runDocker(arguments: ["cat", path])
        let hashes = try Self.extractHashes(from: raw, source: path)
        return Entry(
            package: package,
            kind: kind,
            topLevelTypeName: topLevelTypeName,
            canonicalJSON: raw,
            hashesByROSTypeName: hashes
        )
    }

    public enum OracleError: Error, CustomStringConvertible {
        case dockerNotInstalled
        case dockerExitNonZero(Int32, stderr: String, command: String)
        case missingTypeHashes(path: String, body: String)

        public var description: String {
            switch self {
            case .dockerNotInstalled:
                return "docker not found on PATH; install Docker or skip --verify-hashes"
            case .dockerExitNonZero(let code, let err, let cmd):
                return "docker (\(cmd)) exited \(code): \(err)"
            case .missingTypeHashes(let path, let body):
                let prefix = String(body.prefix(200))
                return "no parseable 'type_hashes' array in \(path); body=\(prefix)..."
            }
        }
    }

    private func runDocker(arguments: [String]) throws -> String {
        #if os(macOS) || os(Linux) || os(Windows)
            let process = Process()
            // POSIX hosts: shell out via `/usr/bin/env docker` so a developer
            // who installed Docker in a non-standard location (Homebrew,
            // CoreOS, etc.) still gets PATH lookup. Windows hosts don't have
            // `/usr/bin/env`, so resolve the bare `docker.exe` and let the OS
            // PATH search find it. The Verify family is part of the Windows
            // build graph (Zenoh-only target builds it as a dependency of
            // SwiftROS2Gen) so the `#if os(Windows)` branch matters even
            // though no Windows CI job exercises the verifier today.
            #if os(Windows)
                process.executableURL = URL(fileURLWithPath: "docker.exe")
                process.arguments = ["run", "--rm", dockerImage] + arguments
                let cmdPrefix = ["docker.exe", "run", "--rm", dockerImage]
            #else
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["docker", "run", "--rm", dockerImage] + arguments
                let cmdPrefix = ["docker", "run", "--rm", dockerImage]
            #endif
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                throw OracleError.dockerNotInstalled
            }
            process.waitUntilExit()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let cmd = (cmdPrefix + arguments).joined(separator: " ")
                throw OracleError.dockerExitNonZero(
                    process.terminationStatus, stderr: stderr, command: cmd)
            }
            return String(data: outData, encoding: .utf8) ?? ""
        #else
            // `Process` / `Pipe` are unavailable on embedded Apple platforms
            // (iOS / tvOS / watchOS / visionOS). `--verify-hashes` shells out
            // to a Docker oracle and is only ever invoked on a build host, so
            // this branch is never executed. It exists so `SwiftROS2Gen` still
            // compiles when `xcodebuild` builds the `SwiftROS2GenPlugin`
            // build-tool plugin's tool for an embedded Apple destination.
            throw OracleError.dockerNotInstalled
        #endif
    }

    /// Pulls the `"type_hashes": [{ "type_name": "...", "hash_string": "RIHS01_..." }, ...]`
    /// array out of the rosidl-emitted JSON. The format is stable across
    /// jazzy / kilted / rolling.
    static func extractHashes(from json: String, source: String) throws -> [String: String] {
        guard let data = json.data(using: .utf8),
            let any = try? JSONSerialization.jsonObject(with: data),
            let dict = any as? [String: Any],
            let array = dict["type_hashes"] as? [[String: Any]]
        else {
            throw OracleError.missingTypeHashes(path: source, body: json)
        }
        var out: [String: String] = [:]
        for entry in array {
            guard
                let name = entry["type_name"] as? String,
                let hash = entry["hash_string"] as? String,
                hash.hasPrefix("RIHS01_")
            else { continue }
            out[name] = hash
        }
        if out.isEmpty {
            throw OracleError.missingTypeHashes(path: source, body: json)
        }
        return out
    }
}
