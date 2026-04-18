import XCTest
@testable import SwiftROS2Zenoh
import SwiftROS2Transport

// A foreign key-expression handle that is NOT a DeclaredKeyExpr from DefaultZenohClient.
// Used to exercise the foreign-handle rejection guard in put(keyExpr:payload:attachment:).
private final class ForeignKeyExprHandle: ZenohKeyExprHandle {}

final class DefaultZenohClientSmokeTests: XCTestCase {
    func testInitializationDoesNotCrash() {
        _ = DefaultZenohClient()
    }

    /// Verifies that passing a foreign ZenohKeyExprHandle to put() throws ZenohError.invalidParameter.
    ///
    /// The foreign-handle guard in DefaultZenohClient.put(keyExpr:payload:attachment:) runs
    /// BEFORE the session-open guard, so this test does not need a live Zenoh router.
    func testForeignKeyExprHandleIsRejected() throws {
        let client = DefaultZenohClient()
        let foreign = ForeignKeyExprHandle()

        XCTAssertThrowsError(try client.put(keyExpr: foreign, payload: Data(), attachment: nil)) { error in
            guard let zErr = error as? ZenohError else {
                XCTFail("Expected ZenohError, got \(type(of: error))")
                return
            }
            if case .invalidParameter = zErr {
                // Correct: foreign handle was rejected before any C call ran.
            } else {
                XCTFail("Expected .invalidParameter, got \(zErr)")
            }
        }
    }

    /// Verifies that calling close() on a client that was never opened throws ZenohError.sessionCloseFailed.
    func testDoubleCloseOnFreshClientThrows() throws {
        let client = DefaultZenohClient()
        XCTAssertThrowsError(try client.close()) { error in
            guard let zErr = error as? ZenohError else {
                XCTFail("Expected ZenohError, got \(type(of: error))")
                return
            }
            if case .sessionCloseFailed = zErr {
                // Correct: closing a never-opened client is reported as sessionCloseFailed.
            } else {
                XCTFail("Expected .sessionCloseFailed, got \(zErr)")
            }
        }
    }
}
