import XCTest
@testable import SwiftROS2Zenoh

final class DefaultZenohClientSmokeTests: XCTestCase {
    func testInitializationDoesNotCrash() {
        _ = DefaultZenohClient()
    }
}
