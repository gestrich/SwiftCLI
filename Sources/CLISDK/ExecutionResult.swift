import Foundation

/// Result of executing a CLI command
public struct ExecutionResult: Sendable {
    /// Exit code of the process (0 typically means success)
    public let exitCode: Int32

    /// Standard output captured from the process
    public let stdout: String

    /// Standard error captured from the process
    public let stderr: String

    /// Time taken to execute the command
    public let duration: TimeInterval

    /// Whether the command succeeded (exit code 0)
    public var isSuccess: Bool {
        exitCode == 0
    }

    /// Combined output (stdout + stderr)
    public var output: String {
        let combined = stdout + (stderr.isEmpty ? "" : "\n" + stderr)
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Error output - prefers stderr if available, otherwise falls back to stdout
    /// Use this for error messages to avoid including informational stdout content
    public var errorOutput: String {
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty {
            return error
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(exitCode: Int32, stdout: String, stderr: String, duration: TimeInterval) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

// MARK: - Stream Output

/// Unique identifier for a CLI command execution
public struct CommandID: Hashable, Sendable {
    public let value: UUID

    public init() {
        self.value = UUID()
    }
}

/// Output type for streaming commands with command ID tracking.
/// Each command gets a unique ID, and all output references that ID.
/// This allows subscribers to filter out output from commands that started
/// before they subscribed (orphaned output).
public enum StreamOutput: Sendable {
    /// A command is starting (includes the formatted command string)
    case command(id: CommandID, text: String)

    /// Standard output from a command
    case stdout(commandID: CommandID, text: String)

    /// Standard error from a command
    case stderr(commandID: CommandID, text: String)

    /// Command exited with code
    case exit(commandID: CommandID, code: Int32)

    /// Error occurred during command execution
    case error(commandID: CommandID, error: Error)

    /// The command ID associated with this output
    public var commandID: CommandID {
        switch self {
        case .command(let id, _): return id
        case .stdout(let id, _): return id
        case .stderr(let id, _): return id
        case .exit(let id, _): return id
        case .error(let id, _): return id
        }
    }

    /// Whether this is a command start event
    public var isCommand: Bool {
        if case .command = self { return true }
        return false
    }

    /// The text content (for command, stdout, stderr)
    public var text: String? {
        switch self {
        case .command(_, let text): return text
        case .stdout(_, let text): return text
        case .stderr(_, let text): return text
        case .exit, .error: return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension ExecutionResult: CustomStringConvertible {
    public var description: String {
        """
        ExecutionResult(
            exitCode: \(exitCode),
            duration: \(String(format: "%.3f", duration))s,
            stdout: \(stdout.isEmpty ? "<empty>" : "\(stdout.count) chars"),
            stderr: \(stderr.isEmpty ? "<empty>" : "\(stderr.count) chars")
        )
        """
    }
}
