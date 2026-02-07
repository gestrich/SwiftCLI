import Foundation

/// open CLI program for opening files and applications on macOS
/// Usage: open [-a <application>] [file...]
@CLIProgram
public struct Open {
    /// Open with the specified application
    @Option("-a") public var application: String?

    /// File or URL to open
    @Positional public var path: String?
}
