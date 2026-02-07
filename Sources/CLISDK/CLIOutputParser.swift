import Foundation

/// A reusable parser that transforms raw CLI output into typed results
///
/// Use this protocol to create reusable parsers that can be shared across
/// multiple commands or used as overrides via `CLIClient.execute(_:parser:)`.
public protocol CLIOutputParser<Output>: Sendable {
    associatedtype Output: Sendable

    /// Parse raw stdout into typed output
    /// - Parameter output: Raw stdout string
    /// - Returns: Parsed output
    /// - Throws: CLIClientError.invalidOutput if parsing fails
    func parse(_ output: String) throws -> Output
}

// MARK: - Built-in Parsers

/// Returns the raw string with whitespace trimmed
public struct StringParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Parses output into an array of lines
public struct LinesParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
    }
}

/// Parses JSON output into a Decodable type
public struct JSONOutputParser<T: Decodable & Sendable>: CLIOutputParser {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func parse(_ output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw CLIClientError.invalidOutput(reason: "Output is not valid UTF-8")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CLIClientError.invalidOutput(reason: "JSON decode failed: \(error.localizedDescription)")
        }
    }
}
