import Foundation

/// Errors that can occur during CLI client operations
public enum CLIClientError: Error, LocalizedError, Sendable {
    /// Command executable not found
    case commandNotFound(String)

    /// Command execution failed with non-zero exit code
    case executionFailed(command: String, exitCode: Int32, output: String)

    /// Command timed out
    case timeout(command: String, duration: TimeInterval)

    /// Invalid command format
    case invalidCommand(String)

    /// Invalid output or parsing error
    case invalidOutput(reason: String)

    /// Working directory does not exist
    case invalidWorkingDirectory(String)

    /// Permission denied
    case permissionDenied(command: String, details: String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return "Command not found: '\(command)'"

        case .executionFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Command '\(command)' failed with exit code \(exitCode): \(errorOutput)"

        case .timeout(let command, let duration):
            return "Command '\(command)' timed out after \(String(format: "%.1f", duration)) seconds"

        case .invalidCommand(let reason):
            return "Invalid command: \(reason)"

        case .invalidOutput(let reason):
            return "Invalid output: \(reason)"

        case .invalidWorkingDirectory(let path):
            return "Invalid working directory: '\(path)' does not exist"

        case .permissionDenied(let command, let details):
            return "Permission denied for command '\(command)': \(details)"
        }
    }
}
