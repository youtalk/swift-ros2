// TransportQoS+QoSPolicy.swift
// Conversion from TransportQoS to wire-level QoSPolicy.
//
// Lives in SwiftROS2Transport because the conversion is consumed by
// transport sessions when emitting liveliness tokens. The function
// itself is a pure mapping and has no transport-specific logic.

import Foundation
import SwiftROS2Wire

extension TransportQoS {
    /// Convert to wire-level QoSPolicy for liveliness token encoding
    public func toQoSPolicy() -> QoSPolicy {
        let rel: QoSPolicy.Reliability = self.reliability == .reliable ? .reliable : .bestEffort
        let dur: QoSPolicy.Durability = self.durability == .transientLocal ? .transientLocal : .volatile
        let hist: QoSPolicy.HistoryPolicy
        let depth: Int

        switch self.history {
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
}
