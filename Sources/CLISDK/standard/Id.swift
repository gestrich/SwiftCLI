import Foundation

/// id CLI program for getting user and group IDs
/// Usage: id [-u] [-g]
/// Use with IdParser to get structured Int output
@CLIProgram
public struct Id {
    /// Get effective user ID (-u flag)
    @Flag("-u") public var userId: Bool = false

    /// Get effective group ID (-g flag)
    @Flag("-g") public var groupId: Bool = false
}

/// Parser for id command output (returns Int)
public struct IdParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(trimmed) else {
            throw CLIClientError.invalidOutput(reason: "Expected integer, got: \(trimmed)")
        }
        return id
    }
}
