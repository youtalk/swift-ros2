import XCTest

@testable import SwiftROS2

final class ROS2ParameterCallbackHandleTests: XCTestCase {
    func testEqualityById() {
        let a = ROS2ParameterCallbackHandle(id: 1)
        let b = ROS2ParameterCallbackHandle(id: 1)
        let c = ROS2ParameterCallbackHandle(id: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHashableMatchesEquality() {
        let a = ROS2ParameterCallbackHandle(id: 1)
        let b = ROS2ParameterCallbackHandle(id: 1)
        var set: Set<ROS2ParameterCallbackHandle> = []
        set.insert(a)
        XCTAssertTrue(set.contains(b))
    }
}
