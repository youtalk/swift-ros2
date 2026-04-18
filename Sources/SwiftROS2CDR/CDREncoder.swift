// CDREncoder.swift
// Pure Swift XCDR v1 little-endian encoder for ROS 2 messages

import Foundation

/// XCDR v1 little-endian encoder for ROS 2 CDR serialization
///
/// CDR alignment is calculated relative to the data stream start (after the 4-byte encapsulation header).
/// Fixed-size arrays serialize WITHOUT length prefix. Variable-length sequences serialize WITH a uint32 length prefix.
public final class CDREncoder {
    private var buffer: Data

    private static let encapsulationHeaderSize = 4

    /// When true, serialize the pre-Jazzy schema (omits fields added after Humble,
    /// e.g. `sensor_msgs/Range.variance`). Defaults to false = Jazzy-compatible.
    public var isLegacyDistro: Bool = false

    public init(estimatedSize: Int = 256, isLegacyDistro: Bool = false) {
        buffer = Data(capacity: estimatedSize)
        self.isLegacyDistro = isLegacyDistro
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Encapsulation Header

    /// Write XCDR v1 encapsulation header: [0x00, 0x01, 0x00, 0x00] (little-endian plain CDR)
    public func writeEncapsulationHeader() {
        buffer.append(contentsOf: [0x00, 0x01, 0x00, 0x00] as [UInt8])
    }

    // MARK: - Primitive Types

    public func writeUInt8(_ value: UInt8) {
        buffer.append(value)
    }

    public func writeInt8(_ value: Int8) {
        buffer.append(UInt8(bitPattern: value))
    }

    public func writeBool(_ value: Bool) {
        writeUInt8(value ? 1 : 0)
    }

    public func writeUInt16(_ value: UInt16) {
        alignTo(2)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeInt16(_ value: Int16) {
        alignTo(2)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeUInt32(_ value: UInt32) {
        alignTo(4)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeInt32(_ value: Int32) {
        alignTo(4)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeUInt64(_ value: UInt64) {
        alignTo(8)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeInt64(_ value: Int64) {
        alignTo(8)
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeFloat32(_ value: Float) {
        alignTo(4)
        var v = value.bitPattern.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    public func writeFloat64(_ value: Double) {
        alignTo(8)
        var v = value.bitPattern.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    // MARK: - String

    /// Write a CDR string (uint32 length including null + chars + null byte)
    public func writeString(_ value: String) {
        let utf8 = Array(value.utf8)
        let length = UInt32(utf8.count + 1)
        writeUInt32(length)
        buffer.append(contentsOf: utf8)
        buffer.append(0)
    }

    // MARK: - Arrays (fixed-size, NO length prefix)

    public func writeFloat64Array(_ array: [Double]) {
        for value in array {
            writeFloat64(value)
        }
    }

    public func writeFloat32Array(_ array: [Float]) {
        for value in array {
            writeFloat32(value)
        }
    }

    // MARK: - Sequences (variable-length, WITH uint32 length prefix)

    public func writeFloat64Sequence(_ sequence: [Double]) {
        writeUInt32(UInt32(sequence.count))
        for value in sequence {
            writeFloat64(value)
        }
    }

    public func writeFloat32Sequence(_ sequence: [Float]) {
        writeUInt32(UInt32(sequence.count))
        for value in sequence {
            writeFloat32(value)
        }
    }

    public func writeInt32Sequence(_ sequence: [Int32]) {
        writeUInt32(UInt32(sequence.count))
        for value in sequence {
            writeInt32(value)
        }
    }

    public func writeUInt8Sequence(_ sequence: [UInt8]) {
        writeUInt32(UInt32(sequence.count))
        buffer.append(contentsOf: sequence)
    }

    public func writeUInt8Sequence(_ data: Data) {
        writeUInt32(UInt32(data.count))
        buffer.append(data)
    }

    // MARK: - Raw Bytes

    public func writeRawBytes(_ data: Data) {
        buffer.append(data)
    }

    public func writeRawBytes(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
    }

    public func writePadding(_ count: Int) {
        buffer.append(contentsOf: [UInt8](repeating: 0, count: count))
    }

    // MARK: - Alignment

    private func alignTo(_ alignment: Int) {
        let dataPosition = buffer.count - Self.encapsulationHeaderSize
        let offset = dataPosition % alignment
        if offset != 0 {
            let padding = alignment - offset
            buffer.append(contentsOf: [UInt8](repeating: 0, count: padding))
        }
    }

    // MARK: - Output

    public func getData() -> Data {
        buffer
    }

    public var count: Int {
        buffer.count
    }
}
