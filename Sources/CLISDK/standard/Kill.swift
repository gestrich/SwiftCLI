import Foundation

/// kill CLI program for sending signals to processes
/// Usage: kill [-signal] PID...
@CLIProgram
public struct Kill {
    /// Signal to send (e.g., "9", "TERM", "KILL"). Defaults to TERM if not specified.
    @PrefixOption("-") public var signal: String?

    /// Process ID to send signal to
    @Positional public var pid: String
}
