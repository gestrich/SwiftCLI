import Foundation

/// lsof CLI program for listing open files and network connections
/// Usage: lsof -i :PORT [-t]
/// Use with LsofPidParser when using -t flag to get [Int] PIDs
@CLIProgram
public struct Lsof {
    /// Port specification (e.g., ":8080")
    @Option("-i") public var port: String

    /// Only return PIDs (-t flag)
    @Flag("-t") public var pidOnly: Bool = false
}

/// Parser for lsof -t output (returns list of PIDs as Int)
public struct LsofPidParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [Int] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try trimmed
            .split(separator: "\n")
            .map { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard let pid = Int(trimmedLine) else {
                    throw CLIClientError.invalidOutput(reason: "Expected integer PID, got: \(line)")
                }
                return pid
            }
    }
}
