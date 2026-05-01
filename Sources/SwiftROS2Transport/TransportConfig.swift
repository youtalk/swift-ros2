// TransportConfig.swift
// Transport configuration types

import Foundation
import SwiftROS2Wire

// MARK: - Transport Type

/// The underlying transport mechanism used to connect to ROS 2.
///
/// Choose `.zenoh` for cross-platform support (including mobile and desktop) or
/// `.dds` for direct CycloneDDS communication on Apple platforms and Linux.
public enum TransportType: String, Codable, CaseIterable, Sendable {
    case zenoh
    case dds

    public var displayName: String {
        switch self {
        case .zenoh: return "Zenoh"
        case .dds: return "DDS"
        }
    }
}

// MARK: - DDS Discovery Mode

/// How CycloneDDS discovers remote participants on the network.
///
/// Use `.multicast` on networks that support it, `.unicast` when multicast is blocked
/// (common on Wi-Fi), or `.hybrid` to try multicast first and fall back to unicast.
public enum DDSDiscoveryMode: String, Codable, CaseIterable, Sendable {
    case multicast
    case unicast
    case hybrid

    public var requiresPeerConfiguration: Bool {
        switch self {
        case .multicast: return false
        case .unicast, .hybrid: return true
        }
    }
}

// MARK: - DDS Peer

/// A remote DDS participant identified by IP address and UDP port.
///
/// Used to configure unicast or hybrid DDS discovery when multicast is unavailable.
/// The discovery port follows the CycloneDDS formula: `7400 + domainId * 250`.
public struct DDSPeer: Codable, Equatable, Sendable {
    public let address: String
    public let port: UInt16

    public init(address: String, port: UInt16 = 7400) {
        self.address = address
        self.port = port
    }

    public var locator: String {
        "udp/\(address):\(port)"
    }

    public static func discoveryPort(forDomain domainId: Int) -> UInt16 {
        UInt16(7400 + domainId * 250)
    }

    public static func peer(address: String, domainId: Int) -> DDSPeer {
        DDSPeer(address: address, port: discoveryPort(forDomain: domainId))
    }
}

// MARK: - Transport Configuration

/// Complete configuration for a transport session, covering both Zenoh and DDS parameters.
///
/// Construct instances using the static factory methods ``zenoh(locator:domainId:wireMode:connectionTimeout:)``,
/// ``ddsMulticast(domainId:)``, or ``ddsUnicast(peers:domainId:)`` rather than the memberwise initializer.
public struct TransportConfig: Sendable {
    public let type: TransportType
    public let domainId: Int

    // Zenoh-specific
    public let zenohLocator: String?
    public let wireMode: ROS2Distro?
    public let connectionTimeout: TimeInterval

    // DDS-specific
    public let ddsDiscoveryMode: DDSDiscoveryMode
    public let ddsUnicastPeers: [DDSPeer]
    public let ddsNetworkInterface: String?

    public static func zenoh(
        locator: String,
        domainId: Int = 0,
        wireMode: ROS2Distro? = nil,
        connectionTimeout: TimeInterval = 10.0
    ) -> TransportConfig {
        TransportConfig(
            type: .zenoh, domainId: domainId,
            zenohLocator: locator, wireMode: wireMode,
            connectionTimeout: connectionTimeout,
            ddsDiscoveryMode: .multicast, ddsUnicastPeers: [], ddsNetworkInterface: nil
        )
    }

    public static func ddsMulticast(domainId: Int = 0) -> TransportConfig {
        TransportConfig(
            type: .dds, domainId: domainId,
            zenohLocator: nil, wireMode: nil, connectionTimeout: 10.0,
            ddsDiscoveryMode: .multicast, ddsUnicastPeers: [], ddsNetworkInterface: nil
        )
    }

    public static func ddsUnicast(peers: [DDSPeer], domainId: Int = 0) -> TransportConfig {
        TransportConfig(
            type: .dds, domainId: domainId,
            zenohLocator: nil, wireMode: nil, connectionTimeout: 10.0,
            ddsDiscoveryMode: .unicast, ddsUnicastPeers: peers, ddsNetworkInterface: nil
        )
    }

    public init(
        type: TransportType,
        domainId: Int = 0,
        zenohLocator: String? = nil,
        wireMode: ROS2Distro? = nil,
        connectionTimeout: TimeInterval = 10.0,
        ddsDiscoveryMode: DDSDiscoveryMode = .multicast,
        ddsUnicastPeers: [DDSPeer] = [],
        ddsNetworkInterface: String? = nil
    ) {
        self.type = type
        self.domainId = domainId
        self.zenohLocator = zenohLocator
        self.wireMode = wireMode
        self.connectionTimeout = connectionTimeout
        self.ddsDiscoveryMode = ddsDiscoveryMode
        self.ddsUnicastPeers = ddsUnicastPeers
        self.ddsNetworkInterface = ddsNetworkInterface
    }

    public func validate() throws {
        guard domainId >= 0 && domainId <= 232 else {
            throw TransportError.invalidConfiguration("Domain ID must be 0-232, got \(domainId)")
        }
        switch type {
        case .zenoh:
            guard let locator = zenohLocator, !locator.isEmpty else {
                throw TransportError.invalidConfiguration("Zenoh transport requires a router locator")
            }
        case .dds:
            if ddsDiscoveryMode.requiresPeerConfiguration && ddsUnicastPeers.isEmpty {
                throw TransportError.invalidConfiguration("DDS \(ddsDiscoveryMode) mode requires peer configuration")
            }
        }
    }
}
