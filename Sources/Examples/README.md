# Examples

Two minimal executables that mirror [`demo_nodes_cpp`](https://github.com/ros2/demos/tree/rolling/demo_nodes_cpp)'s `talker` / `listener`. The transport is picked by the first CLI argument, so one binary covers both Zenoh and DDS.

| Target     | What it does                                      |
|------------|---------------------------------------------------|
| `talker`   | Publishes `std_msgs/String` on `/chatter` at 1 Hz |
| `listener` | Subscribes to `/chatter` and prints each message  |

Message type is `std_msgs/msg/String`, payload is `"Hello World: N"`. Default QoS is `.sensorData` (best-effort, keep-last-10).

## Invocation

```bash
swift run talker    zenoh [tcp/<host>:7447]   # default locator: tcp/127.0.0.1:7447
swift run talker    dds   [domain_id]         # default domain_id: 0
swift run listener  zenoh [tcp/<host>:7447]
swift run listener  dds   [domain_id]
```

The first argument selects the transport (`zenoh` or `dds`). The second is transport-specific: a Zenoh router locator or a ROS 2 domain ID. Both arguments default, so `swift run talker` alone targets a local Zenoh router at `tcp/127.0.0.1:7447`.

## Prerequisites

- macOS with Xcode 16+ **or** Ubuntu 22.04 / 24.04 with Swift 5.9+ and `ros-<distro>-cyclonedds` installed. See the top-level [`README.md`](../../README.md#installation) for per-platform setup.
- A ROS 2 install on the peer side (Humble / Jazzy / Kilted / Rolling). These demos default to the Jazzy wire format; edit `.distro:` on the `ROS2Context` call if you need Humble.
- **Zenoh only:** a running `rmw_zenoh_cpp` router (`ros2 run rmw_zenoh_cpp rmw_zenohd`) that both sides can reach over TCP.
- **DDS only:** a multicast-capable LAN on a shared `ROS_DOMAIN_ID` (default `0`). On Wi-Fi without multicast, switch to `.ddsUnicast(peers:)` — see below.

## Zenoh tutorial

### 1. Start a router

On any host reachable from both the Swift side and the ROS 2 side:

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 run rmw_zenoh_cpp rmw_zenohd            # listens on tcp/0.0.0.0:7447
```

### 2. Swift talker → ROS 2 listener

Terminal A (Swift publisher):

```bash
swift run talker zenoh tcp/<router-host>:7447
# Publishing: 'Hello World: 1'
# Publishing: 'Hello World: 2'
```

Terminal B (ROS 2 subscriber):

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 topic echo /chatter std_msgs/msg/String
# data: 'Hello World: 1'
# ---
# data: 'Hello World: 2'
```

### 3. ROS 2 talker → Swift listener

Terminal A (ROS 2 publisher):

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 run demo_nodes_cpp talker
```

Terminal B (Swift subscriber):

```bash
swift run listener zenoh tcp/<router-host>:7447
# Listening on /chatter...
# I heard: 'Hello World: 1'
```

### 4. Swift ↔ Swift

Runs entirely within swift-ros2, no ROS 2 install needed on either side:

```bash
# Terminal A
swift run talker   zenoh tcp/<router-host>:7447

# Terminal B
swift run listener zenoh tcp/<router-host>:7447
```

You still need a `rmw_zenohd` router in the middle — Zenoh peers rendezvous through it.

## DDS tutorial

CycloneDDS discovery is peer-to-peer, so there is no router. Just run on the same LAN + same `ROS_DOMAIN_ID`.

### 1. Swift talker → ROS 2 listener

Terminal A (Swift publisher):

```bash
swift run talker dds 0             # ROS_DOMAIN_ID = 0
```

Terminal B (ROS 2 subscriber):

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
ros2 topic echo /chatter std_msgs/msg/String
```

### 2. ROS 2 talker → Swift listener

Terminal A (ROS 2):

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
ros2 run demo_nodes_cpp talker
```

Terminal B (Swift):

```bash
swift run listener dds 0
```

### Wi-Fi (no multicast)

On networks that drop multicast, edit the demo's `.ddsMulticast(...)` call to use `.ddsUnicast(peers:)`:

```swift
transport = .ddsUnicast(
    peers: [DDSPeer.peer(address: "192.168.1.10", domainId: 0)],
    domainId: 0
)
```

Both sides must list each other. On the ROS 2 side, set `CYCLONEDDS_URI` — see [CycloneDDS config docs](https://cyclonedds.io/docs/cyclonedds/latest/config/config_file_reference.html) and the notes in the top-level README.

## Anatomy of a demo

Every example follows the same four steps:

```swift
import SwiftROS2

// 1. Open a context over the chosen transport.
let ctx = try await ROS2Context(
    transport: .zenoh(locator: "tcp/127.0.0.1:7447"),   // or .ddsMulticast(domainId: 0)
    distro: .jazzy
)

// 2. Create a node under that context.
let node = try await ctx.createNode(name: "talker")

// 3a. Publisher side.
let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")
try pub.publish(StringMsg(data: "Hello World: 1"))

// 3b. Subscription side.
let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")
for await msg in sub.messages { print(msg.data) }

// 4. Tear down.
await ctx.shutdown()
```

Swap `.zenoh(...)` ↔ `.ddsMulticast(...)` to switch transports — everything above step 1 is identical. That's the whole point of the umbrella API, and it's why the talker / listener demos collapse into a single binary each.

## Troubleshooting

- **`ros2 topic echo` prints nothing but `ros2 topic list` shows `/chatter`** — wire format mismatch. Pin `.distro:` on the Swift side to match the ROS 2 distro (e.g. `.humble` for Humble's pre-type-hash wire schema).
- **Connection refused on Zenoh** — router isn't running, wrong IP, or firewall blocks TCP `7447`.
- **DDS sees nothing** — wrong `ROS_DOMAIN_ID`, or the network drops multicast. Switch to `.ddsUnicast`.
- **`swift run` fails to find `talker`** — run it from the repo root (`deps/swift-ros2`), not a subdirectory; SPM resolves targets relative to `Package.swift`.
