// ZenohTransportSession+Connection.swift
// Connection establishment with timeout polling.

import Foundation

extension ZenohTransportSession {
    func connectWithTimeout(locator: String, timeout: TimeInterval) async throws {
        let result = ConnectionResult()
        let client = self.client

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.open(locator: locator)
                result.setCompleted()
            } catch {
                result.setError(error)
            }
        }

        let startTime = Date()
        while !result.isCompleted() {
            if Date().timeIntervalSince(startTime) > timeout {
                throw TransportError.connectionTimeout(timeout)
            }
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms polling
        }

        if let error = result.getError() {
            throw TransportError.connectionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Connection Result (Thread-safe)

private final class ConnectionResult: @unchecked Sendable {
    private var error: Error?
    private var completed = false
    private let lock = NSLock()

    func setCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }

    func setError(_ err: Error) {
        lock.lock()
        error = err
        completed = true
        lock.unlock()
    }

    func isCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func getError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
