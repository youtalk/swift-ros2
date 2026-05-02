// Minimal std_srvs/srv/Trigger service server — mirrors demo_nodes_cpp/add_two_ints_server.cpp.
// Replies "ok" to every Trigger request on /trigger.
//
// Usage:
//   swift run srv-server zenoh [tcp/<host>:7447] [domain_id]
//   swift run srv-server dds   [domain_id]

import Foundation
import SwiftROS2

let args = Array(CommandLine.arguments.dropFirst())
let transportName = args.first ?? "zenoh"

let transport: TransportConfig
switch transportName {
case "zenoh":
    let locator = args.dropFirst().first ?? "tcp/127.0.0.1:7447"
    let domainId = args.dropFirst(2).first.flatMap(Int.init) ?? 0
    transport = .zenoh(locator: locator, domainId: domainId)
case "dds":
    let domainId = args.dropFirst().first.flatMap(Int.init) ?? 0
    transport = .ddsMulticast(domainId: domainId)
default:
    FileHandle.standardError.write(Data("Unknown transport '\(transportName)'. Use 'zenoh' or 'dds'.\n".utf8))
    exit(2)
}

let ctx = try await ROS2Context(transport: transport, distro: .jazzy)
let node = try await ctx.createNode(name: "srv_server")

let svc = try await node.createService(TriggerSrv.self, name: "/trigger") { _ in
    print("Received Trigger request")
    return TriggerSrv.Response(success: true, message: "ok")
}

print("Service /trigger ready (\(svc.name))")

// Keep the process alive until interrupted.
while !Task.isCancelled {
    try await Task.sleep(nanoseconds: 1_000_000_000)
}

await ctx.shutdown()
