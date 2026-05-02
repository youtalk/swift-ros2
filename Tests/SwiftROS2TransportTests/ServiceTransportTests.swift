// ServiceTransportTests.swift
// DDS Service Server / Client end-to-end tests using MockDDSClient.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class DDSServiceTransportTests: XCTestCase {
    func testServerEchoesRequest() async throws {
        let client = MockDDSClient()
        let session = DDSTransportSession(client: client)
        try await session.open(config: .ddsMulticast(domainId: 0))

        let received = Box<Data?>(nil)
        let server = try session.createServiceServer(
            name: "/echo",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: nil,
            responseTypeHash: nil,
            qos: .sensorData,
            handler: { req in
                received.value = req
                return Data([0x00, 0x01, 0x00, 0x00, 0xCC])
            }
        )

        let id = RMWRequestId(writerGuid: Array(repeating: 0xAB, count: 16), sequenceNumber: 7)
        let userCDR = Data([0x00, 0x01, 0x00, 0x00, 0xDE])
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: userCDR)

        try await client.deliverToReader(topic: "rq/echoRequest", wire: wire, timestamp: 1_000)

        let written = try await client.awaitWrite(topic: "rr/echoReply", timeout: .seconds(1))
        let writtenBytes = try XCTUnwrap(written)

        XCTAssertEqual(received.value, userCDR)

        let (parsedId, parsedBody) = try SampleIdentityPrefix.decode(wirePayload: writtenBytes)
        XCTAssertEqual(parsedId, id)
        XCTAssertEqual(parsedBody, Data([0x00, 0x01, 0x00, 0x00, 0xCC]))
        try server.close()
    }

    func testClientWritesPrefixedRequestAndAwaitsReply() async throws {
        let client = MockDDSClient()
        let session = DDSTransportSession(client: client)
        try await session.open(config: .ddsMulticast(domainId: 0))

        let svc = try session.createServiceClient(
            name: "/echo",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: nil,
            responseTypeHash: nil,
            qos: .sensorData
        )

        client.markPublicationsMatched(topic: "rq/echoRequest")

        let userRequest = Data([0x00, 0x01, 0x00, 0x00, 0xDE])
        async let response: Data = svc.call(requestCDR: userRequest, timeout: .seconds(1))

        let writtenWire = try await client.awaitWrite(topic: "rq/echoRequest", timeout: .seconds(1))
        let bytes = try XCTUnwrap(writtenWire)
        let (id, parsedReq) = try SampleIdentityPrefix.decode(wirePayload: bytes)
        XCTAssertEqual(parsedReq, userRequest)
        XCTAssertEqual(id.writerGuid.count, 16)
        XCTAssertEqual(id.sequenceNumber, 1)

        let userReply = Data([0x00, 0x01, 0x00, 0x00, 0xEE])
        let replyWire = SampleIdentityPrefix.encode(requestId: id, userCDR: userReply)
        try await client.deliverToReader(topic: "rr/echoReply", wire: replyWire, timestamp: 0)

        let body = try await response
        XCTAssertEqual(body, userReply)
        try svc.close()
    }

    func testClientTimesOut() async throws {
        let client = MockDDSClient()
        let session = DDSTransportSession(client: client)
        try await session.open(config: .ddsMulticast(domainId: 0))
        let svc = try session.createServiceClient(
            name: "/echo",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: nil,
            responseTypeHash: nil,
            qos: .sensorData
        )
        client.markPublicationsMatched(topic: "rq/echoRequest")

        do {
            _ = try await svc.call(
                requestCDR: Data([0x00, 0x01, 0x00, 0x00]),
                timeout: .milliseconds(50)
            )
            XCTFail("should have timed out")
        } catch TransportError.requestTimeout {
            // expected
        }
        try svc.close()
    }

    func testClientCancellationPropagates() async throws {
        let client = MockDDSClient()
        let session = DDSTransportSession(client: client)
        try await session.open(config: .ddsMulticast(domainId: 0))
        let svc = try session.createServiceClient(
            name: "/echo",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: nil,
            responseTypeHash: nil,
            qos: .sensorData
        )
        client.markPublicationsMatched(topic: "rq/echoRequest")

        let task = Task {
            try await svc.call(
                requestCDR: Data([0x00, 0x01, 0x00, 0x00]),
                timeout: .seconds(60)
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("should have been cancelled")
        } catch TransportError.requestCancelled {
            // expected
        }
        try svc.close()
    }
}
