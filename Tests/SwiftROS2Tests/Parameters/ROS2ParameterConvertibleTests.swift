import XCTest

@testable import SwiftROS2

final class ROS2ParameterConvertibleTests: XCTestCase {
    func testBool() throws {
        XCTAssertEqual(true.parameterValue, .bool(true))
        XCTAssertEqual(try Bool(parameterValue: .bool(false)), false)
    }

    func testInt64() throws {
        XCTAssertEqual(Int64(42).parameterValue, .integer(42))
        XCTAssertEqual(try Int64(parameterValue: .integer(-7)), -7)
    }

    func testIntCoercesToInt64() throws {
        XCTAssertEqual(Int(42).parameterValue, .integer(42))
        XCTAssertEqual(try Int(parameterValue: .integer(-7)), -7)
    }

    func testDouble() throws {
        XCTAssertEqual(3.14.parameterValue, .double(3.14))
        XCTAssertEqual(try Double(parameterValue: .double(-1.5)), -1.5)
    }

    func testString() throws {
        XCTAssertEqual("hi".parameterValue, .string("hi"))
        XCTAssertEqual(try String(parameterValue: .string("hi")), "hi")
    }

    func testByteArray() throws {
        let bs: [UInt8] = [1, 2, 3]
        XCTAssertEqual(bs.parameterValue, .byteArray([1, 2, 3]))
        XCTAssertEqual(try [UInt8](parameterValue: .byteArray([1, 2, 3])), [1, 2, 3])
    }

    func testBoolArray() throws {
        XCTAssertEqual([true, false].parameterValue, .boolArray([true, false]))
        XCTAssertEqual(try [Bool](parameterValue: .boolArray([true])), [true])
    }

    func testInt64Array() throws {
        let xs: [Int64] = [1, 2]
        XCTAssertEqual(xs.parameterValue, .integerArray([1, 2]))
        XCTAssertEqual(try [Int64](parameterValue: .integerArray([3])), [3])
    }

    func testDoubleArray() throws {
        XCTAssertEqual([1.0, 2.0].parameterValue, .doubleArray([1.0, 2.0]))
        XCTAssertEqual(try [Double](parameterValue: .doubleArray([3.5])), [3.5])
    }

    func testStringArray() throws {
        XCTAssertEqual(["a", "b"].parameterValue, .stringArray(["a", "b"]))
        XCTAssertEqual(try [String](parameterValue: .stringArray(["x"])), ["x"])
    }

    func testTypeMismatchThrows() {
        XCTAssertThrowsError(try Int64(parameterValue: .string("seven"))) { e in
            guard case ROS2ParameterError.invalidType(_, let expected, let got) = e else {
                XCTFail("wrong error: \(e)")
                return
            }
            XCTAssertEqual(expected, .integer)
            XCTAssertEqual(got, .string)
        }
    }
}
