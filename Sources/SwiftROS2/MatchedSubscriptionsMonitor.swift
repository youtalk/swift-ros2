// MatchedSubscriptionsMonitor.swift
// Samples a publisher's matched-subscription state and reports changes.

import Dispatch
import Foundation

/// Samples `read` and reports every change to the registered handler.
///
/// Everything that reads the state or calls the handler runs on one private
/// serial queue, so calls never overlap or reorder, and ``stop()`` can wait
/// for the one that is in flight. The timer only exists while a handler is
/// registered.
final class MatchedSubscriptionsMonitor: @unchecked Sendable {
    static let defaultInterval: DispatchTimeInterval = .milliseconds(50)

    private let read: @Sendable () -> Bool
    private let interval: DispatchTimeInterval
    private let queue = DispatchQueue(label: "swift-ros2.matched-subscriptions")
    private let queueKey = DispatchSpecificKey<Bool>()
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
        queue.setSpecific(key: queueKey, value: true)
    }

    /// Registers `handler` (replacing any previous one), reads the current
    /// state, and calls `handler` with it on the monitor's serial queue.
    ///
    /// That initial call completes before `start` returns, and sampling begins
    /// after it, so a later change can never overtake it. Called from a handler
    /// (already on the queue), it runs inline instead of waiting on itself.
    /// After ``stop()`` this does nothing.
    func start(_ handler: @escaping @Sendable (Bool) -> Void) {
        onQueue {
            let current = read()
            lock.lock()
            guard !stopped else {
                lock.unlock()
                return
            }
            self.handler = handler
            last = current
            lock.unlock()
            handler(current)
            startTimerIfNeeded()
        }
    }

    /// Samples once and reports a change. Internal so tests can drive it.
    func poll() {
        onQueue {
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
    }

    /// Stops sampling for good. Waits for a call that is already running on the
    /// monitor's queue; once this returns, no handler call happens or can start.
    ///
    /// Do not call this while holding a lock that the handler may block on.
    /// Called from the handler itself it returns without waiting, since the
    /// handler is the call in flight.
    func stop() {
        lock.lock()
        stopped = true
        handler = nil
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
        if !isOnQueue {
            queue.sync {}
        }
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Private

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    /// Runs `work` on the monitor's queue: inline when already there, else synchronously.
    private func onQueue(_ work: () -> Void) {
        if isOnQueue {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    /// Must run on the queue, after the initial delivery.
    private func startTimerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
    }
}
