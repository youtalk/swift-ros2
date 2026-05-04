// CommonTypes.swift
// Common ROS 2 types shared across multiple messages.
//
// Header / BuiltinInterfacesTime / Vector3 / Quaternion / Point / Pose / Twist /
// Transform are now generated under `Sources/SwiftROS2Messages/Generated/` by
// swift-ros2-gen (see Phase 2 Task 12). The remaining contents of this file are
// helper utilities that are not derived from `.msg` IDL.

import Foundation
import SwiftROS2CDR

// MARK: - Covariance Constants

/// Sentinel values and helpers for ROS 2 covariance matrices.
///
/// Use ``unknown`` (−1.0) to indicate that covariance is not available,
/// following the ROS 2 sensor-message convention.
public enum CovarianceConstants {
    public static let unknown: Double = -1.0

    public static func unknownCovariance3x3() -> [Double] {
        Array(repeating: unknown, count: 9)
    }

    public static func zeroCovariance3x3() -> [Double] {
        Array(repeating: 0.0, count: 9)
    }
}
