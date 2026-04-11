// BatteryState.swift
// sensor_msgs/msg/BatteryState

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/BatteryState
public struct BatteryState: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/BatteryState",
        typeHash: "RIHS01_4bee5dfce981c98faa6828b868307a0a73f992ed0789f374ee96c8f840e69741"
    )

    public enum PowerSupplyStatus: UInt8, Sendable {
        case unknown = 0, charging = 1, discharging = 2, notCharging = 3, full = 4
    }

    public enum PowerSupplyHealth: UInt8, Sendable {
        case unknown = 0, good = 1, overheat = 2, dead = 3, overvoltage = 4
        case unspecFailure = 5, cold = 6, watchdogTimerExpire = 7, safetyTimerExpire = 8
    }

    public enum PowerSupplyTechnology: UInt8, Sendable {
        case unknown = 0, nimh = 1, lion = 2, lipo = 3, life = 4
        case nicd = 5, limn = 6, ternary = 7, vrla = 8
    }

    public var header: Header
    public var voltage: Float
    public var temperature: Float
    public var current: Float
    public var charge: Float
    public var capacity: Float
    public var designCapacity: Float
    public var percentage: Float
    public var powerSupplyStatus: UInt8
    public var powerSupplyHealth: UInt8
    public var powerSupplyTechnology: UInt8
    public var present: Bool
    public var cellVoltage: [Float]
    public var cellTemperature: [Float]
    public var location: String
    public var serialNumber: String

    public init(
        header: Header = Header(),
        voltage: Float = 0.0,
        temperature: Float = .nan,
        current: Float = .nan,
        charge: Float = .nan,
        capacity: Float = .nan,
        designCapacity: Float = .nan,
        percentage: Float = .nan,
        powerSupplyStatus: PowerSupplyStatus = .unknown,
        powerSupplyHealth: PowerSupplyHealth = .unknown,
        powerSupplyTechnology: PowerSupplyTechnology = .unknown,
        present: Bool = true,
        cellVoltage: [Float] = [],
        cellTemperature: [Float] = [],
        location: String = "",
        serialNumber: String = ""
    ) {
        self.header = header
        self.voltage = voltage
        self.temperature = temperature
        self.current = current
        self.charge = charge
        self.capacity = capacity
        self.designCapacity = designCapacity
        self.percentage = percentage
        self.powerSupplyStatus = powerSupplyStatus.rawValue
        self.powerSupplyHealth = powerSupplyHealth.rawValue
        self.powerSupplyTechnology = powerSupplyTechnology.rawValue
        self.present = present
        self.cellVoltage = cellVoltage
        self.cellTemperature = cellTemperature
        self.location = location
        self.serialNumber = serialNumber
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat32(voltage)
        encoder.writeFloat32(temperature)
        encoder.writeFloat32(current)
        encoder.writeFloat32(charge)
        encoder.writeFloat32(capacity)
        encoder.writeFloat32(designCapacity)
        encoder.writeFloat32(percentage)
        encoder.writeUInt8(powerSupplyStatus)
        encoder.writeUInt8(powerSupplyHealth)
        encoder.writeUInt8(powerSupplyTechnology)
        encoder.writeBool(present)
        encoder.writeFloat32Sequence(cellVoltage)
        encoder.writeFloat32Sequence(cellTemperature)
        encoder.writeString(location)
        encoder.writeString(serialNumber)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.voltage = try decoder.readFloat32()
        self.temperature = try decoder.readFloat32()
        self.current = try decoder.readFloat32()
        self.charge = try decoder.readFloat32()
        self.capacity = try decoder.readFloat32()
        self.designCapacity = try decoder.readFloat32()
        self.percentage = try decoder.readFloat32()
        self.powerSupplyStatus = try decoder.readUInt8()
        self.powerSupplyHealth = try decoder.readUInt8()
        self.powerSupplyTechnology = try decoder.readUInt8()
        self.present = try decoder.readBool()
        self.cellVoltage = try decoder.readFloat32Sequence()
        self.cellTemperature = try decoder.readFloat32Sequence()
        self.location = try decoder.readString()
        self.serialNumber = try decoder.readString()
    }
}
