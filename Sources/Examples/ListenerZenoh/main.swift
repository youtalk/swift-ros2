// Minimal std_msgs/String subscriber over Zenoh — mirrors the shape of
// demo_nodes_cpp/listener.cpp. Prints every message received on /chatter.
//
// Usage: swift run listener_zenoh [tcp/<host>:7447]

import Foundation
import SwiftROS2

let locator = CommandLine.arguments.dropFirst().first ?? "tcp/127.0.0.1:7447"

let ctx = try await ROS2Context(
    transport: .zenoh(locator: locator),
    distro: .jazzy
)
let node = try await ctx.createNode(name: "listener")
let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")

print("Listening on /chatter...")
for await msg in sub.messages {
    print("I heard: '\(msg.data)'")
}

await ctx.shutdown()
