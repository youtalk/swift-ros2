// Per-node parameter storage. Phase 2 covers declare / get / set / list /
// describe with validation. Service registration and ParameterEvent
// publishing land in phases 3 and 4 respectively.

struct ParameterEntry: Sendable, Equatable {
    var value: ROS2ParameterValue
    var descriptor: ROS2ParameterDescriptor
}

actor ParameterStore {
    private var entries: [String: ParameterEntry] = [:]

    init() {}

    @discardableResult
    func declare(
        name: String,
        value: ROS2ParameterValue,
        descriptor: ROS2ParameterDescriptor
    ) throws -> ROS2ParameterValue {
        guard entries[name] == nil else {
            throw ROS2ParameterError.alreadyDeclared(name: name)
        }
        entries[name] = ParameterEntry(value: value, descriptor: descriptor)
        return value
    }

    func undeclare(name: String) throws {
        guard entries.removeValue(forKey: name) != nil else {
            throw ROS2ParameterError.notDeclared(name: name)
        }
    }

    func has(name: String) -> Bool {
        entries[name] != nil
    }
}
