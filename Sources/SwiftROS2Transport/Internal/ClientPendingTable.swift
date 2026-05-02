// ClientPendingTable.swift
// Per-Service-Client correlation table for DDS request / reply matching.

import Foundation

/// Per-Service-Client correlation table.
///
/// Each in-flight `call(...)` registers a continuation keyed by sequence
/// number. The transport's reply handler looks up by sequence number and
/// resolves. Used by DDS — Zenoh's queryable primitive owns correlation
/// natively, so the Zenoh transport does not need this.
actor ClientPendingTable {
    private var pending: [Int64: CheckedContinuation<Data, Error>] = [:]

    /// Register a continuation under `seq` and run `register` to wire up the
    /// caller (e.g. issue the request). `register` runs while the actor holds
    /// the table; do not perform long work inside it.
    func insert(
        seq: Int64,
        register: (CheckedContinuation<Data, Error>) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            pending[seq] = cont
            register(cont)
        }
    }

    @discardableResult
    func resolve(seq: Int64, with result: Result<Data, Error>) -> Bool {
        guard let cont = pending.removeValue(forKey: seq) else { return false }
        cont.resume(with: result)
        return true
    }

    @discardableResult
    func cancel(seq: Int64) -> Bool {
        guard let cont = pending.removeValue(forKey: seq) else { return false }
        cont.resume(throwing: TransportError.requestCancelled)
        return true
    }

    func failAll(_ error: Error) {
        let snapshot = pending
        pending.removeAll()
        for (_, cont) in snapshot {
            cont.resume(throwing: error)
        }
    }
}
