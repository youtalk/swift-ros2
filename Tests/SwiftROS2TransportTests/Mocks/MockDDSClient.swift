import Foundation
import SwiftROS2Transport

/// In-memory DDSClientProtocol used by DDSTransportSession unit tests.
final class MockDDSClient: DDSClientProtocol, @unchecked Sendable {
    private let lock = NSLock()

    // Configurable behavior
    var isAvailable = true
    var sessionConnected = false
    var sessionIdValue: String? = "mock-dds-session"
    var createSessionShouldThrow: DDSError?
    var createWriterShouldThrow: DDSError?
    var writeShouldThrow: DDSError?
    var createReaderShouldThrow: DDSError?

    // Recorded invocations
    private(set) var sessionCreations: [(domainId: Int32, config: DDSBridgeDiscoveryConfig)] = []
    private(set) var sessionDestructions = 0
    private(set) var writers: [(topic: String, type: String, qos: DDSBridgeQoSConfig, userData: String?)] = []
    private(set) var writes: [(topic: String, data: Data, timestamp: UInt64)] = []
    private(set) var destroyedWriters = 0
    private(set) var readers:
        [(topic: String, type: String, qos: DDSBridgeQoSConfig, userData: String?, handler: (Data, UInt64) -> Void)] =
            []
    private(set) var destroyedReaders = 0

    func createSession(domainId: Int32, discoveryConfig: DDSBridgeDiscoveryConfig) throws {
        lock.lock()
        defer { lock.unlock() }
        if let e = createSessionShouldThrow { throw e }
        sessionCreations.append((domainId, discoveryConfig))
        sessionConnected = true
    }

    func destroySession() throws {
        lock.lock()
        defer { lock.unlock() }
        sessionDestructions += 1
        sessionConnected = false
    }

    func isConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionConnected
    }

    func getSessionId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return sessionIdValue
    }

    func createRawWriter(
        topicName: String, typeName: String,
        qos: DDSBridgeQoSConfig, userData: String?
    ) throws -> any DDSWriterHandle {
        lock.lock()
        defer { lock.unlock() }
        if let e = createWriterShouldThrow { throw e }
        let handle = MockDDSWriterHandle(topic: topicName)
        writers.append((topicName, typeName, qos, userData))
        return handle
    }

    func writeRawCDR(writer: any DDSWriterHandle, data: Data, timestamp: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        if let e = writeShouldThrow { throw e }
        let topic = (writer as? MockDDSWriterHandle)?.topic ?? "<unknown>"
        writes.append((topic, data, timestamp))
    }

    func destroyWriter(_ writer: any DDSWriterHandle) {
        lock.lock()
        defer { lock.unlock() }
        destroyedWriters += 1
        (writer as? MockDDSWriterHandle)?.markClosed()
    }

    func createRawReader(
        topicName: String, typeName: String,
        qos: DDSBridgeQoSConfig, userData: String?,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any DDSReaderHandle {
        lock.lock()
        defer { lock.unlock() }
        if let e = createReaderShouldThrow { throw e }
        readers.append((topicName, typeName, qos, userData, handler))
        return MockDDSReaderHandle(topic: topicName)
    }

    func destroyReader(_ reader: any DDSReaderHandle) {
        lock.lock()
        defer { lock.unlock() }
        destroyedReaders += 1
        (reader as? MockDDSReaderHandle)?.markClosed()
    }

    /// Test helper: deliver a sample to readers on the given topic.
    func deliver(toTopic topic: String, data: Data, timestamp: UInt64) {
        let handlers: [(Data, UInt64) -> Void] = {
            lock.lock()
            defer { lock.unlock() }
            return readers.filter { $0.topic == topic }.map { $0.handler }
        }()
        for handler in handlers {
            handler(data, timestamp)
        }
    }
}

final class MockDDSWriterHandle: DDSWriterHandle, @unchecked Sendable {
    let topic: String
    private var closed = false
    private let lock = NSLock()

    init(topic: String) { self.topic = topic }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }

    func markClosed() { close() }
}

final class MockDDSReaderHandle: DDSReaderHandle, @unchecked Sendable {
    let topic: String
    private var closed = false
    private let lock = NSLock()

    init(topic: String) { self.topic = topic }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }

    func markClosed() { close() }
}
