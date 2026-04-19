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
}

private final class ForeignWriterHandle: DDSWriterHandle {
    var isActive: Bool { false }
    func close() {}
}
