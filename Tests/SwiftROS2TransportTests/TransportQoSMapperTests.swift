import SwiftROS2Wire
import XCTest

@testable import SwiftROS2Transport

final class TransportQoSMapperTests: XCTestCase {
    // MARK: - toWireQoSPolicy

    func testReliableTransientLocalKeepLastMapsToWire() {
        let qos = TransportQoS(reliability: .reliable, durability: .transientLocal, history: .keepLast(5))
        let policy = TransportQoSMapper.toWireQoSPolicy(qos)
        XCTAssertEqual(policy.reliability, .reliable)
        XCTAssertEqual(policy.durability, .transientLocal)
        XCTAssertEqual(policy.historyPolicy, .keepLast)
        XCTAssertEqual(policy.historyDepth, 5)
    }

    func testBestEffortVolatileKeepLastMapsToWire() {
        let qos = TransportQoS(reliability: .bestEffort, durability: .volatile, history: .keepLast(10))
        let policy = TransportQoSMapper.toWireQoSPolicy(qos)
        XCTAssertEqual(policy.reliability, .bestEffort)
        XCTAssertEqual(policy.durability, .volatile)
        XCTAssertEqual(policy.historyPolicy, .keepLast)
        XCTAssertEqual(policy.historyDepth, 10)
    }

    func testKeepAllUsesWireSentinelDepthOf1000() {
        let qos = TransportQoS(reliability: .reliable, durability: .volatile, history: .keepAll)
        let policy = TransportQoSMapper.toWireQoSPolicy(qos)
        XCTAssertEqual(policy.historyPolicy, .keepAll)
        XCTAssertEqual(policy.historyDepth, 1000, "Wire sentinel for keepAll is 1000 (preserved from pre-PR3 behavior)")
    }

    // MARK: - toDDSBridgeQoSConfig

    func testReliableTransientLocalKeepLastMapsToDDSBridge() {
        let qos = TransportQoS(reliability: .reliable, durability: .transientLocal, history: .keepLast(7))
        let cfg = TransportQoSMapper.toDDSBridgeQoSConfig(qos)
        XCTAssertEqual(cfg.reliability, .reliable)
        XCTAssertEqual(cfg.durability, .transientLocal)
        XCTAssertEqual(cfg.historyKind, .keepLast)
        XCTAssertEqual(cfg.historyDepth, 7)
    }

    func testKeepAllUsesDDSBridgeSentinelDepthOf0() {
        let qos = TransportQoS(reliability: .reliable, durability: .volatile, history: .keepAll)
        let cfg = TransportQoSMapper.toDDSBridgeQoSConfig(qos)
        XCTAssertEqual(cfg.historyKind, .keepAll)
        XCTAssertEqual(cfg.historyDepth, 0, "DDS bridge sentinel for keepAll is 0 (preserved from pre-PR3 behavior)")
    }

    // MARK: - public TransportQoS.toQoSPolicy() still works (delegation)

    func testPublicToQoSPolicyDelegatesToMapper() {
        let qos = TransportQoS.sensorData
        XCTAssertEqual(qos.toQoSPolicy(), TransportQoSMapper.toWireQoSPolicy(qos))
    }
}
