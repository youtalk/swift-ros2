// Re-export the Swift transport symbols so a caller that imports SwiftROS2DDS
// can reach the shared protocol types (DDSClientProtocol, DDSBridgeQoSConfig,
// DDSError) without adding SwiftROS2Transport to its own import list. The
// actual DefaultDDSClient is added in a follow-up task.
@_exported import SwiftROS2Transport
