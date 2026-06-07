// RclClientProtocol.swift
// FFI seam for the real-rcl backend. The concrete RclClient lives in the
// gated SwiftROS2RCL target; this protocol stays C-free so RclTransportSession
// is unit-testable with a mock (no xcframework) in ordinary CI.

import Foundation

/// Opaque handle to an rcl node owned by the client.
package protocol RclNodeHandle: AnyObject, Sendable {}

/// Opaque handle to an rcl publisher owned by the client.
package protocol RclPublisherHandle: AnyObject, Sendable {
    var isActive: Bool { get }
    func close()
}

/// Lifecycle + publish operations the rcl C bridge exposes.
package protocol RclClientProtocol: Sendable {
    /// Whether the native rcl stack is linked and usable.
    var isAvailable: Bool { get }

    func createContext(domainId: Int32) throws
    func destroyContext()

    func createNode(name: String, namespace: String) throws -> any RclNodeHandle
    func destroyNode(_ node: any RclNodeHandle)

    func createPublisher(
        node: any RclNodeHandle,
        typeName: String,
        topic: String,
        qos: TransportQoS
    ) throws -> any RclPublisherHandle

    /// Publish pre-serialized CDR bytes (XCDR1 incl. the 4-byte encapsulation header).
    func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws
}
