public struct ROS2SetParametersResult: Sendable, Equatable {
    public var successful: Bool
    public var reason: String

    public init(successful: Bool, reason: String = "") {
        self.successful = successful
        self.reason = reason
    }

    public static func success() -> ROS2SetParametersResult {
        ROS2SetParametersResult(successful: true)
    }

    public static func failure(reason: String) -> ROS2SetParametersResult {
        ROS2SetParametersResult(successful: false, reason: reason)
    }
}

public struct ROS2ListParametersResult: Sendable, Equatable {
    public var names: [String]
    public var prefixes: [String]

    public init(names: [String] = [], prefixes: [String] = []) {
        self.names = names
        self.prefixes = prefixes
    }
}
