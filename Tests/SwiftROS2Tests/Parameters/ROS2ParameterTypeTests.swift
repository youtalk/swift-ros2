import XCTest

@testable import SwiftROS2

final class ROS2ParameterTypeTests: XCTestCase {
    func testRawValuesMatchRclInterfacesConstants() {
        XCTAssertEqual(ROS2ParameterType.notSet.rawValue, 0)
        XCTAssertEqual(ROS2ParameterType.bool.rawValue, 1)
        XCTAssertEqual(ROS2ParameterType.integer.rawValue, 2)
        XCTAssertEqual(ROS2ParameterType.double.rawValue, 3)
        XCTAssertEqual(ROS2ParameterType.string.rawValue, 4)
        XCTAssertEqual(ROS2ParameterType.byteArray.rawValue, 5)
        XCTAssertEqual(ROS2ParameterType.boolArray.rawValue, 6)
        XCTAssertEqual(ROS2ParameterType.integerArray.rawValue, 7)
        XCTAssertEqual(ROS2ParameterType.doubleArray.rawValue, 8)
        XCTAssertEqual(ROS2ParameterType.stringArray.rawValue, 9)
    }

    func testRoundTripFromRawValue() {
        for raw: UInt8 in 0...9 {
            let t = ROS2ParameterType(rawValue: raw)
            XCTAssertNotNil(t, "unexpected nil for raw \(raw)")
            XCTAssertEqual(t?.rawValue, raw)
        }
        XCTAssertNil(ROS2ParameterType(rawValue: 10))
    }
}
