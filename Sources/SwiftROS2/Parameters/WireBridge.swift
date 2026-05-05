// Translation between the Swift-public ROS2* types and the
// SwiftROS2Messages.rcl_interfaces wire types. The wire types use
// uint8 discriminators + fixed-name typed slots; we hide that here.

import SwiftROS2Messages

extension ROS2ParameterValue {
    init(wire: SwiftROS2Messages.ParameterValue) {
        switch wire.type {
        case 1: self = .bool(wire.boolValue)
        case 2: self = .integer(wire.integerValue)
        case 3: self = .double(wire.doubleValue)
        case 4: self = .string(wire.stringValue)
        case 5: self = .byteArray(wire.byteArrayValue)
        case 6: self = .boolArray(wire.boolArrayValue)
        case 7: self = .integerArray(wire.integerArrayValue)
        case 8: self = .doubleArray(wire.doubleArrayValue)
        case 9: self = .stringArray(wire.stringArrayValue)
        default: self = .notSet
        }
    }

    func toWire() -> SwiftROS2Messages.ParameterValue {
        var w = SwiftROS2Messages.ParameterValue()
        switch self {
        case .notSet:
            w.type = 0
        case .bool(let v):
            w.type = 1
            w.boolValue = v
        case .integer(let v):
            w.type = 2
            w.integerValue = v
        case .double(let v):
            w.type = 3
            w.doubleValue = v
        case .string(let v):
            w.type = 4
            w.stringValue = v
        case .byteArray(let v):
            w.type = 5
            w.byteArrayValue = v
        case .boolArray(let v):
            w.type = 6
            w.boolArrayValue = v
        case .integerArray(let v):
            w.type = 7
            w.integerArrayValue = v
        case .doubleArray(let v):
            w.type = 8
            w.doubleArrayValue = v
        case .stringArray(let v):
            w.type = 9
            w.stringArrayValue = v
        }
        return w
    }
}

extension ROS2ParameterDescriptor {
    init(wire: SwiftROS2Messages.ParameterDescriptor) {
        let floating = wire.floatingPointRange.first
        let integer = wire.integerRange.first
        self.init(
            name: wire.name,
            type: ROS2ParameterType(rawValue: wire.type) ?? .notSet,
            description: wire.description,
            additionalConstraints: wire.additionalConstraints,
            readOnly: wire.readOnly,
            dynamicTyping: wire.dynamicTyping,
            floatingPointRange: floating.map { $0.fromValue...$0.toValue },
            floatingPointStep: floating.map { $0.step },
            integerRange: integer.map { $0.fromValue...$0.toValue },
            integerStep: integer.map { Int64(bitPattern: $0.step) }
        )
    }

    func toWire() -> SwiftROS2Messages.ParameterDescriptor {
        var w = SwiftROS2Messages.ParameterDescriptor()
        w.name = name
        w.type = type.rawValue
        w.description = description
        w.additionalConstraints = additionalConstraints
        w.readOnly = readOnly
        w.dynamicTyping = dynamicTyping
        if let r = floatingPointRange {
            w.floatingPointRange = [
                SwiftROS2Messages.FloatingPointRange(
                    fromValue: r.lowerBound,
                    toValue: r.upperBound,
                    step: floatingPointStep ?? 0.0
                )
            ]
        }
        if let r = integerRange {
            w.integerRange = [
                SwiftROS2Messages.IntegerRange(
                    fromValue: r.lowerBound,
                    toValue: r.upperBound,
                    step: integerStep.map { UInt64(bitPattern: $0) } ?? 0
                )
            ]
        }
        return w
    }
}
