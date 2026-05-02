// ClientPendingTableTests.swift
// Insert / resolve / cancel / failAll behaviors of the per-client correlation table.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class ClientPendingTableTests: XCTestCase {
    func testInsertAndResolve() async throws {
        let table = ClientPendingTable()
        async let pending: Data = table.insert(seq: 1) { _ in /* will be resolved externally */  }
        try await Task.sleep(nanoseconds: 10_000_000)
        let didResolve = await table.resolve(seq: 1, with: .success(Data([0x01])))
        XCTAssertTrue(didResolve)
        let value = try await pending
        XCTAssertEqual(value, Data([0x01]))
    }

    func testResolveByOtherCaller() async throws {
        let table = ClientPendingTable()
        async let pending: Data = table.insert(seq: 7) { _ in /* will be resolved externally */  }
        try await Task.sleep(nanoseconds: 10_000_000)
        let didResolve = await table.resolve(seq: 7, with: .success(Data([0xAA])))
        XCTAssertTrue(didResolve)
        let value = try await pending
        XCTAssertEqual(value, Data([0xAA]))
    }

    func testResolveUnknownSeqIsNoOp() async {
        let table = ClientPendingTable()
        let didResolve = await table.resolve(seq: 999, with: .success(Data()))
        XCTAssertFalse(didResolve)
    }

    func testFailAllResolvesAllPending() async throws {
        let table = ClientPendingTable()
        async let a: Data = table.insert(seq: 1) { _ in }
        async let b: Data = table.insert(seq: 2) { _ in }
        try await Task.sleep(nanoseconds: 10_000_000)
        await table.failAll(TransportError.sessionClosed)
        do {
            _ = try await a
            XCTFail("should throw")
        } catch {}
        do {
            _ = try await b
            XCTFail("should throw")
        } catch {}
    }
}
