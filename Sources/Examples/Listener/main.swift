// Minimal std_msgs/String subscriber — mirrors demo_nodes_cpp/listener.cpp.
// Prints every message received on /chatter.
//
// Usage:
//   swift run listener zenoh [tcp/<host>:7447]
//   swift run listener dds   [domain_id]

import Foundation
import SwiftROS2

let args = CommandLine.arguments.dropFirst()
let transportName = args.first ?? "zenoh"
let extra = args.dropFirst().first

let transport: TransportConfig
switch transportName {
case "zenoh":
    transport = .zenoh(locator: extra ?? "tcp/127.0.0.1:7447")
case "dds":
    transport = .ddsMulticast(domainId: Int(extra ?? "") ?? 0)
default:
    FileHandle.standardError.write(Data("Unknown transport '\(transportName)'. Use 'zenoh' or 'dds'.\n".utf8))
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
