// ZenohTransportSession+Service.swift
// Service Server / Client stubs for the Zenoh transport.
//
// The real implementation lands in phase 6. For phase 3 these methods
// throw `TransportError.unsupportedFeature` so the build is green and
// callers get a clear error if they reach for services on Zenoh today.

import Foundation

extension ZenohTransportSession {
    public func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService {
        throw TransportError.unsupportedFeature("Zenoh service server (phase 6)")
    }

    public func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient {
        throw TransportError.unsupportedFeature("Zenoh service client (phase 6)")
    }
}
