// CDRDecoder.swift
// Pure Swift XCDR v1 little-endian decoder for ROS 2 messages

import Foundation

/// Errors that can occur during CDR deserialization
public enum CDRDecodingError: Error, LocalizedError {
    case invalidEncapsulationHeader
    case unexpectedEndOfData(expected: Int, remaining: Int)
    case invalidStringEncoding
    case invalidArraySize(expected: Int, available: Int)
    case sequenceTooLarge(elements: UInt32, max: Int)
    case byteSequenceTooLarge(bytes: UInt32, max: Int)
    case stringTooLarge(length: UInt32, max: Int)
    case missingStringNullTerminator

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
        case .sequenceTooLarge(let elements, let max):
            return "CDR sequence declares \(elements) elements which exceeds maximum \(max)"
        case .byteSequenceTooLarge(let bytes, let max):
            return "CDR byte sequence declares \(bytes) bytes which exceeds maximum \(max)"
        case .stringTooLarge(let length, let max):
            return "CDR string declares length \(length) which exceeds maximum \(max)"
        case .missingStringNullTerminator:
            return "CDR string is missing its trailing null terminator"
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

    /// Maximum number of elements allowed in a typed sequence (Float64/Float32/Int32/...).
    /// Wire-declared counts drive `reserveCapacity`; this cap prevents OOM DoS from a
    /// malicious length prefix. 64M elements = up to 512 MB for Float64, well above any
    /// realistic sensor payload.
    public static let maxSequenceElements: Int = 64 * 1024 * 1024

    /// Maximum byte length allowed for a `uint8[]` sequence (e.g. CompressedImage.data,
    /// PointCloud2.data). 256 MB accommodates large sensor buffers while bounding DoS.
    public static let maxByteSequenceLength: Int = 256 * 1024 * 1024

    /// Maximum length (including trailing null) allowed for a CDR string. 64 KB is
    /// generous for any ROS 2 identifier, topic, frame_id, or status message.
    public static let maxStringLength: Int = 64 * 1024

    /// When true, deserialize the pre-Jazzy schema (omits fields added after Humble,
    /// e.g. `sensor_msgs/Range.variance`). Defaults to false = Jazzy-compatible.
    /// Fixed at construction so decoding a partially-consumed buffer cannot change variants.
    public let isLegacySchema: Bool

    /// Create a decoder from CDR data (validates encapsulation header)
    public init(data: Data, isLegacySchema: Bool = false) throws {
        self.isLegacySchema = isLegacySchema
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
            // Non-standard but tolerated: length == 0 is treated as an empty
            // string. `CDREncoder.writeString` always emits length >= 1 with a
            // trailing null, so this branch only accepts malformed inputs; it
            // exists purely for backwards tolerance.
            return ""
        }
        guard length <= Self.maxStringLength else {
            throw CDRDecodingError.stringTooLarge(length: length, max: Self.maxStringLength)
        }
        let byteCount = Int(length)
        try ensureAvailable(byteCount)

        // `length` includes the trailing null terminator. Validate it is actually
        // present before slicing so malformed inputs fail fast instead of silently
        // dropping the final payload byte.
        let terminator = data[data.startIndex + offset + byteCount - 1]
        guard terminator == 0x00 else {
            throw CDRDecodingError.missingStringNullTerminator
        }

        let stringBytes = data[data.startIndex + offset..<data.startIndex + offset + byteCount - 1]
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
        let count = try readBoundedSequenceCount()
        return try readFloat64Array(count: count)
    }

    public func readFloat32Sequence() throws -> [Float] {
        let count = try readBoundedSequenceCount()
        return try readFloat32Array(count: count)
    }

    public func readInt32Sequence() throws -> [Int32] {
        let count = try readBoundedSequenceCount()
        var result = [Int32]()
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try readInt32())
        }
        return result
    }

    public func readUInt8Sequence() throws -> Data {
        let rawCount = try readUInt32()
        guard rawCount <= Self.maxByteSequenceLength else {
            throw CDRDecodingError.byteSequenceTooLarge(bytes: rawCount, max: Self.maxByteSequenceLength)
        }
        let count = Int(rawCount)
        try ensureAvailable(count)
        let result = data[data.startIndex + offset..<data.startIndex + offset + count]
        offset += count
        return Data(result)
    }

    /// Read a uint32 sequence length and reject values beyond `maxSequenceElements`.
    /// Shared by all typed (non-byte) sequences so the cap applies uniformly.
    private func readBoundedSequenceCount() throws -> Int {
        let rawCount = try readUInt32()
        guard rawCount <= Self.maxSequenceElements else {
            throw CDRDecodingError.sequenceTooLarge(elements: rawCount, max: Self.maxSequenceElements)
        }
        return Int(rawCount)
    }

    // MARK: - Raw Bytes

    public func readRawBytes(count: Int) throws -> Data {
        try ensureAvailable(count)
        let result = data[data.startIndex + offset..<data.startIndex + offset + count]
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
