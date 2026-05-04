import Foundation

public struct ParseError: Error, CustomStringConvertible, Equatable, Sendable {
    public let file: String  // Source file path or descriptive label.
    public let line: Int  // 1-based.
    public let message: String  // Human-readable diagnostic.

    public init(file: String, line: Int, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        "\(file):\(line): \(message)"
    }
}
