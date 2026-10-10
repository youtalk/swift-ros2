// TransportPublisher+MatchedDefault.swift
// Default matched-subscription state: unknown. Transports that can tell override it.

extension TransportPublisher {
    package var matchedSubscriptions: Bool? { nil }
}
