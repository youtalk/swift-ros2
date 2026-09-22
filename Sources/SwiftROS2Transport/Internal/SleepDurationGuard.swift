// SleepDurationGuard.swift
// Shared guard against `Duration` values too large to hand to `Task.sleep(for:)`.
//
// `Task.sleep(for:)` converts its `Duration` argument to nanoseconds
// internally using fixed-width arithmetic. A caller-supplied "no timeout"
// stand-in such as `.seconds(Int.max)` overflows that conversion and traps
// the process with "Not enough bits to represent the passed value" instead
// of throwing. Every request/response timeout race in this module (DDS
// action, DDS service, rcl action + service) checks `isSafeSleepDuration`
// before starting the sleeping timeout child task; a duration at or above
// the threshold is treated as "wait forever" and no timeout task is
// scheduled at all, so the reply (or cancellation) is awaited indefinitely
// instead of racing a `Task.sleep` call that would trap.

import Foundation

/// The largest `Duration` this module will hand to `Task.sleep(for:)`.
///
/// `Task.sleep` converts its argument to nanoseconds using `Int64`
/// arithmetic; `Int64.max` nanoseconds is about 292 years. 100 years is far
/// beyond any legitimate request timeout and leaves generous headroom below
/// the overflow point.
let maxSafeSleepDuration = Duration.seconds(60 * 60 * 24 * 365 * 100)

/// Whether `duration` is safe to pass to `Task.sleep(for:)` without risking
/// an overflow trap.
///
/// Callers that race a reply against a timeout should skip scheduling the
/// sleeping child task entirely when this returns `false`, and simply await
/// the reply (or cancellation) with no timeout in effect.
func isSafeSleepDuration(_ duration: Duration) -> Bool {
    duration < maxSafeSleepDuration
}
