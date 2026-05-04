// Source-compat aliases for callers that pre-date the swift-ros2-gen migration.
// These keep the long names alive so that downstream consumers (and the action /
// service plumbing inside this repo) compile without a churn-only rename PR.
// New code should use the bare generated name (`Time`).
//
// `builtin_interfaces/Duration` is intentionally NOT regenerated in Phase 2:
// the emitter would name it `Duration`, which shadows `Swift.Duration` in any
// translation unit that imports `SwiftROS2Messages` (notably `SwiftROS2/`,
// where async timeouts are `Swift.Duration`). A follow-up will teach the
// emitter a stdlib-collision rename rule (`Duration` -> `BuiltinInterfacesDuration`)
// before we re-add it to the generated set.

import Foundation

public typealias BuiltinInterfacesTime = Time

extension Time {
    /// Wall-clock convenience used by integration tests / examples that pre-date
    /// the IDL-generated `Time` struct. The generator does not emit static
    /// helpers, so this stays as a hand-written extension.
    public static func now() -> Time {
        let ti = Date().timeIntervalSince1970
        let s = Int32(ti)
        let ns = UInt32((ti - Double(s)) * 1_000_000_000)
        return Time(sec: s, nanosec: ns)
    }
}
