/// The parsed representation of a single `.action` file.
///
/// An action is three IDL message bodies separated by `---`:
/// - `goal`     — sent from client to server when issuing a goal request.
/// - `result`   — returned from server to client when the goal terminates.
/// - `feedback` — streamed from server to client during execution.
///
/// Each block reuses the existing `IDLFile` representation (same grammar as a
/// `.msg` file body), so `.action` parsing is structurally a thin separator
/// split + three nested `Parser.parseMessage(...)` calls. The synthesized
/// `<typeName>_Goal` / `<typeName>_Result` / `<typeName>_Feedback` names match
/// what rosidl emits for the per-block type descriptions.
public struct IDLAction: Equatable, Sendable {
    public let package: String
    public let typeName: String
    public let goal: IDLFile
    public let result: IDLFile
    public let feedback: IDLFile

    public init(
        package: String,
        typeName: String,
        goal: IDLFile,
        result: IDLFile,
        feedback: IDLFile
    ) {
        self.package = package
        self.typeName = typeName
        self.goal = goal
        self.result = result
        self.feedback = feedback
    }
}
