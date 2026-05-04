// Source-compat conveniences for the IDL-generated `UniqueIdentifierUUID`.
// Mirrors the hand-written API surface that pre-dated the swift-ros2-gen
// migration — keeps Conduit-style call sites that bridge to / from
// `Foundation.UUID` compiling without churn.
//
// The pre-migration struct enforced `uuid.count == 16` via a `precondition`
// inside `init(uuid:)` and exposed `uuid` as `private(set)`. The generator
// emits a public mutable property and no precondition. We do **not** restore
// either guard here: invalid mutations now fail at encode/decode time with a
// clear CDR error rather than aborting the process at construction. The
// 16-element default in the generator's `init(uuid:)` keeps the common path
// safe by construction.

import Foundation

extension UniqueIdentifierUUID {
    /// Build from a `Foundation.UUID`. The 16-byte tuple is unpacked into the
    /// `uuid: [UInt8]` storage in big-endian order, matching `UUID.uuid`.
    public init(foundationUUID: Foundation.UUID) {
        let t = foundationUUID.uuid
        self.init(uuid: [
            t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
            t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15,
        ])
    }

    /// Return the underlying 16 bytes as a `Foundation.UUID`. Reading this
    /// when `uuid.count != 16` is a programming error and traps via an
    /// out-of-bounds subscript — same effective contract as the original
    /// hand-written precondition.
    public var foundationUUID: Foundation.UUID {
        Foundation.UUID(
            uuid: (
                uuid[0], uuid[1], uuid[2], uuid[3],
                uuid[4], uuid[5], uuid[6], uuid[7],
                uuid[8], uuid[9], uuid[10], uuid[11],
                uuid[12], uuid[13], uuid[14], uuid[15]
            ))
    }
}
