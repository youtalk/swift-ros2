import XCTest

@testable import SwiftROS2

final class ROS2NodeOptionsTests: XCTestCase {
    func testDefaultsAutoRegisterParameterServices() {
        let options = ROS2NodeOptions()
        XCTAssertTrue(options.startParameterServices)
    }

    func testDefaultStaticMatchesInit() {
        XCTAssertEqual(ROS2NodeOptions.default, ROS2NodeOptions())
    }

    func testOptOutOfParameterServices() {
        let options = ROS2NodeOptions(startParameterServices: false)
        XCTAssertFalse(options.startParameterServices)
    }
}
