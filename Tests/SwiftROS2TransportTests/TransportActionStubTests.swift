// TransportActionStubTests.swift
// Phase 3: verify the new TransportError cases compile and carry the expected payload.

import XCTest

@testable import SwiftROS2Transport

final class TransportActionStubTests: XCTestCase {
    func testActionErrorDescriptions() {
        XCTAssertEqual(
            TransportError.goalRejected.errorDescription,
            "Action goal was rejected by the server"
        )
        XCTAssertEqual(
            TransportError.goalUnknown.errorDescription,
            "Action goal id is unknown to the server"
        )
        XCTAssertEqual(
            TransportError.actionServerUnavailable.errorDescription,
            "Action server is not reachable"
        )
    }

    func testActionErrorIsRecoverable() {
        // Non-recoverable: server made a definitive decision.
        XCTAssertFalse(TransportError.goalRejected.isRecoverable)
        XCTAssertFalse(TransportError.goalUnknown.isRecoverable)
        // Recoverable: discovery may succeed later.
        XCTAssertTrue(TransportError.actionServerUnavailable.isRecoverable)
    }
}
