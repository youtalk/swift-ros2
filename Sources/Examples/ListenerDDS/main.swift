// Minimal std_msgs/String subscriber over DDS (CycloneDDS multicast) — mirrors
// demo_nodes_cpp/listener.cpp. Prints every message received on /chatter.
//
// Usage: swift run listener_dds [domain_id]

import Foundation
import SwiftROS2

let domainId = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 0

let ctx = try await ROS2Context(
    transport: .ddsMulticast(domainId: domainId),
    distro: .jazzy
)
let node = try await ctx.createNode(name: "listener")
let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")

print("Listening on /chatter...")
for await msg in sub.messages {
    print("I heard: '\(msg.data)'")
}

await ctx.shutdown()
