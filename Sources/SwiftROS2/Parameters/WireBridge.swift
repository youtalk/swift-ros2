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
