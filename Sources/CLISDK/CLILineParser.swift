import Foundation

/// A parser that transforms each stdout line into a typed value as it arrives.
///
/// Unlike `CLIOutputParser` (which parses complete stdout after a command finishes),
/// `CLILineParser` parses each line individually during streaming. Return `nil` to skip a line.
public protocol CLILineParser<Output>: Sendable {
    associatedtype Output: Sendable
    func parse(line: String) throws -> Output?
}

// MARK: - Built-in Line Parsers

/// Yields all non-empty lines as `String`
public struct PassthroughLineParser: CLILineParser {
    public init() {}

    public func parse(line: String) -> String? {
        line.isEmpty ? nil : line
    }
}

/// Decodes each line as JSON, skipping lines that fail to decode
public struct JSONLineParser<T: Decodable & Sendable>: CLILineParser {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func parse(line: String) -> T? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
