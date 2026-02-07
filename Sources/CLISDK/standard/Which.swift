import Foundation

/// which CLI program for locating commands
/// Usage: which [-a] command
@CLIProgram
public struct Which {
    /// Show all matches (not just the first one)
    @Flag("-a") public var all: Bool = false

    /// Command name to locate
    @Positional public var command: String
}
