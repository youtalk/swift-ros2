// ActionServerHandler.swift
// User-supplied protocol for ROS 2 Action servers.

import SwiftROS2Messages

/// User-implemented protocol for an action server.
///
/// Typically implemented as an `actor`. The umbrella `ROS2ActionServer<H>`
/// owns one Task per accepted goal and dispatches into these methods.
///
/// Lifecycle: `handleGoal` decides accept / reject; on accept the umbrella
/// spawns a Task that calls `execute`; if a cancel arrives during execution,
/// the umbrella calls `handleCancel` (the handler decides accept / reject) and
/// — on accept — cancels the executing Task. The handler's `execute`
/// implementation must check `await handle.isCancelRequested` periodically and
/// throw `CancellationError` (or any error) to abort.
public protocol ActionServerHandler: Sendable {
    associatedtype Action: ROS2Action

    /// Decide whether to accept a new goal. Called once per inbound goal,
    /// before the umbrella spawns the executing Task.
    func handleGoal(_ goal: Action.Goal) async -> GoalResponse

    /// Decide whether to honor a cancel request. Called when the client side
    /// requests cancellation of a goal that is currently executing.
    func handleCancel(_ handle: ActionGoalHandle<Action>) async -> CancelResponse

    /// Run the goal. Must produce the final `Action.Result` or throw to abort
    /// (the umbrella translates the throw into `ActionGoalStatus.aborted`).
    /// Periodically check `await handle.isCancelRequested` and throw
    /// `CancellationError` when set to honor a cooperatively-handled cancel.
    func execute(_ handle: ActionGoalHandle<Action>) async throws -> Action.Result
}
