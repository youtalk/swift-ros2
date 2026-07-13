import SwiftROS2Transport
import XCTest

@testable import SwiftROS2Zenoh

// A foreign key-expression handle that is NOT a DeclaredKeyExpr from ZenohClient.
// Used to exercise the foreign-handle rejection guard in put(keyExpr:payload:attachment:).
private final class ForeignKeyExprHandle: ZenohKeyExprHandle {}

final class ZenohClientSmokeTests: XCTestCase {
    func testInitializationDoesNotCrash() {
        _ = ZenohClient(wireFallback: ())
    }

    // The deprecated public initializer must keep constructing a working
    // client through 1.x — the annotation is a migration signal, not a
    // behavior change. The test method carries the same deprecation so the
    // pinned usage compiles without a warning.
    @available(*, deprecated)
    func testDeprecatedPublicInitStillConstructs() {
        XCTAssertFalse(ZenohClient().isSessionHealthy())
    }

    /// Verifies that passing a foreign ZenohKeyExprHandle to put() throws ZenohError.invalidParameter.
    ///
    /// The foreign-handle guard in ZenohClient.put(keyExpr:payload:attachment:) runs
    /// BEFORE the session-open guard, so this test does not need a live Zenoh router.
    func testForeignKeyExprHandleIsRejected() throws {
        let client = ZenohClient(wireFallback: ())
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
        let client = ZenohClient(wireFallback: ())
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
