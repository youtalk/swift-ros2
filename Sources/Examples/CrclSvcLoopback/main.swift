// crcl-svc-loopback — M7 service round-trip gate.
//
// One process, one rcl context: a service server and a service client for
// example_interfaces/AddTwoInts share the name "add_two_ints". Every call
// travels the full public createService / createClient surface end-to-end:
// CDREncoder -> rmw_deserialize shim -> typed rcl service server ->
// user handler -> rmw_serialize shim -> rcl_take_response -> CDRDecoder.
// Two sequential calls with distinct operands discriminate correlation bugs
// (a response wired to the wrong request cannot satisfy both sums). On
// success prints "crcl_svc_loopback OK: …" + flush, then exits 0 (before
// context teardown, which can block on headless runners — ci-rcl bounds the
// run with SIGALRM and decides success on the OK line, consistent with
// crcl-loopback / crcl-golden / crcl-smoke).

import Foundation
import SwiftROS2

// Last-resort in-process bound (60 s): the per-phase budgets below already
// sum to 20 s (waitForService 10 + two 5 s calls) and ASan startup adds
// seconds, so leave real headroom while staying far under ci-rcl's outer
// 150 s bound. If anything wedges past every per-phase timeout, SIGALRM's
// default disposition kills the process before the OK line is printed, so
// the CI grep still fails deterministically.
alarm(60)

func fail(_ reason: String) -> Never {
    print("crcl_svc_loopback FAIL: \(reason)")
    fflush(stdout)
    exit(1)
}

let ctx: ROS2Context
do {
    ctx = try await ROS2Context(transport: .rcl(domainId: 0))
} catch {
    fail("ROS2Context creation threw: \(error)")
}

// Parameter services are deferred on the rcl backend (they land in a
// follow-up after the services PR) — start the node without them, same as
// crcl-loopback.
let node: ROS2Node
do {
    node = try await ctx.createNode(
        name: "crcl_svc_loopback",
        namespace: "/loopback",
        options: ROS2NodeOptions(startParameterServices: false)
    )
} catch {
    fail("createNode threw: \(error)")
}

// Server first so the reader/writer pairs are advertised before the client
// starts looking for them.
do {
    _ = try await node.createService(AddTwoIntsSrv.self, name: "add_two_ints") { request in
        AddTwoIntsResponse(sum: request.a + request.b)
    }
} catch {
    fail("createService threw: \(error)")
}

let cli: ROS2Client<AddTwoIntsSrv>
do {
    cli = try await node.createClient(AddTwoIntsSrv.self, name: "add_two_ints")
} catch {
    fail("createClient threw: \(error)")
}

// Readiness via the seam's graph poll (rcl_service_server_is_available)
// instead of a blind sleep — in-process SEDP matching usually settles well
// under a second, but allow up to 10 s for slow ASan runners.
do {
    try await cli.waitForService(timeout: .seconds(10))
} catch {
    fail("waitForService threw: \(error)")
}

// Two sequential calls with distinct operands — a correlation bug (response
// resolved against the wrong request) cannot produce both expected sums.
let first: AddTwoIntsResponse
do {
    first = try await cli.call(AddTwoIntsRequest(a: 2, b: 3), timeout: .seconds(5))
} catch {
    fail("call #1 threw: \(error)")
}
guard first.sum == 5 else {
    fail("call #1 sum mismatch: \(first.sum) != 5")
}

let second: AddTwoIntsResponse
do {
    second = try await cli.call(AddTwoIntsRequest(a: -7, b: 40), timeout: .seconds(5))
} catch {
    fail("call #2 threw: \(error)")
}
guard second.sum == 33 else {
    fail("call #2 sum mismatch: \(second.sum) != 33")
}

print("crcl_svc_loopback OK: AddTwoInts 2+3=5, -7+40=33")
fflush(stdout)

// Best-effort teardown after the OK line: on a headless runner CycloneDDS
// teardown can block, and ci-rcl's SIGALRM bound + OK-line grep absorb that.
await ctx.shutdown()
exit(0)
