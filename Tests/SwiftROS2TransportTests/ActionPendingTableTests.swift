// ActionPendingTableTests.swift
// Behavior tests for the action-side correlation actor.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class ActionPendingTableTests: XCTestCase {
    private func makeGoalId(_ b: UInt8) -> [UInt8] {
        return Array(repeating: b, count: 16)
    }

    func testYieldFeedbackToRegisteredStream() async throws {
        let table = ActionPendingTable()
        let id = makeGoalId(0xAA)
        var fbCont: AsyncStream<Data>.Continuation!
        let fb = AsyncStream<Data> { fbCont = $0 }
        var stCont: AsyncStream<ActionStatusUpdate>.Continuation!
        let st = AsyncStream<ActionStatusUpdate> { stCont = $0 }

        await table.registerStreams(goalId: id, feedback: fbCont, status: stCont)

        let yielded = await table.yieldFeedback(goalId: id, cdr: Data([0x42]))
        XCTAssertTrue(yielded)
        // Force completion so the iteration terminates.
        await table.cancel(goalId: id)

        var seen: [Data] = []
        for await frame in fb {
            seen.append(frame)
        }
        XCTAssertEqual(seen, [Data([0x42])])

        // Status stream is also finished by cancel().
        var statusSeen: [Int8] = []
        for await s in st {
            statusSeen.append(s.status)
        }
        XCTAssertTrue(statusSeen.isEmpty)
    }

    func testYieldFeedbackUnknownGoalIsNoOp() async {
        let table = ActionPendingTable()
        let yielded = await table.yieldFeedback(goalId: makeGoalId(0x01), cdr: Data())
        XCTAssertFalse(yielded)
    }

    func testTerminalStatusFinishesStreams() async throws {
        let table = ActionPendingTable()
        let id = makeGoalId(0xBB)
        var fbCont: AsyncStream<Data>.Continuation!
        let fb = AsyncStream<Data> { fbCont = $0 }
        var stCont: AsyncStream<ActionStatusUpdate>.Continuation!
        let st = AsyncStream<ActionStatusUpdate> { stCont = $0 }

        await table.registerStreams(goalId: id, feedback: fbCont, status: stCont)

        // STATUS_EXECUTING — non-terminal, streams stay open.
        await table.yieldStatus(goalId: id, status: 2)
        // STATUS_SUCCEEDED — terminal, streams close.
        await table.yieldStatus(goalId: id, status: 4)

        var statusValues: [Int8] = []
        for await s in st {
            statusValues.append(s.status)
        }
        XCTAssertEqual(statusValues, [2, 4])

        var fbValues: [Data] = []
        for await frame in fb {
            fbValues.append(frame)
        }
        XCTAssertTrue(fbValues.isEmpty)
    }

    func testResolveResultBeforeRegisterCachesValue() async throws {
        let table = ActionPendingTable()
        let id = makeGoalId(0xCC)

        // Result arrives before any caller registers — value is cached.
        let inlineResolved = await table.resolveResult(
            goalId: id,
            ack: GetResultAck(status: 4, resultCDR: Data([0x77]))
        )
        XCTAssertFalse(inlineResolved, "no continuation yet → false")

        // Now `getResult` registers — should resolve from the cached value immediately.
        let value = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<GetResultAck, Error>) in
            Task {
                await table.registerResult(goalId: id, continuation: cont)
            }
        }
        XCTAssertEqual(value.status, 4)
        XCTAssertEqual(value.resultCDR, Data([0x77]))

        // Entry is gone.
        let count = await table.count
        XCTAssertEqual(count, 0)
    }

    func testResolveResultAfterRegisterResolvesInline() async throws {
        let table = ActionPendingTable()
        let id = makeGoalId(0xDD)

        async let result: GetResultAck = withCheckedThrowingContinuation { cont in
            Task { await table.registerResult(goalId: id, continuation: cont) }
        }
        // Give the registration a beat to land.
        try await Task.sleep(nanoseconds: 10_000_000)

        let inlineResolved = await table.resolveResult(
            goalId: id,
            ack: GetResultAck(status: 5, resultCDR: Data([0x99]))
        )
        XCTAssertTrue(inlineResolved)

        let r = try await result
        XCTAssertEqual(r.status, 5)
        XCTAssertEqual(r.resultCDR, Data([0x99]))
    }

    func testCancelThrowsRequestCancelledFromResult() async {
        let table = ActionPendingTable()
        let id = makeGoalId(0xEE)
        var fbCont: AsyncStream<Data>.Continuation!
        _ = AsyncStream<Data> { fbCont = $0 }
        var stCont: AsyncStream<ActionStatusUpdate>.Continuation!
        _ = AsyncStream<ActionStatusUpdate> { stCont = $0 }

        await table.registerStreams(goalId: id, feedback: fbCont, status: stCont)

        async let result: GetResultAck = withCheckedThrowingContinuation { cont in
            Task { await table.registerResult(goalId: id, continuation: cont) }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await table.cancel(goalId: id)

        do {
            _ = try await result
            XCTFail("expected requestCancelled")
        } catch let err as TransportError {
            if case .requestCancelled = err { return }
            XCTFail("got \(err) instead of requestCancelled")
        } catch {
            XCTFail("non-TransportError: \(error)")
        }
    }

    func testFailAllResolvesEveryPending() async {
        let table = ActionPendingTable()
        let a = makeGoalId(0x01)
        let b = makeGoalId(0x02)
        var aFB: AsyncStream<Data>.Continuation!
        _ = AsyncStream<Data> { aFB = $0 }
        var aST: AsyncStream<ActionStatusUpdate>.Continuation!
        _ = AsyncStream<ActionStatusUpdate> { aST = $0 }
        await table.registerStreams(goalId: a, feedback: aFB, status: aST)

        async let resA: GetResultAck = withCheckedThrowingContinuation {
            cont in
            Task { await table.registerResult(goalId: a, continuation: cont) }
        }
        async let resB: GetResultAck = withCheckedThrowingContinuation {
            cont in
            Task { await table.registerResult(goalId: b, continuation: cont) }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await table.failAll(TransportError.sessionClosed)

        do {
            _ = try await resA
            XCTFail("expected throw")
        } catch {}
        do {
            _ = try await resB
            XCTFail("expected throw")
        } catch {}

        let count = await table.count
        XCTAssertEqual(count, 0)
    }
}
