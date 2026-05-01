// TransportQoSMapper.swift
// Internal mapping helpers from TransportQoS to wire and DDS-bridge QoS.
//
// Centralizes the shared mapping logic so DDSTransportSession.bridgeQoS,
// TransportQoS.toQoSPolicy, and any future consumer all share one
// implementation. Internal — public callers go through the existing
// public conversion methods.

import SwiftROS2Wire

enum TransportQoSMapper {
    static func toWireQoSPolicy(_ qos: TransportQoS) -> QoSPolicy {
        let rel: QoSPolicy.Reliability = qos.reliability == .reliable ? .reliable : .bestEffort
        let dur: QoSPolicy.Durability = qos.durability == .transientLocal ? .transientLocal : .volatile
        let hist: QoSPolicy.HistoryPolicy
        let depth: Int

        switch qos.history {
        case .keepLast(let n):
            hist = .keepLast
            depth = n
        case .keepAll:
            hist = .keepAll
            depth = 1000
        }

        return QoSPolicy(
            reliability: rel,
            durability: dur,
            historyPolicy: hist,
            historyDepth: depth
        )
    }

    static func toDDSBridgeQoSConfig(_ qos: TransportQoS) -> DDSBridgeQoSConfig {
        let kind: DDSBridgeQoSConfig.HistoryKind
        let depth: Int32
        switch qos.history {
        case .keepLast(let n):
            kind = .keepLast
            depth = Int32(n)
        case .keepAll:
            kind = .keepAll
            depth = 0
        }

        return DDSBridgeQoSConfig(
            reliability: qos.reliability == .reliable ? .reliable : .bestEffort,
            durability: qos.durability == .transientLocal ? .transientLocal : .volatile,
            historyKind: kind,
            historyDepth: depth
        )
    }
}
