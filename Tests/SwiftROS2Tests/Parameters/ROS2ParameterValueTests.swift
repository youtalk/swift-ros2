import XCTest

@testable import SwiftROS2

final class ROS2ParameterValueTests: XCTestCase {
    func testEqualityForSameValues() {
        XCTAssertEqual(ROS2ParameterValue.integer(7), ROS2ParameterValue.integer(7))
        XCTAssertEqual(ROS2ParameterValue.string("a"), ROS2ParameterValue.string("a"))
        XCTAssertEqual(ROS2ParameterValue.notSet, ROS2ParameterValue.notSet)
    }

    func testInequalityAcrossCases() {
        XCTAssertNotEqual(ROS2ParameterValue.integer(7), ROS2ParameterValue.double(7.0))
        XCTAssertNotEqual(ROS2ParameterValue.bool(true), ROS2ParameterValue.notSet)
    }

    func testArrayCases() {
        let a: ROS2ParameterValue = .integerArray([1, 2, 3])
        let b: ROS2ParameterValue = .integerArray([1, 2, 3])
        let c: ROS2ParameterValue = .integerArray([1, 2])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
