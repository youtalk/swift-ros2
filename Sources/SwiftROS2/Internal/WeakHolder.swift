// WeakHolder.swift
// Tiny generic that holds a weak reference. Used by the umbrella to break
// the retain cycle between `ROS2ActionServer<H>` and the per-role handler
// closure bag (`TransportActionServerHandlers`) that the transport keeps.

import Foundation

final class WeakHolder<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}
