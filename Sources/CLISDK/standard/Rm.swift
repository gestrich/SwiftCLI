import Foundation

/// rm CLI program for removing files and directories
/// Usage: rm [-rf] file...
@CLIProgram
public struct Rm {
    /// Remove directories and their contents recursively (-r)
    @Flag("-r") public var recursive: Bool = false

    /// Ignore nonexistent files and never prompt (-f)
    @Flag("-f") public var force: Bool = false

    /// Files or directories to remove
    @Positional public var paths: [String]
}
