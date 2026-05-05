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

    func testGetReturnsValue() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        let p = try await store.get(name: "rate")
        XCTAssertEqual(p, ROS2Parameter(name: "rate", value: .integer(30)))
    }

    func testGetUnknownThrows() async {
        let store = ParameterStore()
        do {
            _ = try await store.get(name: "rate")
            XCTFail("expected notDeclared")
        } catch let e as ROS2ParameterError {
            XCTAssertEqual(e, .notDeclared(name: "rate"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDescribeReturnsDescriptor() async throws {
        let store = ParameterStore()
        let d = ROS2ParameterDescriptor(
            name: "rate", type: .integer, integerRange: 1...120)
        _ = try await store.declare(
            name: "rate", value: .integer(30), descriptor: d)
        let got = try await store.describe(name: "rate")
        XCTAssertEqual(got, d)
    }

    func testListAllNoPrefix() async throws {
        let store = try await populated()
        let r = await store.list(prefixes: [], depth: 0)
        XCTAssertEqual(Set(r.names), ["a", "b.c", "b.d.e"])
    }

    func testListByPrefix() async throws {
        let store = try await populated()
        let r = await store.list(prefixes: ["b"], depth: 0)
        XCTAssertEqual(Set(r.names), ["b.c", "b.d.e"])
    }

    func testListByPrefixWithDepth() async throws {
        let store = try await populated()
        // depth=1 means "no further . separators after the prefix"
        // so "b.c" matches but "b.d.e" does not.
        let r = await store.list(prefixes: ["b"], depth: 1)
        XCTAssertEqual(Set(r.names), ["b.c"])
    }

    private func populated() async throws -> ParameterStore {
        let s = ParameterStore()
        let d = ROS2ParameterDescriptor()
        _ = try await s.declare(name: "a", value: .integer(1), descriptor: d)
        _ = try await s.declare(name: "b.c", value: .integer(2), descriptor: d)
        _ = try await s.declare(name: "b.d.e", value: .integer(3), descriptor: d)
        return s
    }
}
