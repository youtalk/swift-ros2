import SwiftROS2
import SwiftROS2Transport
import SwiftROS2Wire
import XCTest

final class QoSProfileTests: XCTestCase {
    // MARK: - presets

    func testSensorDataPreset() {
        XCTAssertEqual(QoSProfile.sensorData.reliability, .bestEffort)
        XCTAssertEqual(QoSProfile.sensorData.durability, .volatile)
        XCTAssertEqual(QoSProfile.sensorData.history, .keepLast(10))
    }

    func testReliableSensorPreset() {
        XCTAssertEqual(QoSProfile.reliableSensor.reliability, .reliable)
        XCTAssertEqual(QoSProfile.reliableSensor.durability, .volatile)
        XCTAssertEqual(QoSProfile.reliableSensor.history, .keepLast(10))
    }

    func testLatchedPreset() {
        XCTAssertEqual(QoSProfile.latched.reliability, .reliable)
        XCTAssertEqual(QoSProfile.latched.durability, .transientLocal)
        XCTAssertEqual(QoSProfile.latched.history, .keepLast(1))
    }

    func testServicesDefaultPreset() {
        XCTAssertEqual(QoSProfile.servicesDefault.reliability, .reliable)
        XCTAssertEqual(QoSProfile.servicesDefault.durability, .volatile)
    }

    func testDefaultIsSensorData() {
        XCTAssertEqual(QoSProfile.default, QoSProfile.sensorData)
    }

    // MARK: - equatability

    func testProfilesAreEqualWhenAllFieldsMatch() {
        XCTAssertEqual(
            QoSProfile(reliability: .reliable, durability: .volatile, history: .keepLast(5)),
            QoSProfile(reliability: .reliable, durability: .volatile, history: .keepLast(5))
        )
    }

    func testProfilesDifferOnHistoryDepth() {
        XCTAssertNotEqual(
            QoSProfile(history: .keepLast(5)),
            QoSProfile(history: .keepLast(6))
        )
    }

    // MARK: - toTransportQoS

    func testToTransportQoSPreservesReliability() {
        let profile = QoSProfile(reliability: .reliable, durability: .volatile, history: .keepLast(10))
        XCTAssertEqual(profile.toTransportQoS().reliability, .reliable)
    }

    func testToTransportQoSMapsKeepAll() {
        let profile = QoSProfile(reliability: .reliable, durability: .volatile, history: .keepAll)
        let qos = profile.toTransportQoS()
        if case .keepAll = qos.history {
            // ok
        } else {
            XCTFail("Expected keepAll")
        }
    }

    // MARK: - toQoSPolicy

    func testToQoSPolicyKeepLast() {
        let policy = QoSProfile(reliability: .bestEffort, durability: .volatile, history: .keepLast(10)).toQoSPolicy()
        XCTAssertEqual(policy.reliability, .bestEffort)
        XCTAssertEqual(policy.historyPolicy, .keepLast)
        XCTAssertEqual(policy.historyDepth, 10)
    }

    func testToQoSPolicyKeepAllUsesUmbrellaSentinel() {
        // The umbrella's sentinel for keepAll is 0 (depth = 0), see
        // Sources/SwiftROS2/QoSProfile.swift toQoSPolicy(). This differs from
        // TransportQoSMapper.toWireQoSPolicy which uses 1000 — both are
        // intentional, history-of-the-codebase choices.
        let policy = QoSProfile(history: .keepAll).toQoSPolicy()
        XCTAssertEqual(policy.historyPolicy, .keepAll)
        XCTAssertEqual(policy.historyDepth, 0)
    }
}
