import Foundation

/// Sendable container for capturing values from `@Sendable` handlers in tests.
///
/// The transport `createSubscriber` API hands the user a `@Sendable` closure;
/// asserting on what the handler observed requires a sendable shared
/// container. `Box` wraps a single value behind an `NSLock` and is callable
/// from any concurrency context.
final class Box<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}
