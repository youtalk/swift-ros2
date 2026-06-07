// Re-export SwiftROS2Transport so a caller importing SwiftROS2RCL reaches
// TransportConfig and the shared transport entry points without an extra
// import, mirroring SwiftROS2DDS/Exports.swift.
@_exported import SwiftROS2Transport
