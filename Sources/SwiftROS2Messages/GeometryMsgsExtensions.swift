// Hand-written conveniences layered on top of the swift-ros2-gen output.
//
// The IDL emitter is intentionally minimal — it only writes fields, an `init`,
// and CDR encode/decode. Any helper / sentinel / convention-driven default that
// the rest of the codebase relies on lives here so the generated files stay
// regenerable without manual touch-ups.

import Foundation

extension Quaternion {
    /// Identity quaternion (`w == 1`). The generated `init` defaults `w` to `0`
    /// because Phase 2 of swift-ros2-gen drops `.msg` default values; this
    /// overload preserves the identity convention used pervasively in caller
    /// code (e.g. `Imu.orientation` defaults to identity, not the zero
    /// quaternion).
    public static var identity: Quaternion { Quaternion(w: 1.0) }
}

extension Header {
    /// Backward-compat initializer matching the pre-generation `Header` shape
    /// (`UInt32 sec`, `UInt32 nanosec`). Routes through the nested `Time` field
    /// the IDL-generated struct now exposes. New callers should use
    /// `Header(stamp:frameId:)` directly.
    ///
    /// All parameters retain the defaults the original hand-written initializer
    /// shipped with — removing them would be an API break flagged by the
    /// `swift package diagnose-api-breaking-changes` baseline.
    public init(sec: UInt32 = 0, nanosec: UInt32 = 0, frameId: String = "") {
        self.init(stamp: Time(sec: Int32(bitPattern: sec), nanosec: nanosec), frameId: frameId)
    }

    /// `sec` accessor preserved for callers that still read the pre-generation
    /// flat layout. Returns the underlying `stamp.sec` reinterpreted as `UInt32`.
    public var sec: UInt32 {
        get { UInt32(bitPattern: stamp.sec) }
        set { stamp.sec = Int32(bitPattern: newValue) }
    }

    /// `nanosec` accessor preserved for the same reason as ``sec``.
    public var nanosec: UInt32 {
        get { stamp.nanosec }
        set { stamp.nanosec = newValue }
    }

    /// Stamp the header with the current wall-clock time and the given frame.
    ///
    /// Saturates rather than traps after Jan 19 2038 03:14:07 UTC: `Int32(ti)`
    /// would overflow there, but `Int32(clamping:)` over an `Int64` intermediate
    /// pins to `Int32.max` instead — a more useful failure mode for callers.
    public static func now(frameId: String) -> Header {
        let ti = Date().timeIntervalSince1970
        let s = Int32(clamping: Int64(ti))
        let ns = UInt32(clamping: Int64((ti - Double(s)) * 1_000_000_000))
        return Header(stamp: Time(sec: s, nanosec: ns), frameId: frameId)
    }

    /// Header timestamp expressed in nanoseconds since the Unix epoch.
    public var timestampNanoseconds: Int64 {
        Int64(stamp.sec) * 1_000_000_000 + Int64(stamp.nanosec)
    }
}
