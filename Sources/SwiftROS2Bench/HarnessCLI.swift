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
    /// ``defaultZenohLocator``. A trailing `--locator` with no value and an
    /// empty environment value both fall through to the next source.
    public static func resolveZenohLocator(
        arguments: [String],
        environment: [String: String]
    ) -> String {
        if let i = arguments.firstIndex(of: "--locator"), i + 1 < arguments.count,
            !arguments[i + 1].isEmpty
        {
            return arguments[i + 1]
        }
        if let env = environment[zenohLocatorEnvVar], !env.isEmpty {
            return env
        }
        return defaultZenohLocator
    }
}
