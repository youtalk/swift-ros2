// Internal wire fallback — not a product since 2.0.0, so every importer is
// in-package (the SwiftROS2 umbrella and tests).
// Re-export the Swift transport symbols so a caller that imports SwiftROS2Zenoh
// can reach the shared protocol types (ZenohClientProtocol, ZenohSample, ZenohError)
// without adding SwiftROS2Transport to its own import list.
@_exported import SwiftROS2Transport
