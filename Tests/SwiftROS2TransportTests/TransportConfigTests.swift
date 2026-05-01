import SwiftROS2Transport
import XCTest

final class TransportConfigTests: XCTestCase {
    // MARK: - TransportType

    func testTransportTypeDisplayNames() {
        XCTAssertEqual(TransportType.zenoh.displayName, "Zenoh")
        XCTAssertEqual(TransportType.dds.displayName, "DDS")
    }

    func testTransportTypeRoundTripsThroughCodable() throws {
        for type in TransportType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(TransportType.self, from: data)
            XCTAssertEqual(type, decoded)
        }
    }

    // MARK: - DDSDiscoveryMode

    func testDDSDiscoveryModePeerRequirement() {
        XCTAssertFalse(DDSDiscoveryMode.multicast.requiresPeerConfiguration)
        XCTAssertTrue(DDSDiscoveryMode.unicast.requiresPeerConfiguration)
        XCTAssertTrue(DDSDiscoveryMode.hybrid.requiresPeerConfiguration)
    }

    // MARK: - DDSPeer

    func testDDSPeerLocatorString() {
        let peer = DDSPeer(address: "192.168.1.10", port: 7400)
        XCTAssertEqual(peer.locator, "udp/192.168.1.10:7400")
    }

    func testDDSPeerDiscoveryPortFormula() {
        XCTAssertEqual(DDSPeer.discoveryPort(forDomain: 0), 7400)
        XCTAssertEqual(DDSPeer.discoveryPort(forDomain: 1), 7650)
        XCTAssertEqual(DDSPeer.discoveryPort(forDomain: 42), 17900)
    }

    func testDDSPeerFactoryAppliesDiscoveryPort() {
        let peer = DDSPeer.peer(address: "10.0.0.1", domainId: 1)
        XCTAssertEqual(peer.address, "10.0.0.1")
        XCTAssertEqual(peer.port, 7650)
    }

    // MARK: - TransportConfig.zenoh factory

    func testZenohFactoryDefaults() throws {
        let config = TransportConfig.zenoh(locator: "tcp/localhost:7447")
        XCTAssertEqual(config.type, .zenoh)
        XCTAssertEqual(config.domainId, 0)
        XCTAssertEqual(config.zenohLocator, "tcp/localhost:7447")
        XCTAssertNil(config.wireMode)
        XCTAssertEqual(config.connectionTimeout, 10.0)
        XCTAssertNoThrow(try config.validate())
    }

    // MARK: - TransportConfig.ddsMulticast factory

    func testDDSMulticastFactoryValidates() throws {
        let config = TransportConfig.ddsMulticast(domainId: 5)
        XCTAssertEqual(config.type, .dds)
        XCTAssertEqual(config.domainId, 5)
        XCTAssertEqual(config.ddsDiscoveryMode, .multicast)
        XCTAssertNoThrow(try config.validate())
    }

    func testDDSUnicastFactoryRequiresPeers() throws {
        let goodConfig = TransportConfig.ddsUnicast(
            peers: [DDSPeer(address: "10.0.0.1")],
            domainId: 0
        )
        XCTAssertNoThrow(try goodConfig.validate())

        let badConfig = TransportConfig.ddsUnicast(peers: [], domainId: 0)
        XCTAssertThrowsError(try badConfig.validate()) { error in
            guard case TransportError.invalidConfiguration = error else {
                XCTFail("Expected invalidConfiguration, got \(error)")
                return
            }
        }
    }

    // MARK: - validate()

    func testValidateRejectsNegativeDomainId() {
        let config = TransportConfig(type: .zenoh, domainId: -1, zenohLocator: "tcp/x:7447")
        XCTAssertThrowsError(try config.validate())
    }

    func testValidateRejectsTooLargeDomainId() {
        let config = TransportConfig(type: .zenoh, domainId: 233, zenohLocator: "tcp/x:7447")
        XCTAssertThrowsError(try config.validate())
    }

    func testValidateAcceptsBoundaryDomainIds() throws {
        let lo = TransportConfig(type: .zenoh, domainId: 0, zenohLocator: "tcp/x:7447")
        let hi = TransportConfig(type: .zenoh, domainId: 232, zenohLocator: "tcp/x:7447")
        XCTAssertNoThrow(try lo.validate())
        XCTAssertNoThrow(try hi.validate())
    }

    func testValidateRejectsZenohWithoutLocator() {
        let config = TransportConfig(type: .zenoh, zenohLocator: nil)
        XCTAssertThrowsError(try config.validate())
    }

    func testValidateRejectsZenohWithEmptyLocator() {
        let config = TransportConfig(type: .zenoh, zenohLocator: "")
        XCTAssertThrowsError(try config.validate())
    }
}
