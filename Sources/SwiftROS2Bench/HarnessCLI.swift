import Foundation

/// Pure argument / environment resolution shared by the rcl-bench and
/// rcl-soak harness executables. No I/O — unit-tested in normal CI.
public enum HarnessCLI {
    /// Backend tokens the harness executables accept.
    public static let supportedBackends: Set<String> = ["rcl", "dds", "zenoh"]

    /// Environment variable consulted when `--locator` is absent.
    public static let zenohLocatorEnvVar = "SWIFT_ROS2_ZENOH_LOCATOR"

    /// Fallback Zenoh router locator (a local rmw_zenohd).
    public static let defaultZenohLocator = "tcp/127.0.0.1:7447"

    /// Resolve the Zenoh router locator for the `zenoh` backend:
    /// `--locator <str>` wins, then `SWIFT_ROS2_ZENOH_LOCATOR`, then
    /// ``defaultZenohLocator``. A trailing `--locator` with no value, a
    /// value that is itself another flag (`--locator --duration-s`), and an
    /// empty environment value all fall through to the next source — a
    /// locator never legitimately starts with `-`.
    public static func resolveZenohLocator(
        arguments: [String],
        environment: [String: String]
    ) -> String {
        if let i = arguments.firstIndex(of: "--locator"), i + 1 < arguments.count,
            !arguments[i + 1].isEmpty, !arguments[i + 1].hasPrefix("-")
        {
            return arguments[i + 1]
        }
        if let env = environment[zenohLocatorEnvVar], !env.isEmpty {
            return env
        }
        return defaultZenohLocator
    }

    /// The transport stack the `zenoh` backend token actually resolves to in
    /// this build. The token is variant-dependent (an invisible build-time
    /// switch), so RESULT lines record it explicitly to keep archived soak
    /// and bench logs self-describing: when the zenoh-pico wire family is in
    /// the build graph, `.zenoh` is the wire path; when it is carved out
    /// (SWIFT_ROS2_RCL_RMW=zenoh), `.zenoh` routes to rcl + rmw_zenoh_cpp.
    public static var zenohStack: String {
        #if canImport(SwiftROS2Zenoh)
            return "wire-zenoh-pico"
        #else
            return "rcl-rmw_zenoh"
        #endif
    }

    /// Stack description for any backend token, for RESULT-line stamping.
    public static func stack(forBackend backend: String) -> String {
        switch backend {
        case "zenoh": return zenohStack
        case "rcl": return "rcl-rmw_cyclonedds"
        default: return "wire-cyclonedds"
        }
    }
}
