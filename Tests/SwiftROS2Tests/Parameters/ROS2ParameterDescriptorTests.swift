import XCTest

@testable import SwiftROS2

final class ROS2ParameterDescriptorTests: XCTestCase {
    func testDefaultsAreEmpty() {
        let d = ROS2ParameterDescriptor()
        XCTAssertEqual(d.name, "")
        XCTAssertEqual(d.type, .notSet)
        XCTAssertEqual(d.description, "")
        XCTAssertEqual(d.additionalConstraints, "")
        XCTAssertFalse(d.readOnly)
        XCTAssertFalse(d.dynamicTyping)
        XCTAssertNil(d.floatingPointRange)
        XCTAssertNil(d.floatingPointStep)
        XCTAssertNil(d.integerRange)
        XCTAssertNil(d.integerStep)
    }

    func testCustomDescriptor() {
        let d = ROS2ParameterDescriptor(
            name: "rate",
            type: .integer,
            description: "publish rate (Hz)",
            integerRange: 1...120,
            integerStep: 1
        )
        XCTAssertEqual(d.name, "rate")
        XCTAssertEqual(d.type, .integer)
        XCTAssertEqual(d.description, "publish rate (Hz)")
        XCTAssertEqual(d.integerRange?.lowerBound, 1)
        XCTAssertEqual(d.integerRange?.upperBound, 120)
        XCTAssertEqual(d.integerStep, 1)
    }
}
