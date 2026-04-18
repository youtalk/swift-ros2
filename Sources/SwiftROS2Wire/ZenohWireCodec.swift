// ZenohWireCodec.swift
// Wire format codec for rmw_zenoh compatibility

import Foundation

/// Wire format codec for rmw_zenoh
///
/// Generates key expressions, liveliness tokens, and 33-byte attachments
/// compatible with rmw_zenoh_cpp. Handles both legacy (Humble) and modern
/// (Jazzy/Kilted/Rolling) wire formats.
public struct ZenohWireCodec: WireCodec {
    public let distro: ROS2Distro

    public init(distro: ROS2Distro) {
        self.distro = distro
    }

    // MARK: - Key Expression

    /// Generate key expression for rmw_zenoh
    ///
    /// Format: `<domain>/<namespace>/<topic>/<dds_type_name>/<type_hash>`
    public func makeKeyExpr(
        domainId: Int,
        namespace: String,
        topic: String,
        typeName: String,
        typeHash: String?
    ) -> String {
        let cleanNamespace = TypeNameConverter.stripLeadingSlash(namespace)
        let ddsTypeName = TypeNameConverter.toDDSTypeName(typeName)
        let hashComponent = distro.formatTypeHash(typeHash)
        // Global topics (e.g. /tf_static) are published with an empty namespace;
        // avoid emitting `domain//topic` which Zenoh rejects as invalid.
        let topicPath = cleanNamespace.isEmpty ? topic : "\(cleanNamespace)/\(topic)"

        if !distro.alwaysIncludeTypeHashInKey && hashComponent.isEmpty {
            return "\(domainId)/\(topicPath)/\(ddsTypeName)"
        } else {
            return "\(domainId)/\(topicPath)/\(ddsTypeName)/\(hashComponent)"
        }
    }

    // MARK: - Liveliness Token

    /// Generate liveliness token for ROS 2 discovery
    ///
    /// Format: `@ros2_lv/<domain>/<session>/<node>/<entity>/MP/%/%/<node_name>/<topic>/<type>/<hash>/<qos>`
    public func makeLivelinessToken(
        domainId: Int,
        sessionId: String,
        nodeId: String,
        entityId: String,
        namespace: String,
        nodeName: String,
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: QoSPolicy
    ) -> String {
        let mangledTopic = TypeNameConverter.mangleTopicPath(namespace: namespace, topic: topic)
        let ddsTypeName = TypeNameConverter.toDDSTypeName(typeName)
        let hashComponent = distro.formatTypeHash(typeHash)
        let qosKeyExpr = qos.toKeyExpr()

        return "@ros2_lv/\(domainId)/\(sessionId)/\(nodeId)/\(entityId)/MP/%/%/\(nodeName)/\(mangledTopic)/\(ddsTypeName)/\(hashComponent)/\(qosKeyExpr)"
    }

    // MARK: - Attachment

    /// Build 33-byte attachment for rmw_zenoh messages
    ///
    /// Layout (Zenoh ext::Serializer format):
    /// - Bytes 0-7: seq (Int64 LE)
    /// - Bytes 8-15: timestamp_ns (Int64 LE)
    /// - Byte 16: GID array length (LEB128, 0x10 for 16 bytes)
    /// - Bytes 17-32: publisher GID (16 raw bytes)
    public func buildAttachment(
        seq: Int64,
        tsNsec: Int64,
        gid: [UInt8]
    ) -> Data {
        precondition(gid.count == 16, "Publisher GID must be exactly 16 bytes, got \(gid.count)")

        var data = Data(capacity: 33)

        var seqLE = seq.littleEndian
        withUnsafeBytes(of: &seqLE) { data.append(contentsOf: $0) }

        var tsLE = tsNsec.littleEndian
        withUnsafeBytes(of: &tsLE) { data.append(contentsOf: $0) }

        // LEB128 length prefix for 16-byte GID array
        data.append(0x10)

        data.append(contentsOf: gid)

        assert(data.count == 33, "Attachment must be exactly 33 bytes")
        return data
    }
}
