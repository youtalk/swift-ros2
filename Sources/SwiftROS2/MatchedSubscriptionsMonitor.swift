// MatchedSubscriptionsMonitor.swift
// Samples a publisher's matched-subscription state and reports changes.

import Dispatch
import Foundation

/// Samples `read` on a private queue and calls the registered handler with
/// every change. The timer only exists while a handler is registered.
final class MatchedSubscriptionsMonitor: @unchecked Sendable {
    static let defaultInterval: DispatchTimeInterval = .milliseconds(50)

    private let read: @Sendable () -> Bool
    private let interval: DispatchTimeInterval
    private let queue = DispatchQueue(label: "swift-ros2.matched-subscriptions")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var handler: (@Sendable (Bool) -> Void)?
    private var last: Bool?
    private var stopped = false

    init(
        interval: DispatchTimeInterval = MatchedSubscriptionsMonitor.defaultInterval,
        read: @escaping @Sendable () -> Bool
    ) {
        self.interval = interval
        self.read = read
    }

    /// Registers `handler` (replacing any previous one), calls it once with the
    /// current state before returning, and starts sampling.
    func start(_ handler: @escaping @Sendable (Bool) -> Void) {
        let current = read()
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        self.handler = handler
        last = current
        if timer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + interval, repeating: interval)
            t.setEventHandler { [weak self] in self?.poll() }
            timer = t
            t.resume()
        }
        lock.unlock()
        handler(current)
    }

    /// Samples once and reports a change. Internal so tests can drive it.
    func poll() {
        let current = read()
        lock.lock()
        guard !stopped, let h = handler, current != last else {
            lock.unlock()
            return
        }
        last = current
        lock.unlock()
        h(current)
    }

    /// Stops sampling for good; no handler call happens after this returns.
    func stop() {
        lock.lock()
        stopped = true
        handler = nil
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
    }

    deinit {
        timer?.cancel()
    }
}
