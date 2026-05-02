import Foundation
import XCTest

@testable import SwiftROS2Transport
@testable import SwiftROS2Zenoh

/// LAN-gated smoke test that exercises `declareQueryable` + `get` against a
/// live `rmw_zenohd` router on `tcp/<LINUX_IP>:7447`. Skipped when `LINUX_IP`
/// is unset.
final class ZenohQueryableSmokeTests: XCTestCase {
    private var skipReason: String? {
        ProcessInfo.processInfo.environment["LINUX_IP"] == nil
            ? "LINUX_IP unset; skipping live zenoh router test"
            : nil
    }

    func testDeclareReplyUndeclare() async throws {
        try XCTSkipIf(skipReason != nil, skipReason ?? "")
        let linuxIP = ProcessInfo.processInfo.environment["LINUX_IP"] ?? ""

        let z = ZenohClient()
        try z.open(locator: "tcp/\(linuxIP):7447")
        defer { try? z.close() }

        let queryable = try z.declareQueryable("swift_srv_smoke/echo") { query in
            try? query.reply(payload: Data([0x01, 0x02]), attachment: nil)
        }

        let exp = expectation(description: "reply")
        try z.get(
            keyExpr: "swift_srv_smoke/echo",
            payload: nil,
            attachment: nil,
            timeoutMs: 1_000,
            handler: { result in
                if case .success(let sample) = result, sample.payload == Data([0x01, 0x02]) {
                    exp.fulfill()
                }
            },
            onFinish: {}
        )
        await fulfillment(of: [exp], timeout: 2)
        try queryable.close()
    }
}
