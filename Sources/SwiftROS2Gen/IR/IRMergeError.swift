import Foundation

/// Surfaces failures from `IRBuilder.build(perDistro:)` when distro-specific
/// IDLs cannot be merged into a single distro-neutral IR.
public struct IRMergeError: Error, CustomStringConvertible, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The same `ros2Name` resolves to incompatible `FieldType`s across distros.
        case conflictingFieldType(name: String, perDistroTypes: [String: FieldType])
        /// Two distros disagree on the package or type name. Should never happen
        /// in practice because the caller groups by `(package, typeName)` before
        /// calling `build(perDistro:)`, but encoded for defensiveness.
        case identityMismatch(perDistroIdentity: [String: String])
    }

    public let kind: Kind
    public let typeName: String

    public init(kind: Kind, typeName: String) {
        self.kind = kind
        self.typeName = typeName
    }

    public var description: String {
        switch kind {
        case .conflictingFieldType(let name, let perDistroTypes):
            let detail =
                perDistroTypes
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            return "\(typeName): field '\(name)' has conflicting types across distros: \(detail)"
        case .identityMismatch(let perDistroIdentity):
            let detail =
                perDistroIdentity
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            return "\(typeName): distros disagree on identity: \(detail)"
        }
    }
}
