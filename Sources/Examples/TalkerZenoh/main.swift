// Minimal std_msgs/String publisher over Zenoh — mirrors the shape of
// demo_nodes_cpp/talker.cpp. Publishes "Hello World: N" on /chatter at 1 Hz.
//
// Usage: swift run talker_zenoh [tcp/<host>:7447]

import Foundation
import SwiftROS2

let locator = CommandLine.arguments.dropFirst().first ?? "tcp/127.0.0.1:7447"

let ctx = try await ROS2Context(
    transport: .zenoh(locator: locator),
    distro: .jazzy
)
let node = try await ctx.createNode(name: "talker")
let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")

var count = 0
while !Task.isCancelled {
    count += 1
    let msg = StringMsg(data: "Hello World: \(count)")
    try pub.publish(msg)
    print("Publishing: '\(msg.data)'")
    try await Task.sleep(nanoseconds: 1_000_000_000)
}

await ctx.shutdown()
