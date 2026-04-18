// ROS2Distro.swift
// ROS 2 distribution configuration for wire format compatibility

import Foundation

/// ROS 2 distribution with wire format configuration
///
/// Each distro has specific wire format requirements for rmw compatibility.
/// Key differences:
/// - Humble: No type hash support (uses "TypeHashNotSupported")
/// - Jazzy/Kilted/Rolling: RIHS01 type hash support
public enum ROS2Distro: String, CaseIterable, Sendable {
    case humble
    case jazzy
    case kilted
    case rolling

    public var displayName: String {
        rawValue.capitalized
    }

    /// Whether this distro supports type hash in key expressions
    public var supportsTypeHash: Bool {
        switch self {
        case .humble:
            return false
        case .jazzy, .kilted, .rolling:
            return true
        }
    }

    /// Whether this distro uses the pre-Jazzy message schema variant
    /// (e.g. `sensor_msgs/Range` without `variance`).
    public var isLegacySchema: Bool {
        switch self {
        case .humble:
            return true
        case .jazzy, .kilted, .rolling:
            return false
        }
    }

    /// Wire format group
    public enum WireGroup: String, CaseIterable, Sendable {
        case legacy = "Humble and earlier"
        case modern = "Iron and later"

        public var distros: [ROS2Distro] {
            switch self {
            case .legacy: return [.humble]
            case .modern: return [.jazzy, .kilted, .rolling]
            }
        }
    }

    public var wireGroup: WireGroup {
        supportsTypeHash ? .modern : .legacy
    }

    /// Placeholder for distros without type hash support
    public var typeHashPlaceholder: String {
        "TypeHashNotSupported"
    }

    /// Format the type hash component for key expressions
    public func formatTypeHash(_ typeHash: String?) -> String {
        if supportsTypeHash {
            return typeHash ?? ""
        } else {
            return typeHashPlaceholder
        }
    }

    /// Whether the key expression should always include the type hash segment
    public var alwaysIncludeTypeHashInKey: Bool {
        switch self {
        case .humble:
            return true
        case .jazzy, .kilted, .rolling:
            return false
        }
    }
}
