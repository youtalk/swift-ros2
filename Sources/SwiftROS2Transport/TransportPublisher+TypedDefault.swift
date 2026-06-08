// TransportPublisher+TypedDefault.swift
// Default typed-publish behavior: unsupported. Only RclTransportPublisher overrides.

extension TransportPublisher {
    package var supportsTypedPublish: Bool { false }

    package func publishTyped(_ publishable: any RclTypedPublishable) throws {
        throw TransportError.unsupportedFeature(
            "typed publish is only supported on the .rcl transport")
    }
}
