import SwiftROS2
import XCTest

/// 2.0.0: the wire clients are an implementation detail. This file runs the
/// MIGRATION.md "1.x -> 2.0" connectivity-probe recipe — the replacement for a
/// 1.x `ZenohClient` open / close probe — end-to-end against the `SwiftROS2`
/// umbrella, imported without `@testable`.
///
/// What it proves: the documented migration recipe compiles and runs against
/// the umbrella. What it cannot prove: that the umbrella API stays `public`.
/// `package` declarations are visible to every module of this package, test
/// targets included, so a demotion of umbrella API would still compile here.
/// The public-surface lock is the API-breakage gate
/// (`Scripts/diagnose-api-breaking-changes.sh` against the previous tag) plus
/// the post-tag external consumer smoke. The gate catches removals and
/// signature changes, but SwiftPM's ABI digest also lists `package`
/// declarations, so a `public` -> `package` flip only shows up in the
/// external consumer smoke.
final class PublicSurfaceTests: XCTestCase {
    func testConnectivityProbeRecipeCompilesAndRuns() async {
        // Mirrors the MIGRATION "1.x -> 2.0" recipe. Nothing listens on this
        // port, so the open is expected to fail; the recipe must still run
        // through open / inspect / shutdown without crashing.
        do {
            let ctx = try await ROS2Context(transport: .zenoh(locator: "tcp/127.0.0.1:1"))
            _ = ctx.isConnected
            _ = ctx.sessionId
            await ctx.shutdown()
        } catch {
            // expected: connection refused
        }
    }
}
