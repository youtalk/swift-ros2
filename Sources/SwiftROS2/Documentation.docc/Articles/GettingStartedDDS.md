# Getting Started with DDS

Use CycloneDDS directly (no router) on Apple platforms or Linux.

## Overview

DDS uses multicast discovery by default. If your network does not allow
multicast (e.g. many Wi-Fi setups), switch to unicast and supply the peer
address(es).

## Multicast

```swift
import SwiftROS2

let ctx = try await ROS2Context(transport: .ddsMulticast(domainId: 0))
let node = try await ctx.createNode(name: "talker")
let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")
```

## Unicast (Wi-Fi without multicast)

```swift
let peers = [DDSPeer(address: "192.168.1.10", port: 7400)]
let ctx = try await ROS2Context(transport: .ddsUnicast(peers: peers, domainId: 0))
```

## Domain ID and discovery port

CycloneDDS computes the discovery port as `7400 + domainId * 250`. SwiftROS2
exposes the same formula via `DDSPeer.discoveryPort(forDomain:)`.
