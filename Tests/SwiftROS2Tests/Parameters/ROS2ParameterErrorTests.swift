import XCTest

@testable import SwiftROS2

final class ROS2ParameterErrorTests: XCTestCase {
    func testCasesAreDistinct() {
        let a: ROS2ParameterError = .alreadyDeclared(name: "rate")
        let b: ROS2ParameterError = .notDeclared(name: "rate")
        XCTAssertNotEqual(a, b)
    }

    func testInvalidTypeCarriesExpectedAndGot() {
        let e: ROS2ParameterError = .invalidType(
            name: "rate", expected: .integer, got: .string)
        guard case let .invalidType(name, expected, got) = e else {
            XCTFail("wrong case")
            return
        }
        XCTAssertEqual(name, "rate")
        XCTAssertEqual(expected, .integer)
        XCTAssertEqual(got, .string)
    }

    func testIsErrorType() {
        let e: any Error = ROS2ParameterError.notDeclared(name: "x")
        XCTAssertTrue(e is ROS2ParameterError)
    }
}
