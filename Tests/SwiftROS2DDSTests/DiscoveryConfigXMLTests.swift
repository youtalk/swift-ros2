// DiscoveryConfigXMLTests.swift
// Guards the shared CycloneDDS discovery-XML builder
// (dds_bridge_build_domain_config_xml) — the SAME function the pure-Swift DDS
// path (dds_create_domain) and the RCL path (exported as CYCLONEDDS_URI for
// rmw_cyclonedds) both use, so the XML must be valid on EVERY CycloneDDS slice.
//
// Regression for youtalk/swift-ros2#149: the unicast block used to emit
// <EnableTopicDiscoveryEndpoints>, which CycloneDDS builds compiled without
// topic-discovery support (e.g. the one bundled in CRos2Jazzy on iOS) reject as
// an unknown element, failing rmw_create_node on the RCL unicast path.

import CDDSBridge
import Foundation
import XCTest

final class DiscoveryConfigXMLTests: XCTestCase {
    /// Build the discovery XML through the shared C builder, marshalling the
    /// peers into the NULL-terminated C array it expects (mirrors the
    /// marshalling in RclClient / DDSClient).
    private func buildXML(peers: [String], interface: String?, domainId: Int32 = 0) -> String? {
        var config = bridge_discovery_config_t()
        config.mode = peers.isEmpty ? BRIDGE_DISCOVERY_MULTICAST : BRIDGE_DISCOVERY_UNICAST

        var peerCStrings: [UnsafeMutablePointer<CChar>?] = peers.map { strdup($0) }
        peerCStrings.append(nil)  // NULL terminator for the C array
        let peersPtr = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: peerCStrings.count)
        defer {
            for s in peerCStrings where s != nil { free(s) }
            peersPtr.deallocate()
        }
        for (i, s) in peerCStrings.enumerated() { peersPtr[i] = s.map { UnsafePointer($0) } }
        if !peers.isEmpty {
            config.unicast_peers = peersPtr
            config.peer_count = Int32(peers.count)
        }

        var interfaceCString: UnsafeMutablePointer<CChar>?
        if let interface {
            interfaceCString = strdup(interface)
            config.network_interface = UnsafePointer(interfaceCString)
        }
        defer { if let interfaceCString { free(interfaceCString) } }

        guard let xmlPtr = dds_bridge_build_domain_config_xml(domainId, &config) else { return nil }
        defer { dds_bridge_free_string(xmlPtr) }
        return String(cString: xmlPtr)
    }

    /// The unicast block must carry the static <Peer> and the mobile-friendly
    /// <SPDPInterval>, but must NOT emit <EnableTopicDiscoveryEndpoints> — that
    /// element is compiled out of some CycloneDDS builds (CRos2Jazzy / iOS) and
    /// makes rmw_create_node reject the whole config (issue #149).
    func testUnicastXMLOmitsEnableTopicDiscoveryEndpoints() {
        let xml = buildXML(peers: ["192.168.1.85"], interface: "en0")
        XCTAssertNotNil(xml)
        XCTAssertTrue(xml!.contains("<Peer address=\"192.168.1.85\""))
        XCTAssertTrue(xml!.contains("<SPDPInterval>"))
        XCTAssertFalse(
            xml!.contains("EnableTopicDiscoveryEndpoints"),
            "discovery XML must not emit <EnableTopicDiscoveryEndpoints>: rejected by "
                + "CycloneDDS builds without topic-discovery support, failing rmw_create_node (issue #149)")
    }

    /// Multicast/default discovery emits no <Peers> block and therefore never
    /// reaches the offending element either.
    func testMulticastXMLHasNoPeersOrTopicDiscoveryElement() {
        let xml = buildXML(peers: [], interface: nil)
        XCTAssertNotNil(xml)
        XCTAssertFalse(xml!.contains("<Peer "))
        XCTAssertFalse(xml!.contains("EnableTopicDiscoveryEndpoints"))
    }
}
