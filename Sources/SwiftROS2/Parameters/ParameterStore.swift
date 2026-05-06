// Per-node parameter storage. Phase 2 covers declare / get / set / list /
// describe with validation. Service registration and ParameterEvent
// publishing land in phases 3 and 4 respectively.

struct ParameterEntry: Sendable, Equatable {
    var value: ROS2ParameterValue
    var descriptor: ROS2ParameterDescriptor
}

actor ParameterStore {
    private var entries: [String: ParameterEntry] = [:]
    private var servicesStarted = false

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
        // Validate the initial value against the descriptor — the same rules
        // that gate set(_:) apply at declare time. readOnly is intentionally
        // skipped here: declare IS the one legal write to a read-only param.
        if let reason = validate(
            name: name, value: value, descriptor: descriptor, allowWriteToReadOnly: true)
        {
            throw ROS2ParameterError.invalidValue(name: name, reason: reason)
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
        // Stay in UInt64-land so a depth > Int.max can't trap on the cast.
        let separators = UInt64(suffix.filter { $0 == "." }.count)
        return separators < depth
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

extension ParameterStore {
    @discardableResult
    func set(_ p: ROS2Parameter) -> ROS2SetParametersResult {
        guard var entry = entries[p.name] else {
            return .failure(reason: "parameter '\(p.name)' is not declared")
        }
        if let reason = validate(
            name: p.name, value: p.value, descriptor: entry.descriptor,
            allowWriteToReadOnly: false)
        {
            return .failure(reason: reason)
        }
        entry.value = p.value
        entries[p.name] = entry
        return .success()
    }

    func setMany(_ ps: [ROS2Parameter]) -> [ROS2SetParametersResult] {
        ps.map { set($0) }
    }

    func setAtomically(_ ps: [ROS2Parameter]) -> ROS2SetParametersResult {
        let snapshot = entries
        for p in ps {
            let r = set(p)
            if !r.successful {
                entries = snapshot
                return r
            }
        }
        return .success()
    }

    /// Returns nil if the value is acceptable, otherwise a human-readable reason.
    ///
    /// `floatingPointStep` and `integerStep` from the descriptor are NOT
    /// enforced here — they are advisory metadata for tools (rqt_param,
    /// `ros2 param describe`). rclcpp follows the same convention.
    private func validate(
        name: String,
        value: ROS2ParameterValue,
        descriptor: ROS2ParameterDescriptor,
        allowWriteToReadOnly: Bool
    ) -> String? {
        if descriptor.readOnly && !allowWriteToReadOnly {
            return "parameter '\(name)' is read-only"
        }
        let valueType = value.parameterType
        if !descriptor.dynamicTyping
            && descriptor.type != .notSet
            && valueType != descriptor.type
            && valueType != .notSet
        {
            return "parameter '\(name)' expects \(descriptor.type), got \(valueType)"
        }
        if case .integer(let v) = value, let r = descriptor.integerRange {
            if v < r.lowerBound || v > r.upperBound {
                return "parameter '\(name)' value \(v) out of range \(r)"
            }
        }
        if case .double(let v) = value, let r = descriptor.floatingPointRange {
            if v < r.lowerBound || v > r.upperBound {
                return "parameter '\(name)' value \(v) out of range \(r)"
            }
        }
        return nil
    }
}

extension ParameterStore {
    /// Non-throwing accessor used by the parameter-service handlers. The
    /// throwing variants (`get`, `describe`) keep the rclcpp convention
    /// for direct Swift callers; the wire services prefer to encode an
    /// "absent" answer rather than surface an error to the caller.
    func entry(name: String) -> (value: ROS2ParameterValue, descriptor: ROS2ParameterDescriptor)? {
        guard let e = entries[name] else { return nil }
        return (e.value, e.descriptor)
    }

    /// One-shot latch used by `Node.startParameterServices()` to claim
    /// the right to register the six parameter services. Returns `true`
    /// the first time it is called; subsequent calls return `false`.
    ///
    /// The latch is claimed *before* the six `createService` calls so
    /// concurrent `startParameterServices()` invocations can't double-
    /// register. If registration then fails partway through, the caller
    /// must invoke `resetServicesStarted()` so a future retry can
    /// re-claim the latch.
    @discardableResult
    func markServicesStarted() -> Bool {
        if servicesStarted { return false }
        servicesStarted = true
        return true
    }

    /// Release the latch so a future `startParameterServices()` call can
    /// re-claim it. Called by `Node.startParameterServices()` when one of
    /// the six `createService` registrations throws — the partially-
    /// registered services are torn down by `Node.destroy()` (or by the
    /// caller's own cleanup) and the node is left in an un-started state.
    func resetServicesStarted() {
        servicesStarted = false
    }
}
