import Foundation

/// Git CLI program definition using macro-based API
@CLIProgram
public struct Git {
    /// Git merge command
    /// Example: git merge --no-ff -m "Merge feature" feature-branch
    @CLICommand
    public struct Merge {
        /// Use --no-fast-forward merge strategy
        @Flag public var noFastForward: Bool = false

        /// Commit message for the merge
        @Option("-m") public var message: String?

        /// Branch to merge
        @Positional public var branch: String
    }

    /// Git log command
    /// Use with GitLogParser to get structured output
    @CLICommand
    public struct Log {
        /// Custom format for machine parsing (baked in)
        @Option public var format: String = "%H|%an|%ae|%s|%aI"

        /// Limit number of commits
        @Option("-n") public var maxCount: String?

        /// Starting point (branch, tag, or commit)
        @Positional public var revision: String?
    }

    /// Git status command
    /// Use with GitStatusParser to get structured output when using --porcelain
    @CLICommand
    public struct Status {
        /// Use porcelain format for machine parsing
        @Flag public var porcelain: Bool = false
    }

    /// Git diff command
    @CLICommand
    public struct Diff {
        @Flag public var staged: Bool = false
        @Positional public var path: String?
    }

    /// Git rev-list command for counting commits
    /// Example: git rev-list @{u}..HEAD --count
    @CLICommand
    public struct RevList {
        /// Count commits instead of listing them
        @Flag public var count: Bool = false

        /// Revision range (e.g., "@{u}..HEAD" for commits ahead of upstream)
        @Positional public var range: String
    }

    /// Git branch command
    /// Example: git branch --show-current
    @CLICommand
    public struct Branch {
        /// Show only the current branch name
        @Flag public var showCurrent: Bool = false
    }

    /// Git push command
    /// Example: git push
    @CLICommand
    public struct Push {
        /// Set upstream for the branch
        @Flag("-u") public var setUpstream: Bool = false

        /// Remote name (optional, defaults to origin)
        @Positional public var remote: String?

        /// Branch name (optional)
        @Positional public var branch: String?
    }

    /// Git config command
    /// Example: git config --get remote.origin.url
    @CLICommand
    public struct Config {
        /// Get the value for a given key
        @Flag public var get: Bool = false

        /// Configuration key
        @Positional public var key: String
    }
}

// MARK: - Parsers

/// Parser for git rev-list --count output
public struct GitRevListCountParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(trimmed) else {
            throw CLIClientError.invalidOutput(
                reason: "Expected integer from git rev-list --count, got '\(trimmed)'"
            )
        }
        return count
    }
}

/// Parser for git log output with pipe-delimited format
public struct GitLogParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [GitCommit] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        return try lines.map { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 5 else {
                throw CLIClientError.invalidOutput(
                    reason: "Expected 5 fields in git log output, got \(parts.count)"
                )
            }
            return GitCommit(
                hash: parts[0],
                authorName: parts[1],
                authorEmail: parts[2],
                subject: parts[3],
                date: ISO8601DateFormatter().date(from: parts[4]) ?? Date()
            )
        }
    }
}

/// Parser for git status --porcelain output
public struct GitStatusParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> GitStatusResult {
        var staged: [GitFileChange] = []
        var unstaged: [GitFileChange] = []
        var untracked: [String] = []

        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            guard line.count >= 3 else { continue }

            let indexStatus = line[line.startIndex]
            let workTreeStatus = line[line.index(after: line.startIndex)]
            let path = String(line.dropFirst(3))

            if indexStatus == "?" {
                untracked.append(path)
            } else {
                if indexStatus != " " {
                    staged.append(GitFileChange(status: indexStatus, path: path))
                }
                if workTreeStatus != " " {
                    unstaged.append(GitFileChange(status: workTreeStatus, path: path))
                }
            }
        }

        return GitStatusResult(staged: staged, unstaged: unstaged, untracked: untracked)
    }
}

// MARK: - Output Types

/// A parsed git commit
public struct GitCommit: Sendable, Equatable {
    public let hash: String
    public let authorName: String
    public let authorEmail: String
    public let subject: String
    public let date: Date

    public init(hash: String, authorName: String, authorEmail: String, subject: String, date: Date) {
        self.hash = hash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.subject = subject
        self.date = date
    }
}

/// Result of git status --porcelain
public struct GitStatusResult: Sendable, Equatable {
    public let staged: [GitFileChange]
    public let unstaged: [GitFileChange]
    public let untracked: [String]

    public var hasChanges: Bool {
        !staged.isEmpty || !unstaged.isEmpty || !untracked.isEmpty
    }

    public var isClean: Bool {
        !hasChanges
    }

    public init(staged: [GitFileChange], unstaged: [GitFileChange], untracked: [String]) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
    }
}

/// A file change from git status
public struct GitFileChange: Sendable, Equatable {
    public let status: Character
    public let path: String

    public var statusDescription: String {
        switch status {
        case "M": return "modified"
        case "A": return "added"
        case "D": return "deleted"
        case "R": return "renamed"
        case "C": return "copied"
        case "U": return "unmerged"
        default: return "unknown"
        }
    }

    public init(status: Character, path: String) {
        self.status = status
        self.path = path
    }
}
