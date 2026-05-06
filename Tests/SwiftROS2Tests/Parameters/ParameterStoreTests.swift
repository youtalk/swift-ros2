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

    func testSetExistingValue() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        let r = await store.set(
            ROS2Parameter(name: "rate", value: .integer(60)))
        XCTAssertTrue(r.successful)
        let p = try await store.get(name: "rate")
        XCTAssertEqual(p.value, .integer(60))
    }

    func testSetUnknownFails() async {
        let store = ParameterStore()
        let r = await store.set(
            ROS2Parameter(name: "rate", value: .integer(30)))
        XCTAssertFalse(r.successful)
        XCTAssertTrue(r.reason.contains("rate"))
    }

    func testSetReadOnlyFails() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "k", value: .string("v"),
            descriptor: ROS2ParameterDescriptor(
                name: "k", type: .string, readOnly: true))
        let r = await store.set(
            ROS2Parameter(name: "k", value: .string("w")))
        XCTAssertFalse(r.successful)
        XCTAssertTrue(r.reason.contains("read"))
    }

    func testSetWrongTypeFailsWhenNotDynamic() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        let r = await store.set(
            ROS2Parameter(name: "rate", value: .string("nope")))
        XCTAssertFalse(r.successful)
    }

    func testSetWrongTypeAllowedWhenDynamic() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "k", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(
                name: "k", type: .integer, dynamicTyping: true))
        let r = await store.set(
            ROS2Parameter(name: "k", value: .string("hi")))
        XCTAssertTrue(r.successful)
    }

    func testSetIntegerOutOfRange() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate", value: .integer(30),
            descriptor: ROS2ParameterDescriptor(
                name: "rate", type: .integer, integerRange: 1...120))
        let r = await store.set(
            ROS2Parameter(name: "rate", value: .integer(999)))
        XCTAssertFalse(r.successful)
        XCTAssertTrue(r.reason.contains("range"))
    }

    func testSetDoubleOutOfRange() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "g", value: .double(0.5),
            descriptor: ROS2ParameterDescriptor(
                name: "g", type: .double, floatingPointRange: 0.0...1.0))
        let r = await store.set(
            ROS2Parameter(name: "g", value: .double(2.0)))
        XCTAssertFalse(r.successful)
    }

    func testSetManyReportsPerEntry() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "a", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(name: "a", type: .integer))
        _ = try await store.declare(
            name: "b", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(
                name: "b", type: .integer, integerRange: 0...10))
        let rs = await store.setMany([
            ROS2Parameter(name: "a", value: .integer(5)),
            ROS2Parameter(name: "b", value: .integer(999)),
        ])
        XCTAssertEqual(rs.count, 2)
        XCTAssertTrue(rs[0].successful)
        XCTAssertFalse(rs[1].successful)
        // a should be applied even though b failed
        let a = try await store.get(name: "a")
        let b = try await store.get(name: "b")
        XCTAssertEqual(a.value, .integer(5))
        XCTAssertEqual(b.value, .integer(0))
    }

    func testSetAtomicallyRollsBack() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "a", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(name: "a", type: .integer))
        _ = try await store.declare(
            name: "b", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(
                name: "b", type: .integer, integerRange: 0...10))
        let r = await store.setAtomically([
            ROS2Parameter(name: "a", value: .integer(5)),
            ROS2Parameter(name: "b", value: .integer(999)),
        ])
        XCTAssertFalse(r.successful)
        let a = try await store.get(name: "a")
        let b = try await store.get(name: "b")
        XCTAssertEqual(a.value, .integer(0), "a must have rolled back")
        XCTAssertEqual(b.value, .integer(0))
    }

    // MARK: - declare-time validation (added in PR #103 review)

    func testDeclareRejectsTypeMismatch() async {
        let store = ParameterStore()
        do {
            _ = try await store.declare(
                name: "rate", value: .string("30"),
                descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
            XCTFail("expected invalidValue")
        } catch let e as ROS2ParameterError {
            guard case .invalidValue = e else {
                XCTFail("wrong case: \(e)")
                return
            }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDeclareRejectsOutOfRangeDefault() async {
        let store = ParameterStore()
        do {
            _ = try await store.declare(
                name: "rate", value: .integer(999),
                descriptor: ROS2ParameterDescriptor(
                    name: "rate", type: .integer, integerRange: 1...120))
            XCTFail("expected invalidValue")
        } catch let e as ROS2ParameterError {
            guard case .invalidValue = e else {
                XCTFail("wrong case: \(e)")
                return
            }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDeclareAllowsReadOnlyInitialValue() async throws {
        // declare IS the one legal write to a read-only parameter.
        let store = ParameterStore()
        _ = try await store.declare(
            name: "k", value: .string("v"),
            descriptor: ROS2ParameterDescriptor(
                name: "k", type: .string, readOnly: true))
        let p = try await store.get(name: "k")
        XCTAssertEqual(p.value, .string("v"))
    }

    func testListWithDepthGreaterThanIntMaxDoesNotTrap() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "a", value: .integer(0),
            descriptor: ROS2ParameterDescriptor(name: "a", type: .integer))
        let r = await store.list(prefixes: [], depth: UInt64.max)
        XCTAssertEqual(r.names, ["a"])
    }

    func testEntryReturnsNilForUndeclared() async {
        let store = ParameterStore()
        let result = await store.entry(name: "missing")
        XCTAssertNil(result)
    }

    func testEntryReturnsValueAndDescriptorForDeclared() async throws {
        let store = ParameterStore()
        _ = try await store.declare(
            name: "rate",
            value: .integer(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        let entry = await store.entry(name: "rate")
        XCTAssertEqual(entry?.value, .integer(30))
        XCTAssertEqual(entry?.descriptor.type, .integer)
    }

    func testMarkServicesStartedIsOneShot() async {
        let store = ParameterStore()
        let first = await store.markServicesStarted()
        let second = await store.markServicesStarted()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testRegisterCallbackReturnsUniqueHandle() async {
        let store = ParameterStore()
        let h1 = await store.registerOnSet { _ in .success() }
        let h2 = await store.registerOnSet { _ in .success() }
        XCTAssertNotEqual(h1, h2)
    }

    func testUnregisterCallbackReturnsTrueOnce() async {
        let store = ParameterStore()
        let h = await store.registerOnSet { _ in .success() }
        let firstRemove = await store.unregisterCallback(h)
        let secondRemove = await store.unregisterCallback(h)
        XCTAssertTrue(firstRemove)
        XCTAssertFalse(secondRemove)
    }
}
