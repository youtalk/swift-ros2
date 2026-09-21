// Internal wire fallback — not a product since 2.0.0, so every importer is
// in-package (the SwiftROS2 umbrella and tests).
// Re-export the public surface of SwiftROS2Transport so a caller that imports
// SwiftROS2DDS can reach TransportConfig, DDSPeer, and the shared transport
// entry points without an extra import. The internal/package-scoped bridge
// types (DDSClientProtocol, DDSBridgeQoSConfig, DDSError, etc.) are not
// re-exported — they were demoted out of the public surface in 1.0.0.
@_exported import SwiftROS2Transport
