# ROS 2 Actions

Long-running, cancelable, feedback-emitting RPCs over Zenoh or DDS.

## Overview

A ROS 2 action is built from three message types — `Goal`, `Result`, and `Feedback` — and
two more capabilities the simple Service contract doesn't have:

1. **Cancelability.** The client can ask the server to abort an in-flight goal.
2. **Streaming feedback.** While the goal is executing, the server publishes intermediate
   updates that the client iterates as an `AsyncStream`.

`swift-ros2` exposes both sides through a pure Swift Concurrency surface: no callback
shims, no thread pinning. The umbrella `SwiftROS2` module ships everything you need.

## Defining an action type

Conform an `enum` to ``SwiftROS2Messages/ROS2Action`` and supply three nested types:

```swift
import SwiftROS2

public enum MyAction: ROS2Action {
    public static let typeInfo = ROS2ActionTypeInfo(
        actionName: "my_pkg/action/My",
        goalTypeHash: "RIHS01_…",
        // … five more synthesized hashes; see SwiftROS2Messages/BuiltinActions/ExampleInterfaces/Fibonacci.swift
        resultTypeHash: nil,
        feedbackTypeHash: nil,
        sendGoalRequestTypeHash: nil,
        sendGoalResponseTypeHash: nil,
        getResultRequestTypeHash: nil,
        getResultResponseTypeHash: nil,
        feedbackMessageTypeHash: nil
    )
    public struct Goal: CDRCodable, Sendable, Equatable { /* … */ }
    public struct Result: CDRCodable, Sendable, Equatable { /* … */ }
    public struct Feedback: CDRCodable, Sendable, Equatable { /* … */ }
}
```

For convenience, ``SwiftROS2Messages/FibonacciAction`` is built in.

## Server side

Implement ``ActionServerHandler`` — typically as an `actor`:

```swift
actor MyHandler: ActionServerHandler {
    typealias Action = MyAction
    func handleGoal(_ g: MyAction.Goal) async -> GoalResponse { .accept }
    func handleCancel(_ h: ActionGoalHandle<MyAction>) async -> CancelResponse { .accept }
    func execute(_ h: ActionGoalHandle<MyAction>) async throws -> MyAction.Result {
        for _ in 1...10 {
            try Task.checkCancellation()
            if await h.isCancelRequested { throw CancellationError() }
            try await h.publishFeedback(MyAction.Feedback(/* … */))
            try await Task.sleep(for: .milliseconds(100))
        }
        return MyAction.Result(/* … */)
    }
}

let server = try await node.createActionServer(
    MyAction.self,
    name: "/my_action",
    handler: MyHandler()
)
```

## Client side

```swift
let client = try await node.createActionClient(MyAction.self, name: "/my_action")
try await client.waitForActionServer(timeout: .seconds(5))
let handle = try await client.sendGoal(MyAction.Goal(/* … */))

Task {
    for await fb in handle.feedback {
        print("Feedback: \(fb)")
    }
}

let result = try await handle.result()
switch result {
case .succeeded(let r): print("Got \(r)")
case .canceled: print("Canceled")
case .aborted(let reason): print("Aborted: \(reason ?? "nil")")
}
```

To cancel a single goal: `try await handle.cancel()`.
To cancel every active goal at-or-before a timestamp: `try await client.cancelGoals(beforeStamp: …)`.

## QoS

The default ``QoSProfile/actionDefault`` is `reliable / volatile / keep-last 10` — same as
`rmw_qos_profile_services_default` on rclcpp. The transport layer applies a per-role
override on the `_action/status` topic (`transient_local / depth 1`) so late-joining
clients see the latest known status.

## Topics under the hood

For an action `<ns>/<name>`, the wire layer materializes:

| Role | Kind | Wire name |
|---|---|---|
| `send_goal` | service | `<ns>/<name>/_action/send_goal` |
| `cancel_goal` | service | `<ns>/<name>/_action/cancel_goal` |
| `get_result` | service | `<ns>/<name>/_action/get_result` |
| `feedback` | topic | `<ns>/<name>/_action/feedback` |
| `status` | topic | `<ns>/<name>/_action/status` |

You don't see these from Swift code — they're formatted by ``SwiftROS2Wire/ZenohWireCodec``
and ``SwiftROS2Wire/DDSWireCodec``.
