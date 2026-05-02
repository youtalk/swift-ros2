# Getting Started with Zenoh

Publish and subscribe to ROS 2 topics over Zenoh in fewer than ten lines.

## Overview

Zenoh works on every platform SwiftROS2 supports. You need a running Zenoh
router (typically `rmw_zenohd`) reachable on TCP. The router locator
(`tcp/<host>:7447`) is the only configuration you must provide.

## Publish

```swift
import SwiftROS2
import SwiftROS2Messages

let ctx = try await ROS2Context(
    transport: .zenoh(locator: "tcp/192.168.1.10:7447")
)
let node = try await ctx.createNode(name: "talker", namespace: "/demo")
let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")

for i in 0..<100 {
    try pub.publish(StringMsg(data: "hello \(i)"))
    try await Task.sleep(nanoseconds: 100_000_000)
}

await ctx.shutdown()
```

## Subscribe

```swift
let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")
for await msg in sub.messages {
    print("Received:", msg.data)
}
```
