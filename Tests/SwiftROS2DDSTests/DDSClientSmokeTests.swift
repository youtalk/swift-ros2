import XCTest

@testable import SwiftROS2DDS

final class DDSClientSmokeTests: XCTestCase {
    func testAvailabilityFlag() {
        let client = DDSClient()
        XCTAssertTrue(client.isAvailable)
    }

    func testInitializationDoesNotCrash() {
        _ = DDSClient()
    }

    func testWriteWithForeignHandleThrows() throws {
        let client = DDSClient()
        let foreign = ForeignWriterHandle()
        XCTAssertThrowsError(
            try client.writeRawCDR(
                writer: foreign, data: Data([0x00, 0x01, 0x00, 0x00]), timestamp: 0)
        ) { error in
            guard let e = error as? DDSError else {
                XCTFail("Expected DDSError, got \(type(of: error))")
                return
            }
            if case .writeFailed = e {
                // ok
            } else {
                XCTFail("Expected .writeFailed, got \(e)")
            }
        }
    }

    func testDestroyReaderWithForeignHandleIsNoOp() {
        let client = DDSClient()
        let foreign = ForeignReaderHandle()
        // destroyReader is non-throwing; the client must silently no-op on a
        // handle it didn't create rather than force-cast into its private box.
        client.destroyReader(foreign)
    }

    func testCreateReaderWithoutSessionThrows() throws {
        let client = DDSClient()
        XCTAssertThrowsError(
            try client.createRawReader(
                topicName: "rt/test",
                typeName: "std_msgs::msg::dds_::String_",
                qos: DDSBridgeQoSConfig(),
                userData: nil,
                handler: { _, _ in }
            )
        ) { error in
            guard let e = error as? DDSError else {
                XCTFail("Expected DDSError, got \(type(of: error))")
                return
            }
            if case .notConnected = e {
                // ok
            } else {
                XCTFail("Expected .notConnected, got \(e)")
            }
        }
    }
}

private final class ForeignWriterHandle: DDSWriterHandle {
    var isActive: Bool { false }
    func close() {}
}

private final class ForeignReaderHandle: DDSReaderHandle {
    var isActive: Bool { false }
    func close() {}
}
