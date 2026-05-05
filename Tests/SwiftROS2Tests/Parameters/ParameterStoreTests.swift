import XCTest

@testable import SwiftROS2

final class ParameterStoreTests: XCTestCase {
    func testDeclareThenHas() async throws {
        let store = ParameterStore()
        let stored = try await store.declare(
            name: "rate",
            value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        XCTAssertEqual(stored, .integer(30))
        let hit = await store.has(name: "rate")
        XCTAssertTrue(hit)
        let miss = await store.has(name: "fps")
        XCTAssertFalse(miss)
    }

    func testDeclareTwiceThrows() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        do {
            _ = try await store.declare(
                name: "rate", value: .integer(40),
                descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
            XCTFail("expected alreadyDeclared")
        } catch let e as ROS2ParameterError {
            XCTAssertEqual(e, .alreadyDeclared(name: "rate"))
        }
    }

    func testUndeclareRemoves() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        try await store.undeclare(name: "rate")
        let hit = await store.has(name: "rate")
        XCTAssertFalse(hit)
    }

    func testUndeclareUnknownThrows() async {
        let store = ParameterStore()
        do {
            try await store.undeclare(name: "rate")
            XCTFail("expected notDeclared")
        } catch let e as ROS2ParameterError {
            XCTAssertEqual(e, .notDeclared(name: "rate"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
