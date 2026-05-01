import Foundation

import SwiftROS2Transport

/// In-memory ZenohClientProtocol used by ZenohTransportSession unit tests.
///
/// Records every call so tests can assert against `puts`, `keyExprDeclarations`,
/// `subscriptions`, etc. Lock-protected so tests can also exercise the
/// session's @Sendable contract.
final class MockZenohClient: ZenohClientProtocol, @unchecked Sendable {
    private let lock = NSLock()

    // Configurable behavior
    var isOpen = false
    var sessionIdValue = "mock-session-id"
    var openShouldThrow: ZenohError?
    var declareKeyExprShouldThrow: ZenohError?
    var putShouldThrow: ZenohError?
    var subscribeShouldThrow: ZenohError?
    var livelinessShouldThrow: ZenohError?
    var healthOverride: Bool?

    // Recorded invocations
    private(set) var openedLocators: [String] = []
    private(set) var closedCount = 0
    private(set) var keyExprDeclarations: [String] = []
    private(set) var puts: [(key: String, payload: Data, attachment: Data?)] = []
    private(set) var subscriptions: [(key: String, handler: (ZenohSample) -> Void)] = []
    private(set) var livelinessDeclarations: [String] = []

    func open(locator: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let e = openShouldThrow { throw e }
        openedLocators.append(locator)
        isOpen = true
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closedCount += 1
        isOpen = false
    }

    func isSessionHealthy() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return healthOverride ?? isOpen
    }

    func getSessionId() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return sessionIdValue
    }

    func declareKeyExpr(_ keyExpr: String) throws -> any ZenohKeyExprHandle {
        lock.lock()
        defer { lock.unlock() }
        if let e = declareKeyExprShouldThrow { throw e }
        keyExprDeclarations.append(keyExpr)
        return MockKeyExprHandle(keyExpr: keyExpr)
    }

    func put(keyExpr: any ZenohKeyExprHandle, payload: Data, attachment: Data?) throws {
        lock.lock()
        defer { lock.unlock() }
        if let e = putShouldThrow { throw e }
        let key = (keyExpr as? MockKeyExprHandle)?.keyExpr ?? "<unknown>"
        puts.append((key: key, payload: payload, attachment: attachment))
    }

    func put(keyExpr: String, payload: Data, attachment: Data?) throws {
        lock.lock()
        defer { lock.unlock() }
        if let e = putShouldThrow { throw e }
        puts.append((key: keyExpr, payload: payload, attachment: attachment))
    }

    func subscribe(keyExpr: String, handler: @escaping (ZenohSample) -> Void) throws -> any ZenohSubscriberHandle {
        lock.lock()
        defer { lock.unlock() }
        if let e = subscribeShouldThrow { throw e }
        subscriptions.append((key: keyExpr, handler: handler))
        return MockSubscriberHandle()
    }

    func declareLivelinessToken(_ keyExpr: String) throws -> any ZenohLivelinessTokenHandle {
        lock.lock()
        defer { lock.unlock() }
        if let e = livelinessShouldThrow { throw e }
        livelinessDeclarations.append(keyExpr)
        return MockLivelinessTokenHandle()
    }

    /// Test helper: deliver a sample to all matching subscriber handlers.
    func deliver(sample: ZenohSample, toKeyExpr key: String) {
        let handlers: [(ZenohSample) -> Void] = {
            lock.lock()
            defer { lock.unlock() }
            return subscriptions.filter { $0.key == key }.map { $0.handler }
        }()
        for handler in handlers {
            handler(sample)
        }
    }
}

final class MockKeyExprHandle: ZenohKeyExprHandle {
    let keyExpr: String
    init(keyExpr: String) { self.keyExpr = keyExpr }
}

final class MockSubscriberHandle: ZenohSubscriberHandle {
    private(set) var closeCount = 0
    private let lock = NSLock()
    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closeCount += 1
    }
}

final class MockLivelinessTokenHandle: ZenohLivelinessTokenHandle {
    private(set) var closeCount = 0
    private let lock = NSLock()
    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closeCount += 1
    }
}
