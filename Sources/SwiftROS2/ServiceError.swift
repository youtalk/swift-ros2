// ServiceError.swift
// Public error type for the service-call surface.

import Foundation
import SwiftROS2Transport

/// Errors thrown by ``ROS2Service`` and ``ROS2Client``.
///
/// The umbrella maps lower-level ``TransportError`` cases (`requestTimeout`,
/// `requestCancelled`, `serviceHandlerFailed`, …) into the service-shaped
/// variants below so callers can pattern-match on a single, ROS-friendly
/// type.
public enum ServiceError: Error, LocalizedError, Sendable {
    /// The call did not complete within the supplied deadline.
    case timeout(Duration)
    /// The service was not reachable (no server matched, or transport rejected the call).
    case serviceUnavailable(String)
    /// The remote service handler threw — typically a `ServiceError.handlerFailed`
    /// raised by the user closure on the server side.
    case handlerFailed(String)
    /// Encoding the typed request to CDR failed (client side).
    case requestEncodingFailed(String)
    /// Decoding the CDR request bytes into the typed `Request` failed (server side).
    case requestDecodingFailed(String)
    /// Decoding the CDR response into the typed `Response` failed (client side).
    case responseDecodingFailed(String)
    /// Encoding the typed response to CDR failed (server side).
    case responseEncodingFailed(String)
    /// The client was closed before / during the call.
    case clientClosed
    /// The server was closed before / during the call.
    case serverClosed
    /// The structured-concurrency Task was cancelled.
    case taskCancelled
    /// Any other transport-level error not covered by the cases above.
    case transportError(TransportError)
    /// An unexpected error that is not a `TransportError` (e.g. a
    /// `ZenohError` that escaped from the C bridge, or a `DDSError` from
    /// CycloneDDS startup). The wrapped value preserves the original error
    /// so callers can pattern-match or log it without losing fidelity.
    case underlying(Error)

    public var errorDescription: String? {
        switch self {
        case .timeout(let d): return "Service call timed out after \(d)"
        case .serviceUnavailable(let n): return "Service unavailable: \(n)"
        case .handlerFailed(let m): return "Service handler failed: \(m)"
        case .requestEncodingFailed(let m): return "Request encoding failed: \(m)"
        case .requestDecodingFailed(let m): return "Request decoding failed: \(m)"
        case .responseDecodingFailed(let m): return "Response decoding failed: \(m)"
        case .responseEncodingFailed(let m): return "Response encoding failed: \(m)"
        case .clientClosed: return "Service client is closed"
        case .serverClosed: return "Service server is closed"
        case .taskCancelled: return "Service call was cancelled"
        case .transportError(let e): return e.errorDescription
        case .underlying(let e):
            if let l = e as? LocalizedError, let d = l.errorDescription {
                return d
            }
            return String(describing: e)
        }
    }
}

extension ServiceError {
    /// Map an error thrown by the underlying transport into the closest
    /// matching `ServiceError` case. Non-`TransportError` errors are wrapped
    /// in `.underlying` so the original error survives the mapping —
    /// previously they were misreported as `.invalidConfiguration`.
    static func mapping(_ error: Error) -> ServiceError {
        if let svc = error as? ServiceError {
            return svc
        }
        guard let transport = error as? TransportError else {
            return .underlying(error)
        }
        switch transport {
        case .requestTimeout(let d): return .timeout(d)
        case .requestCancelled: return .taskCancelled
        case .serviceHandlerFailed(let m): return .handlerFailed(m)
        case .connectionTimeout(let t):
            return .serviceUnavailable("connection timed out after \(Int(t))s")
        case .notConnected: return .serviceUnavailable("not connected")
        case .sessionClosed: return .clientClosed
        default: return .transportError(transport)
        }
    }
}
