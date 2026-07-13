// TransportPublisherTypedDefaultTests.swift
// Covers the protocol-extension defaults in TransportPublisher+TypedDefault.swift:
// a publisher that does not override the typed-publish seam must report
// supportsTypedPublish == false and throw unsupportedFeature from publishTyped.

import Foundation
import XCTest

@testable import SwiftROS2Transport

/// Minimal conformer that intentionally does NOT override the typed-publish
/// members, so the protocol-extension defaults are the ones exercised.
private struct DefaultBehaviorPublisher: TransportPublisher {
    let topic = "typed_default"
    let isActive = true
    func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws {}
    func close() throws {}
}

/// Typed-publishable stand-in; never marshalled because the default
/// publishTyped throws before touching it.
private struct NoopTypedPublishable: RclTypedPublishable {
    func rclTypedPublish(into handle: any RclPublisherHandle) throws {}
}

final class TransportPublisherTypedDefaultTests: XCTestCase {
    func testDefaultSupportsTypedPublishIsFalse() {
        let publisher = DefaultBehaviorPublisher()
        XCTAssertFalse(publisher.supportsTypedPublish)
    }

    func testDefaultPublishTypedThrowsUnsupportedFeature() {
        let publisher = DefaultBehaviorPublisher()
        XCTAssertThrowsError(try publisher.publishTyped(NoopTypedPublishable())) { error in
            guard case TransportError.unsupportedFeature(let detail) = error else {
                XCTFail("expected TransportError.unsupportedFeature, got \(error)")
                return
            }
            XCTAssertTrue(detail.contains("typed publish"))
        }
    }
}
