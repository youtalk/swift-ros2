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

    /// Generate the Zenoh service key expression
    ///
    /// Format: `<domain>/<namespace>/<service_name>/<dds_request_type_name>/<request_type_hash>`
    ///
    /// - The DDS request type name uses `<pkg>::srv::dds_::<Type>_Request_` form.
    /// - On Humble, the trailing segment is `TypeHashNotSupported`.
    /// - On Jazzy+ with no hash, the trailing segment is omitted (matching Pub/Sub).
    public func makeServiceKeyExpr(
        domainId: Int,
        namespace: String,
        serviceName: String,
        serviceTypeName: String,
        requestTypeHash: String?
    ) -> String {
        let cleanNamespace = TypeNameConverter.stripLeadingSlash(namespace)
        let ddsRequestTypeName = TypeNameConverter.toDDSServiceRequestTypeName(serviceTypeName)
        let hashComponent = distro.formatTypeHash(requestTypeHash)
        let svcPath = cleanNamespace.isEmpty ? serviceName : "\(cleanNamespace)/\(serviceName)"

        if !distro.alwaysIncludeTypeHashInKey && hashComponent.isEmpty {
            return "\(domainId)/\(svcPath)/\(ddsRequestTypeName)"
        } else {
            return "\(domainId)/\(svcPath)/\(ddsRequestTypeName)/\(hashComponent)"
        }
    }

    // MARK: - Service Liveliness Token

    /// Liveliness-token entity kind for Service entities.
    ///
    /// Parallels rmw_zenoh_cpp's per-entity-kind tags (`MP` = message publisher,
    /// `SS` = service server, `SC` = service client). Pub/Sub is hard-coded to
    /// `MP` in `makeLivelinessToken`; services pass one of these values to
    /// ``makeServiceLivelinessToken(entityKind:domainId:sessionId:nodeId:entityId:namespace:nodeName:serviceName:serviceTypeName:requestTypeHash:qos:)``.
    public enum ServiceEntityKind: String, Sendable {
        case serviceServer = "SS"
        case serviceClient = "SC"
    }

    /// Generate a Service-shaped liveliness token (`SS` / `SC`).
    ///
    /// Format: `@ros2_lv/<domain>/<session>/<node>/<entity>/<SS|SC>/%/%/<node_name>/<mangled_service_path>/<dds_request_type>/<request_hash>/<qos>`
    public func makeServiceLivelinessToken(
        entityKind: ServiceEntityKind,
        domainId: Int,
        sessionId: String,
        nodeId: String,
        entityId: String,
        namespace: String,
        nodeName: String,
        serviceName: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        qos: QoSPolicy
    ) -> String {
        let mangled = TypeNameConverter.mangleTopicPath(namespace: namespace, topic: serviceName)
        let ddsRequestTypeName = TypeNameConverter.toDDSServiceRequestTypeName(serviceTypeName)
        let hashComponent = distro.formatTypeHash(requestTypeHash)
        let qosKeyExpr = qos.toKeyExpr()

        return
            "@ros2_lv/\(domainId)/\(sessionId)/\(nodeId)/\(entityId)/\(entityKind.rawValue)/%/%/\(nodeName)/\(mangled)/\(ddsRequestTypeName)/\(hashComponent)/\(qosKeyExpr)"
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

        return
            "@ros2_lv/\(domainId)/\(sessionId)/\(nodeId)/\(entityId)/MP/%/%/\(nodeName)/\(mangledTopic)/\(ddsTypeName)/\(hashComponent)/\(qosKeyExpr)"
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
        AttachmentBuilder.build(seq: seq, tsNsec: tsNsec, gid: gid)
    }
}
