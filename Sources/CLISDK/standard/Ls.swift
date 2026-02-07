import Foundation

/// ls CLI program definition using macro-based API
@CLIProgram
public struct Ls {
    /// List directory contents with details
    @CLICommand("") // Empty command name since ls has no subcommand
    public struct List {
        // MARK: - Display Format

        /// Use long listing format (-l)
        @Flag("-l") public var longFormat: Bool = false

        /// Force multi-column output (-C)
        @Flag("-C") public var multiColumn: Bool = false

        /// Stream output format, comma separated (-m)
        @Flag("-m") public var streamFormat: Bool = false

        /// List one file per line (-1)
        @Flag("-1") public var onePerLine: Bool = false

        // MARK: - File Selection

        /// Include hidden files (names beginning with .) (-a)
        @Flag("-a") public var all: Bool = false

        /// Include hidden files except . and .. (-A)
        @Flag("-A") public var almostAll: Bool = false

        /// List directories themselves, not their contents (-d)
        @Flag("-d") public var directory: Bool = false

        // MARK: - Sorting

        /// Sort by size, largest first (-S)
        @Flag("-S") public var sortBySize: Bool = false

        /// Sort by time modified, most recent first (-t)
        @Flag("-t") public var sortByTime: Bool = false

        /// Reverse sort order (-r)
        @Flag("-r") public var reverse: Bool = false

        /// Do not sort (-f)
        @Flag("-f") public var unsorted: Bool = false

        // MARK: - Size Display

        /// Human-readable sizes (e.g., 1K, 234M) (-h)
        @Flag("-h") public var humanReadable: Bool = false

        /// Display size in blocks (-s)
        @Flag("-s") public var showBlocks: Bool = false

        // MARK: - Additional Info

        /// Print inode number (-i)
        @Flag("-i") public var showInode: Bool = false

        /// Append indicator (/, *, @, etc.) to entries (-F)
        @Flag("-F") public var classify: Bool = false

        /// Append / to directories (-p)
        @Flag("-p") public var slashDirs: Bool = false

        /// Recursively list subdirectories (-R)
        @Flag("-R") public var recursive: Bool = false

        /// Show complete time information (-T)
        @Flag("-T") public var fullTime: Bool = false

        // MARK: - Positional

        /// Directory or file to list
        @Positional public var path: String?
    }
}

// MARK: - Parser

/// Parser for ls -l output
public struct LsParser: CLIOutputParser {
    public init() {}

    public func parse(_ output: String) throws -> [FileEntry] {
        var entries: [FileEntry] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Skip empty lines and total line
            guard !line.isEmpty, !line.hasPrefix("total ") else { continue }

            // Parse ls -l format: permissions links owner group size date name
            // Example: -rw-r--r--  1 user  staff  1234 Nov 29 10:30 file.txt
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let permissions = String(parts[0])
            let links = Int(parts[1]) ?? 1
            let owner = String(parts[2])
            let group = String(parts[3])
            let size = Int(parts[4]) ?? 0
            // Date parts: month day time/year (parts 5, 6, 7)
            let dateString = "\(parts[5]) \(parts[6]) \(parts[7])"
            // Name is everything after the date (handles names with spaces)
            let nameStartIndex = parts[0...7].reduce(0) { $0 + $1.count + 1 }
            let name = String(line.dropFirst(nameStartIndex))

            let isDirectory = permissions.hasPrefix("d")
            let isSymlink = permissions.hasPrefix("l")
            let isExecutable = permissions.contains("x")

            entries.append(FileEntry(
                name: name,
                permissions: permissions,
                links: links,
                owner: owner,
                group: group,
                size: size,
                dateString: dateString,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                isExecutable: isExecutable
            ))
        }

        return entries
    }
}

// MARK: - Output Types

/// A file entry from ls -l output
public struct FileEntry: Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let permissions: String
    public let links: Int
    public let owner: String
    public let group: String
    public let size: Int
    public let dateString: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isExecutable: Bool

    /// Icon for the file type
    public var icon: String {
        if isDirectory {
            return "📁"
        } else if isSymlink {
            return "🔗"
        } else if isExecutable {
            return "⚙️"
        } else if name.hasSuffix(".swift") {
            return "🐦"
        } else if name.hasSuffix(".md") {
            return "📝"
        } else if name.hasSuffix(".json") || name.hasSuffix(".yml") || name.hasSuffix(".yaml") {
            return "📋"
        } else {
            return "📄"
        }
    }

    /// Human-readable size
    public var humanSize: String {
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024)
        } else if size < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
        }
    }

    public init(
        name: String,
        permissions: String,
        links: Int,
        owner: String,
        group: String,
        size: Int,
        dateString: String,
        isDirectory: Bool,
        isSymlink: Bool,
        isExecutable: Bool
    ) {
        self.name = name
        self.permissions = permissions
        self.links = links
        self.owner = owner
        self.group = group
        self.size = size
        self.dateString = dateString
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isExecutable = isExecutable
    }
}
