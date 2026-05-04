// Hand-written conveniences layered on top of the swift-ros2-gen output for
// `sensor_msgs`. These mirror the API surface that the pre-Phase-4 hand-written
// types exposed (Swift enums for ROS constants, factory helpers, `Data`-typed
// blob initializers) so existing callers — both inside swift-ros2 and inside
// the Conduit app that consumes this package — keep compiling without the
// generator having to learn each special case.
//
// The IDL emitter is intentionally minimal — it only writes fields, an `init`,
// and CDR encode / decode. Anything else lives here.

import Foundation
import SwiftROS2CDR

// MARK: - BatteryState

extension BatteryState {
    /// Mirrors the legacy hand-written `BatteryState.PowerSupplyStatus` enum.
    /// The generated struct stores the value as a raw `UInt8`; the typed
    /// initializer below converts.
    public enum PowerSupplyStatus: UInt8, Sendable {
        case unknown = 0
        case charging = 1
        case discharging = 2
        case notCharging = 3
        case full = 4
    }

    public enum PowerSupplyHealth: UInt8, Sendable {
        case unknown = 0
        case good = 1
        case overheat = 2
        case dead = 3
        case overvoltage = 4
        case unspecFailure = 5
        case cold = 6
        case watchdogTimerExpire = 7
        case safetyTimerExpire = 8
    }

    public enum PowerSupplyTechnology: UInt8, Sendable {
        case unknown = 0
        case nimh = 1
        case lion = 2
        case lipo = 3
        case life = 4
        case nicd = 5
        case limn = 6
        case ternary = 7
        case vrla = 8
    }

    /// Convenience initializer matching the pre-Phase-4 hand-written shape.
    /// Accepts the typed Swift enums for `powerSupplyStatus` /
    /// `powerSupplyHealth` / `powerSupplyTechnology` and stores the underlying
    /// `UInt8` raw value.
    public init(
        header: Header = Header(),
        voltage: Float = 0.0,
        temperature: Float = .nan,
        current: Float = .nan,
        charge: Float = .nan,
        capacity: Float = .nan,
        designCapacity: Float = .nan,
        percentage: Float = .nan,
        powerSupplyStatus: PowerSupplyStatus,
        powerSupplyHealth: PowerSupplyHealth = .unknown,
        powerSupplyTechnology: PowerSupplyTechnology = .unknown,
        present: Bool = true,
        cellVoltage: [Float] = [],
        cellTemperature: [Float] = [],
        location: String = "",
        serialNumber: String = ""
    ) {
        self.init(
            header: header,
            voltage: voltage,
            temperature: temperature,
            current: current,
            charge: charge,
            capacity: capacity,
            designCapacity: designCapacity,
            percentage: percentage,
            powerSupplyStatus: powerSupplyStatus.rawValue,
            powerSupplyHealth: powerSupplyHealth.rawValue,
            powerSupplyTechnology: powerSupplyTechnology.rawValue,
            present: present,
            cellVoltage: cellVoltage,
            cellTemperature: cellTemperature,
            location: location,
            serialNumber: serialNumber
        )
    }
}

// MARK: - Range

extension Range {
    public enum RadiationType: UInt8, Sendable {
        case ultrasound = 0
        case infrared = 1
    }

    /// Convenience initializer accepting the typed `RadiationType` enum.
    /// Required when callers write `Range(..., radiationType: .infrared, ...)`.
    public init(
        header: Header = Header(),
        radiationType: RadiationType,
        fieldOfView: Float = 0.0,
        minRange: Float = 0.0,
        maxRange: Float = 0.0,
        range: Float = 0.0,
        variance: Float = 0.0
    ) {
        self.init(
            header: header,
            radiationType: radiationType.rawValue,
            fieldOfView: fieldOfView,
            minRange: minRange,
            maxRange: maxRange,
            range: range,
            variance: variance
        )
    }
}

// MARK: - NavSatFix

extension NavSatFix {
    public enum CovarianceType: UInt8, Sendable {
        case unknown = 0
        case approximated = 1
        case diagonalKnown = 2
        case known = 3
    }

    public init(
        header: Header = Header(),
        status: NavSatStatus = NavSatStatus(),
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        altitude: Double = .nan,
        positionCovariance: [Double] = Array(repeating: 0.0, count: 9),
        positionCovarianceType: CovarianceType
    ) {
        self.init(
            header: header,
            status: status,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            positionCovariance:
                positionCovariance.count == 9 ? positionCovariance : Array(repeating: 0.0, count: 9),
            positionCovarianceType: positionCovarianceType.rawValue
        )
    }
}

