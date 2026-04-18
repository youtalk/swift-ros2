// GIDManager.swift
// Publisher GID (Global Identifier) management

import Foundation

/// Manages a stable 16-byte publisher GID
///
/// The GID uniquely identifies a publisher and must be stable across
/// publish calls within a session. Platform-specific persistence
/// (Keychain on iOS/macOS, file on Linux) can be added later.
public final class GIDManager: @unchecked Sendable {
    public static let gidSize = 16

    private var cachedGid: [UInt8]?
    private let lock = NSLock()

    public init() {}

    /// Get or create a 16-byte publisher GID
    public func getOrCreateGid() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }

        if let gid = cachedGid {
            return gid
        }

        let gid = generateRandomGid()
        cachedGid = gid
        return gid
    }

    /// Reset the GID (generates a new one on next access)
    public func reset() {
        lock.lock()
        cachedGid = nil
        lock.unlock()
    }

    private func generateRandomGid() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.gidSize)
        #if canImport(Security)
            // Use SecRandomCopyBytes on Apple platforms
            let status = SecRandomCopyBytes(kSecRandomDefault, Self.gidSize, &bytes)
            if status == errSecSuccess {
                return bytes
            }
        #endif
        // Fallback: UUID bytes
        let uuid = UUID()
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        return Array(uuidBytes.prefix(Self.gidSize))
    }
}
