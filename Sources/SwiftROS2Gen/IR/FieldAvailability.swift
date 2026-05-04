/// Tracks which ROS 2 distros define a particular field of a merged message.
///
/// `SwiftROS2Gen` does not depend on `SwiftROS2Wire`, so distro names are
/// raw strings ("humble", "jazzy", "kilted", "rolling") rather than the
/// `ROS2Distro` enum. The runtime side maps these to `ROS2Distro` when
/// emitting `typeInfo(for:)` switches.
public enum FieldAvailability: Equatable, Sendable {
    /// Field exists in every distro the message was built against.
    case all
    /// Field exists only in the listed distros (set of raw names).
    case onlyIn(Set<String>)

    /// True if the field is present for the given distro name.
    public func includes(_ distro: String) -> Bool {
        switch self {
        case .all: return true
        case .onlyIn(let set): return set.contains(distro)
        }
    }
}
