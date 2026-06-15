#if SWIFT_ROS2_RCL
    import CDDSBridge
    import Foundation
    import SwiftROS2RCL
    import SwiftROS2Transport
    import XCTest

    /// Axis 3 (correctness) byte-shape guard: the RCL path and the wire DDS path
    /// build their CycloneDDS discovery XML through the SAME shared CDDSBridge
    /// builder (`dds_bridge_build_domain_config_xml`), so both backends discover
    /// identically. Pure: no rmw, no env mutation, no transport.
    final class RclDiscoveryEnvTests: XCTestCase {
        func testDiscoveryURIXMLCarriesPeersAndInterface() {
            let xml = RclClient().makeDiscoveryURIXML(
                domainId: 0, unicastPeerAddresses: ["192.168.1.85"], networkInterface: "en0")
            XCTAssertNotNil(xml)
            XCTAssertTrue(xml!.contains("<Peer address=\"192.168.1.85\""))
            XCTAssertTrue(xml!.contains("<NetworkInterface name=\"en0\""))
            XCTAssertTrue(xml!.contains("SPDP"))  // SPDPInterval present in the unicast block
        }

        func testDiscoveryURIXMLMulticastHasNoPeers() {
            let xml = RclClient().makeDiscoveryURIXML(
                domainId: 0, unicastPeerAddresses: [], networkInterface: nil)
            XCTAssertNotNil(xml)
            XCTAssertFalse(xml!.contains("<Peer "))
        }

        /// The real env-export path: applyDiscoveryEnv actually sets CYCLONEDDS_URI
        /// (carrying <Peer> + <NetworkInterface>), and restoreDiscoveryEnv puts the
        /// prior value back. This is what rmw_cyclonedds reads at participant
        /// creation; createContext/destroyContext drive these two methods.
        func testApplyDiscoveryEnvExportsAndRestoresCyclonedDDSURI() {
            // Hermetic: snapshot + restore whatever the environment already had.
            let outerPrior = getenv("CYCLONEDDS_URI").map { String(cString: $0) }
            defer {
                if let p = outerPrior { setenv("CYCLONEDDS_URI", p, 1) } else { unsetenv("CYCLONEDDS_URI") }
            }
            unsetenv("CYCLONEDDS_URI")  // known-clear starting point

            let client = RclClient()
            let applied = client.applyDiscoveryEnv(
                domainId: 0, unicastPeerAddresses: ["192.168.1.85"], networkInterface: "en0")
            XCTAssertTrue(applied)
            let uri = getenv("CYCLONEDDS_URI").map { String(cString: $0) }
            XCTAssertNotNil(uri)
            XCTAssertTrue(uri!.contains("<Peer address=\"192.168.1.85\""))
            XCTAssertTrue(uri!.contains("<NetworkInterface name=\"en0\""))

            client.restoreDiscoveryEnv()
            // Cleared before applying → restore must clear it again.
            XCTAssertNil(getenv("CYCLONEDDS_URI").map { String(cString: $0) })
        }

        /// Multicast/default discovery must not touch the process environment.
        func testApplyDiscoveryEnvIsNoOpForMulticast() {
            let outerPrior = getenv("CYCLONEDDS_URI").map { String(cString: $0) }
            defer {
                if let p = outerPrior { setenv("CYCLONEDDS_URI", p, 1) } else { unsetenv("CYCLONEDDS_URI") }
            }
            let applied = RclClient().applyDiscoveryEnv(
                domainId: 0, unicastPeerAddresses: [], networkInterface: nil)
            XCTAssertFalse(applied)
        }

        /// The route-(b) raw writer must honour the caller's QoS rather than the
        /// best-effort/volatile sensor-data default. makeBridgeQoS maps every
        /// knob through to the CDDSBridge config (it is passed as the writer's
        /// QoS, not nil).
        func testMakeBridgeQoSHonoursCallerReliabilityDurabilityHistory() {
            let reliable = RclClient().makeBridgeQoS(
                TransportQoS(reliability: .reliable, durability: .transientLocal, history: .keepLast(7)))
            XCTAssertEqual(reliable.reliability, BRIDGE_RELIABILITY_RELIABLE)
            XCTAssertEqual(reliable.durability, BRIDGE_DURABILITY_TRANSIENT_LOCAL)
            XCTAssertEqual(reliable.history_kind, BRIDGE_HISTORY_KEEP_LAST)
            XCTAssertEqual(reliable.history_depth, 7)

            let bestEffort = RclClient().makeBridgeQoS(
                TransportQoS(reliability: .bestEffort, durability: .volatile, history: .keepAll))
            XCTAssertEqual(bestEffort.reliability, BRIDGE_RELIABILITY_BEST_EFFORT)
            XCTAssertEqual(bestEffort.durability, BRIDGE_DURABILITY_VOLATILE)
            XCTAssertEqual(bestEffort.history_kind, BRIDGE_HISTORY_KEEP_ALL)
        }
    }
#endif
