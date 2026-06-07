import XCTest

@testable import SwiftROS2Transport

final class RclTransportSessionTests: XCTestCase {
    private func openSession(
        _ client: MockRclClient = MockRclClient(),
        domainId: Int = 0
    ) async throws -> RclTransportSession {
        let s = RclTransportSession(client: client)
        try await s.open(config: .rcl(domainId: domainId))
        return s
    }

    func testOpenCreatesContext() async throws {
        let client = MockRclClient()
        let s = try await openSession(client, domainId: 5)
        XCTAssertTrue(client.contextCreated)
        XCTAssertEqual(client.lastDomainId, 5)
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.transportType, .rcl)
        XCTAssertEqual(s.sessionId, "rcl-5")
    }

    func testOpenRejectsNonRclConfig() async {
        let s = RclTransportSession(client: MockRclClient())
        do {
            try await s.open(config: .ddsMulticast(domainId: 0))
            XCTFail("expected invalidConfiguration")
        } catch let e as TransportError {
            guard case .invalidConfiguration = e else { return XCTFail("got \(e)") }
        } catch { XCTFail("got \(error)") }
    }

    func testOpenFailsWhenUnavailable() async {
        let client = MockRclClient()
        client.isAvailable = false
        let s = RclTransportSession(client: client)
        do {
            try await s.open(config: .rcl(domainId: 0))
            XCTFail("expected unsupportedFeature")
        } catch let e as TransportError {
            guard case .unsupportedFeature = e else { return XCTFail("got \(e)") }
        } catch { XCTFail("got \(error)") }
    }

    func testRegisterNodeCreatesRclNode() async throws {
        let client = MockRclClient()
        let s = try await openSession(client)
        try s.registerNode(name: "imu_node", namespace: "/ios")
        XCTAssertEqual(client.nodesCreated.count, 1)
        XCTAssertEqual(client.nodesCreated.first?.name, "imu_node")
        XCTAssertEqual(client.nodesCreated.first?.namespace, "/ios")
    }

    func testUnregisterNodeDestroysRclNode() async throws {
        let client = MockRclClient()
        let s = try await openSession(client)
        try s.registerNode(name: "imu_node", namespace: "/ios")
        s.unregisterNode(name: "imu_node", namespace: "/ios")
        XCTAssertEqual(client.nodesDestroyed.count, 1)
        XCTAssertEqual(client.nodesDestroyed.first?.name, "imu_node")
    }

    func testCreateSubscriberUnsupported() async throws {
        let s = try await openSession()
        XCTAssertThrowsError(
            try s.createSubscriber(
                topic: "/t", typeName: "std_msgs/msg/String", typeHash: nil,
                qos: .sensorData, handler: { _, _ in })
        ) { error in
            guard case TransportError.unsupportedFeature = error else {
                return XCTFail("got \(error)")
            }
        }
    }

    func testCloseDestroysNodesAndContext() async throws {
        let client = MockRclClient()
        let s = try await openSession(client)
        try s.registerNode(name: "imu_node", namespace: "/ios")
        try s.close()
        XCTAssertTrue(client.contextDestroyed)
        XCTAssertEqual(client.nodesDestroyed.count, 1)
        XCTAssertFalse(s.isConnected)
    }

    func testRegisterNodeBeforeOpenThrows() {
        let s = RclTransportSession(client: MockRclClient())
        XCTAssertThrowsError(try s.registerNode(name: "n", namespace: "/")) { error in
            guard case TransportError.notConnected = error else { return XCTFail("got \(error)") }
        }
    }

    func testCloseWithoutOpenSkipsDestroyContext() throws {
        let client = MockRclClient()
        let s = RclTransportSession(client: client)
        try s.close()
        XCTAssertFalse(client.contextDestroyed)
    }
}
