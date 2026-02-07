import Foundation

/// Curl CLI program definition using macro-based API
@CLIProgram
public struct Curl {

    /// Make HTTP request
    /// Example: curl -X POST -H "Content-Type: application/json" -d '{"key":"value"}' https://example.com/api
    @CLICommand("")
    public struct Request {
        /// HTTP method (GET, POST, PUT, DELETE, etc.)
        @Option("-X") public var method: String?

        /// HTTP headers (can be specified multiple times)
        @Option("-H") public var headers: [String] = []

        /// Request body data
        @Option("-d") public var data: String?

        /// Verbose output
        @Flag("-v") public var verbose: Bool = false

        /// Silent mode (hide progress and error messages)
        @Flag("-s") public var silent: Bool = false

        /// Write output to file instead of stdout
        @Option("-o") public var output: String?

        /// Format to write after completion (e.g., %{http_code})
        @Option("-w") public var writeOut: String?

        /// URL to request (positional argument)
        @Positional public var url: String
    }
}

// MARK: - Convenience Initializers

public extension Curl.Request {
    /// Create a simple GET request
    static func get(url: String, silent: Bool = false, verbose: Bool = false) -> Self {
        Self(
            method: "GET",
            headers: [],
            data: nil,
            verbose: verbose,
            silent: silent,
            output: nil,
            writeOut: nil,
            url: url
        )
    }

    /// Create a simple POST request
    static func post(url: String, data: String? = nil, silent: Bool = false, verbose: Bool = false) -> Self {
        Self(
            method: "POST",
            headers: [],
            data: data,
            verbose: verbose,
            silent: silent,
            output: nil,
            writeOut: nil,
            url: url
        )
    }

    /// Create a POST request with JSON body
    static func postJSON(url: String, data: String, silent: Bool = false, verbose: Bool = false) -> Self {
        Self(
            method: "POST",
            headers: ["Content-Type: application/json"],
            data: data,
            verbose: verbose,
            silent: silent,
            output: nil,
            writeOut: nil,
            url: url
        )
    }

    /// Create a request that just checks HTTP status code
    static func checkStatus(url: String) -> Self {
        Self(
            method: nil,
            headers: [],
            data: nil,
            verbose: false,
            silent: true,
            output: "/dev/null",
            writeOut: "%{http_code}",
            url: url
        )
    }
}
