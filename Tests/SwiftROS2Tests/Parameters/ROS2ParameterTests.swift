import XCTest

@testable import SwiftROS2

final class ROS2ParameterTests: XCTestCase {
    func testInitAndAccessors() {
        let p = ROS2Parameter(name: "rate", value: .integer(30))
        XCTAssertEqual(p.name, "rate")
        XCTAssertEqual(p.value, .integer(30))
    }

    func testEquality() {
        let a = ROS2Parameter(name: "rate", value: .integer(30))
        let b = ROS2Parameter(name: "rate", value: .integer(30))
        let c = ROS2Parameter(name: "rate", value: .integer(31))
        let d = ROS2Parameter(name: "fps", value: .integer(30))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }
}
