// CDRDecoder.swift
// Pure Swift XCDR v1 little-endian decoder for ROS 2 messages

import Foundation

/// Errors that can occur during CDR deserialization
public enum CDRDecodingError: Error, LocalizedError {
    case invalidEncapsulationHeader
    case unexpectedEndOfData(expected: Int, remaining: Int)
    case invalidStringEncoding
    case invalidArraySize(expected: Int, available: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEncapsulationHeader:
            return "Invalid XCDR v1 encapsulation header (expected [0x00, 0x01, 0x00, 0x00])"
        case .unexpectedEndOfData(let expected, let remaining):
            return "Unexpected end of CDR data: need \(expected) bytes but only \(remaining) remain"
        case .invalidStringEncoding:
            return "Invalid UTF-8 string encoding in CDR data"
        case .invalidArraySize(let expected, let available):
            return "Invalid array size: expected \(expected) elements but data has room for \(available)"
        }
    }
}

/// XCDR v1 little-endian decoder for ROS 2 CDR deserialization
///
/// Mirrors `CDREncoder` for the decode direction. Alignment rules are identical:
/// alignment is relative to the data stream start (after the 4-byte encapsulation header).
public final class CDRDecoder {
    private let data: Data
    private var offset: Int

    private static let encapsulationHeaderSize = 4

    /// Create a decoder from CDR data (validates encapsulation header)
    public init(data: Data) throws {
        guard data.count >= 4 else {
            throw CDRDecodingError.invalidEncapsulationHeader
        }

        // Validate XCDR v1 little-endian header: [0x00, 0x01, 0x00, 0x00]
        guard data[data.startIndex] == 0x00,
              data[data.startIndex + 1] == 0x01,
              data[data.startIndex + 2] == 0x00,
              data[data.startIndex + 3] == 0x00
        else {
            throw CDRDecodingError.invalidEncapsulationHeader
        }

        self.data = data
        self.offset = Self.encapsulationHeaderSize
    }

    /// Remaining bytes available
    public var remainingBytes: Int {
        data.count - offset
    }

    // MARK: - Primitive Types

    public func readUInt8() throws -> UInt8 {
        try ensureAvailable(1)
        let value = data[data.startIndex + offset]
        offset += 1
        return value
    }

    public func readInt8() throws -> Int8 {
        Int8(bitPattern: try readUInt8())
    }

    public func readBool() throws -> Bool {
        try readUInt8() != 0
    }

    public func readUInt16() throws -> UInt16 {
        try alignTo(2)
        try ensureAvailable(2)
        let value = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: value)
    }

    public func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    public func readUInt32() throws -> UInt32 {
        try alignTo(4)
        try ensureAvailable(4)
        let value = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    public func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    public func readUInt64() throws -> UInt64 {
        try alignTo(8)
        try ensureAvailable(8)
        let value = data.withUnsafeBytes { ptr -> UInt64 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return UInt64(littleEndian: value)
    }

    public func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    public func readFloat32() throws -> Float {
        let bits = try readUInt32()
        return Float(bitPattern: bits)
    }

    public func readFloat64() throws -> Double {
        let bits = try readUInt64()
        return Double(bitPattern: bits)
    }

    // MARK: - String

    /// Read a CDR string (uint32 length including null + chars + null byte)
    public func readString() throws -> String {
        let length = try readUInt32()
        guard length > 0 else {
            return ""
        }
        let byteCount = Int(length)
        try ensureAvailable(byteCount)

        // length includes null terminator
        let stringBytes = data[data.startIndex + offset ..< data.startIndex + offset + byteCount - 1]
        offset += byteCount

        guard let string = String(data: stringBytes, encoding: .utf8) else {
            throw CDRDecodingError.invalidStringEncoding
        }
        return string
    }

    // MARK: - Arrays (fixed-size, NO length prefix)

    public func readFloat64Array(count: Int) throws -> [Double] {
        var result = [Double]()
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readFloat64())
        }
        return result
    }

    public func readFloat32Array(count: Int) throws -> [Float] {
        var result = [Float]()
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readFloat32())
        }
        return result
    }

    // MARK: - Sequences (variable-length, WITH uint32 length prefix)

    public func readFloat64Sequence() throws -> [Double] {
        let count = Int(try readUInt32())
        return try readFloat64Array(count: count)
    }

    public func readFloat32Sequence() throws -> [Float] {
        let count = Int(try readUInt32())
        return try readFloat32Array(count: count)
    }

    public func readInt32Sequence() throws -> [Int32] {
        let count = Int(try readUInt32())
        var result = [Int32]()
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readInt32())
        }
        return result
    }

    public func readUInt8Sequence() throws -> Data {
        let count = Int(try readUInt32())
        try ensureAvailable(count)
        let result = data[data.startIndex + offset ..< data.startIndex + offset + count]
        offset += count
        return Data(result)
    }

    // MARK: - Raw Bytes

    public func readRawBytes(count: Int) throws -> Data {
        try ensureAvailable(count)
        let result = data[data.startIndex + offset ..< data.startIndex + offset + count]
        offset += count
        return Data(result)
    }

    public func skipBytes(_ count: Int) throws {
        try ensureAvailable(count)
        offset += count
    }

    // MARK: - Alignment

    private func alignTo(_ alignment: Int) throws {
        let relativePosition = offset - Self.encapsulationHeaderSize
        let remainder = relativePosition % alignment
        if remainder != 0 {
            let padding = alignment - remainder
            try ensureAvailable(padding)
            offset += padding
        }
    }

    // MARK: - Validation

    private func ensureAvailable(_ count: Int) throws {
        guard offset + count <= data.count else {
            throw CDRDecodingError.unexpectedEndOfData(
                expected: count,
                remaining: data.count - offset
            )
        }
    }
}
