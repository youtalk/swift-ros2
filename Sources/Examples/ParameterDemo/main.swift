// Minimal parameter-server demo. Declares three parameters and idles
// forever, so external tooling (`ros2 param list/get/set/describe`,
// `rqt_param`) can drive the node from a second terminal.
//
// Usage:
//   swift run parameter-demo zenoh [tcp/<host>:7447] [domain_id]
//   swift run parameter-demo dds   [domain_id]

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
    FileHandle.standardError.write(
        Data("Unknown transport '\(transportName)'. Use 'zenoh' or 'dds'.\n".utf8))
    exit(2)
}

let ctx = try await ROS2Context(transport: transport, distro: .jazzy)
let node = try await ctx.createNode(name: "parameter_demo")

_ = try await node.declareParameter(
    "rate",
    default: Int64(30),
    descriptor: ROS2ParameterDescriptor(
        name: "rate",
        type: .integer,
        description: "publish rate in Hz",
        integerRange: Int64(1)...Int64(120)))

_ = try await node.declareParameter(
    "greeting",
    default: "Hello, ROS 2",
    descriptor: ROS2ParameterDescriptor(
        name: "greeting",
        type: .string,
        description: "greeting message"))

_ = try await node.declareParameter(
    "enabled",
    default: true,
    descriptor: ROS2ParameterDescriptor(
        name: "enabled",
        type: .bool,
        description: "publish on/off toggle"))

_ = await node.setOnSetParametersCallback { proposed in
    // Reject `rate` outside 1..120 even if the descriptor is bypassed.
    for p in proposed {
        if p.name == "rate", case .integer(let v) = p.value, !(1...120).contains(v) {
            return .failure(reason: "rate must be in [1, 120]")
        }
    }
    return .success()
}

print("parameter_demo running. Try:")
print("  ros2 param list /parameter_demo")
print("  ros2 param get  /parameter_demo rate")
print("  ros2 param set  /parameter_demo rate 60")
print("  ros2 param describe /parameter_demo greeting")

while !Task.isCancelled {
    try await Task.sleep(nanoseconds: 1_000_000_000)
}

await ctx.shutdown()
