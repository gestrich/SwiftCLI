/// Protocol for CLI programs (executables like git, docker, swift)
public protocol CLIProgram: Sendable {
    /// The program/executable name (e.g., "git", "docker")
    static var programName: String { get }
}
