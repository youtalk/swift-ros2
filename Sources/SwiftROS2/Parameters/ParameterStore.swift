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

extension ParameterStore {
    func get(name: String) throws -> ROS2Parameter {
        guard let e = entries[name] else {
            throw ROS2ParameterError.notDeclared(name: name)
        }
        return ROS2Parameter(name: name, value: e.value)
    }

    func describe(name: String) throws -> ROS2ParameterDescriptor {
        guard let e = entries[name] else {
            throw ROS2ParameterError.notDeclared(name: name)
        }
        return e.descriptor
    }

    func list(prefixes: [String], depth: UInt64) -> ROS2ListParametersResult {
        let allNames = entries.keys.sorted()
        let matched: [String]
        if prefixes.isEmpty {
            matched = allNames.filter { passesDepth($0, prefix: "", depth: depth) }
        } else {
            matched = allNames.filter { name in
                prefixes.contains { p in
                    (name == p || name.hasPrefix(p + "."))
                        && passesDepth(name, prefix: p, depth: depth)
                }
            }
        }
        let derivedPrefixes = collectPrefixes(matched)
        return ROS2ListParametersResult(names: matched, prefixes: derivedPrefixes)
    }

    private func passesDepth(_ name: String, prefix: String, depth: UInt64) -> Bool {
        if depth == 0 { return true }
        let suffix: Substring
        if prefix.isEmpty {
            suffix = name[...]
        } else if name == prefix {
            return true
        } else {
            suffix = name.dropFirst(prefix.count + 1)  // skip "<prefix>."
        }
        let separators = suffix.filter { $0 == "." }.count
        return separators < Int(depth)
    }

    private func collectPrefixes(_ names: [String]) -> [String] {
        var seen = Set<String>()
        for name in names {
            var parts = name.split(separator: ".", omittingEmptySubsequences: false)
            // every proper ancestor (drop the last segment, then the next, ...)
            while parts.count > 1 {
                parts.removeLast()
                seen.insert(parts.joined(separator: "."))
            }
        }
        return seen.sorted()
    }
}
