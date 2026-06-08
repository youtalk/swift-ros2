import Foundation
import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

@testable import SwiftROS2
@testable import SwiftROS2Transport

/// A message that is both encodable and typed-publishable, for dispatch testing.
private struct FakeTypedMessage: ROS2Message, RclTypedPublishable, Equatable {
    static let typeInfo = ROS2MessageTypeInfo(typeName: "test_msgs/msg/Fake", typeHash: "RIHS01_fake")
    var value: Int32 = 7
    func encode(to encoder: CDREncoder) throws { encoder.writeInt32(value) }
    init() {}
    init(value: Int32) { self.value = value }
    init(from decoder: CDRDecoder) throws { self.value = try decoder.readInt32() }
    func rclTypedPublish(into handle: any RclPublisherHandle) throws {}  // unused in dispatch test
}

/// Records which path ROS2Publisher took.
private final class SpyPublisher: TransportPublisher, @unchecked Sendable {
    let supportsTyped: Bool
    let topic = "fake"
    var isActive = true
    private(set) var byteCount = 0
    private(set) var typedCount = 0
    init(supportsTyped: Bool) { self.supportsTyped = supportsTyped }
    var supportsTypedPublish: Bool { supportsTyped }
    func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws { byteCount += 1 }
    func publishTyped(_ publishable: any RclTypedPublishable) throws { typedCount += 1 }
    func close() throws {}
}

final class TypedPublishDispatchTests: XCTestCase {
    func testRoutesToTypedWhenSupported() throws {
        let spy = SpyPublisher(supportsTyped: true)
        let pub = ROS2Publisher<FakeTypedMessage>(transportPublisher: spy)
        try pub.publish(FakeTypedMessage(value: 1))
        XCTAssertEqual(spy.typedCount, 1)
        XCTAssertEqual(spy.byteCount, 0)
    }

    func testFallsBackToByteWhenUnsupported() throws {
        let spy = SpyPublisher(supportsTyped: false)
        let pub = ROS2Publisher<FakeTypedMessage>(transportPublisher: spy)
        try pub.publish(FakeTypedMessage(value: 1))
        XCTAssertEqual(spy.typedCount, 0)
        XCTAssertEqual(spy.byteCount, 1)
    }
}
