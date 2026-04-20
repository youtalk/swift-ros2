// Minimal std_msgs/String publisher — mirrors demo_nodes_cpp/talker.cpp.
// Publishes "Hello World: N" on /chatter at 1 Hz.
//
// Usage:
//   swift run talker zenoh [tcp/<host>:7447]
//   swift run talker dds   [domain_id]

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