// MARK: - NavSatStatus

extension NavSatStatus {
    /// camelCase aliases mirroring the legacy hand-written constants. The
    /// generator emits `STATUS_FIX` / `SERVICE_GPS` (matching upstream IDL);
    /// these aliases preserve the shorter `statusFix` / `serviceGPS` form
    /// used pervasively in caller code and tests.
    public static var statusNoFix: Int8 { Self.STATUS_NO_FIX }
    public static var statusFix: Int8 { Self.STATUS_FIX }
    public static var statusSbasFix: Int8 { Self.STATUS_SBAS_FIX }
    public static var statusGbasFix: Int8 { Self.STATUS_GBAS_FIX }

    public static var serviceGPS: UInt16 { Self.SERVICE_GPS }
    public static var serviceGLONASS: UInt16 { Self.SERVICE_GLONASS }
    public static var serviceCOMPASS: UInt16 { Self.SERVICE_COMPASS }
    public static var serviceGALILEO: UInt16 { Self.SERVICE_GALILEO }
}

// MARK: - PointField

/// Mirrors the legacy `PointFieldDataType` enum. The generated `PointField`
/// stores `datatype` as a raw `UInt8`; this enum gives callers the typed form
/// and a convenience initializer.
public enum PointFieldDataType: UInt8, Sendable {
    case int8 = 1
    case uint8 = 2
    case int16 = 3
    case uint16 = 4
    case int32 = 5
    case uint32 = 6
    case float32 = 7
    case float64 = 8

    public var byteSize: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float32: return 4
        case .float64: return 8
        }
    }
}

extension PointField {
    public init(name: String, offset: UInt32, datatype: PointFieldDataType, count: UInt32 = 1) {
        self.init(name: name, offset: offset, datatype: datatype.rawValue, count: count)
    }

    public static func x(offset: UInt32 = 0) -> PointField {
        PointField(name: "x", offset: offset, datatype: .float32, count: 1)
    }

    public static func y(offset: UInt32 = 4) -> PointField {
        PointField(name: "y", offset: offset, datatype: .float32, count: 1)
    }

    public static func z(offset: UInt32 = 8) -> PointField {
        PointField(name: "z", offset: offset, datatype: .float32, count: 1)
    }

    public static func rgb(offset: UInt32 = 12) -> PointField {
        PointField(name: "rgb", offset: offset, datatype: .uint32, count: 1)
    }

    public static var xyzFields: [PointField] {
        [.x(), .y(), .z()]
    }

    public static var xyzrgbFields: [PointField] {
        [.x(), .y(), .z(), .rgb()]
    }
}

// MARK: - RegionOfInterest

extension RegionOfInterest {
    /// Build a full-frame ROI sized to the given dimensions.
    public static func fullFrame(width: UInt32, height: UInt32) -> RegionOfInterest {
        RegionOfInterest(xOffset: 0, yOffset: 0, height: height, width: width, doRectify: false)
    }
}

// MARK: - Image / CompressedImage data convenience

extension CompressedImage {
    /// Convenience initializer that accepts the pixel buffer as `Data`. The
    /// generated `init` takes `[UInt8]`; this variant copies via `Data.bytes`.
    public init(header: Header = Header(), format: String = "jpeg", data: Data) {
        self.init(header: header, format: format, data: Array(data))
    }

    /// Read-only `Data` view of the underlying byte array. Convenience for
    /// callers that work with `Data` (e.g. transport / compression).
    public var dataAsData: Data { Data(data) }
}

extension Image {
    public init(
        header: Header = Header(),
        height: UInt32 = 0,
        width: UInt32 = 0,
        encoding: String = "",
        isBigendian: UInt8 = 0,
        step: UInt32 = 0,
        data: Data
    ) {
        self.init(
            header: header,
            height: height,
            width: width,
            encoding: encoding,
            isBigendian: isBigendian,
            step: step,
            data: Array(data)
        )
    }

    public var dataAsData: Data { Data(data) }
}

extension PointCloud2 {
    public init(
        header: Header = Header(),
        height: UInt32 = 0,
        width: UInt32 = 0,
        fields: [PointField] = [],
        isBigendian: Bool = false,
        pointStep: UInt32 = 0,
        rowStep: UInt32 = 0,
        data: Data,
        isDense: Bool = true
    ) {
        self.init(
            header: header,
            height: height,
            width: width,
            fields: fields,
            isBigendian: isBigendian,
            pointStep: pointStep,
            rowStep: rowStep,
            data: Array(data),
            isDense: isDense
        )
    }

    public var dataAsData: Data { Data(data) }
}
