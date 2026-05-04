/// Per-distro hashes for an action and its eight contained type descriptions.
///
/// The action-level `actionHash` corresponds to the `<pkg>/action/<Type>`
/// rosidl entry; the seven member hashes are the wrapper / block hashes that
/// either travel on the wire (the five wrappers) or describe the user-facing
/// goal / result / feedback payloads.
public struct ActionHashes: Equatable, Sendable {
    public var actionHash: String
    public var goalHash: String
    public var resultHash: String
    public var feedbackHash: String
    public var sendGoalRequestHash: String
    public var sendGoalResponseHash: String
    public var getResultRequestHash: String
    public var getResultResponseHash: String
    public var feedbackMessageHash: String

    public init(
        actionHash: String,
        goalHash: String,
        resultHash: String,
        feedbackHash: String,
        sendGoalRequestHash: String,
        sendGoalResponseHash: String,
        getResultRequestHash: String,
        getResultResponseHash: String,
        feedbackMessageHash: String
    ) {
        self.actionHash = actionHash
        self.goalHash = goalHash
        self.resultHash = resultHash
        self.feedbackHash = feedbackHash
        self.sendGoalRequestHash = sendGoalRequestHash
        self.sendGoalResponseHash = sendGoalResponseHash
        self.getResultRequestHash = getResultRequestHash
        self.getResultResponseHash = getResultResponseHash
        self.feedbackMessageHash = feedbackMessageHash
    }
}

/// Distro-neutral intermediate representation of a single ROS 2 action type.
///
/// Bundles the three user-defined IRs (`goal` / `result` / `feedback`) with
/// the five wrapper IRs synthesized per the rcl action protocol. All eight
/// IRs are regular ``MessageIR``s (``MessageKind/action``) so the existing
/// emitter / RIHS01 code reuses untouched.
public struct ActionIR: Equatable, Sendable {
    public let package: String  // "example_interfaces"
    public let typeName: String  // "Fibonacci"

    public var goal: MessageIR
    public var result: MessageIR
    public var feedback: MessageIR

    public var sendGoalRequest: MessageIR
    public var sendGoalResponse: MessageIR
    public var getResultRequest: MessageIR
    public var getResultResponse: MessageIR
    public var feedbackMessage: MessageIR

    /// Per-distro hashes for the action itself and each of the eight member IRs.
    public var perDistroHashes: [String: ActionHashes] = [:]

    public init(
        package: String,
        typeName: String,
        goal: MessageIR,
        result: MessageIR,
        feedback: MessageIR,
        sendGoalRequest: MessageIR,
        sendGoalResponse: MessageIR,
        getResultRequest: MessageIR,
        getResultResponse: MessageIR,
        feedbackMessage: MessageIR,
        perDistroHashes: [String: ActionHashes] = [:]
    ) {
        self.package = package
        self.typeName = typeName
        self.goal = goal
        self.result = result
        self.feedback = feedback
        self.sendGoalRequest = sendGoalRequest
        self.sendGoalResponse = sendGoalResponse
        self.getResultRequest = getResultRequest
        self.getResultResponse = getResultResponse
        self.feedbackMessage = feedbackMessage
        self.perDistroHashes = perDistroHashes
    }

    /// "example_interfaces/action/Fibonacci"
    public var rosActionName: String { "\(package)/action/\(typeName)" }
}
