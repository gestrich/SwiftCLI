import Foundation

/// sh CLI program for executing shell commands
/// Usage: sh -c "command string"
@CLIProgram
public struct Sh {
    /// Execute command string (-c)
    @Flag("-c") public var executeCommand: Bool = true

    /// The command string to execute
    @Positional public var command: String
}
