// Minimal std_msgs/String subscriber — mirrors demo_nodes_cpp/listener.cpp.
// Prints every message received on /chatter.
//
// Usage:
//   swift run listener zenoh [tcp/<host>:7447] [domain_id]
//
// Note: DDS subscribe is not implemented in swift-ros2 yet (the transport
// layer throws "DDS subscriber not yet implemented"), so `dds` is rejected
// up front here. Use zenoh for now.

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
    FileHandle.standardError.write(Data("DDS subscribe is not yet supported by swift-ros2; use zenoh.\n".utf8))
    exit(2)
default:
    FileHandle.standardError.write(Data("Unknown transport '\(transportName)'. Use 'zenoh'.\n".utf8))
    exit(2)
}

let ctx = try await ROS2Context(transport: transport, distro: .jazzy)
let node = try await ctx.createNode(name: "listener")
let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")

print("Listening on /chatter...")
for await msg in sub.messages {
    print("I heard: '\(msg.data)'")
}

await ctx.shutdown()
