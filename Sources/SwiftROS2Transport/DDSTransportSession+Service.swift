// DDSTransportSession+Service.swift
// Service Server / Client stubs for the DDS transport.
//
// The real implementation lands in phase 4. For phase 3 these methods
// throw `TransportError.unsupportedFeature` so the build is green and
// callers get a clear error if they reach for services on DDS today.

import Foundation

extension DDSTransportSession {
    public func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService {
        throw TransportError.unsupportedFeature("DDS service server (phase 4)")
    }

    public func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient {
        throw TransportError.unsupportedFeature("DDS service client (phase 4)")
    }
}
