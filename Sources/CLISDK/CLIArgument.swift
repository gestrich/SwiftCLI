/// Represents a single CLI argument component
public enum CLIArgument: Equatable, Sendable {
    case flag(CLIFlag)
    case option(CLIOption)
    case prefixOption(CLIPrefixOption)
    case positional(CLIPositional)

    /// Convert to command-line string components
    public var components: [String] {
        switch self {
        case .flag(let flag):
            return flag.components
        case .option(let option):
            return option.components
        case .prefixOption(let prefixOption):
            return prefixOption.components
        case .positional(let positional):
            return positional.components
        }
    }
}

/// A boolean flag (e.g., --force, -f)
public struct CLIFlag: Equatable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var components: [String] {
        [name]
    }
}

/// An option with a value (e.g., --message "text", -m "text")
public struct CLIOption: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(_ name: String, value: String) {
        self.name = name
        self.value = value
    }

    public var components: [String] {
        [name, value]
    }
}

/// A prefix option where prefix and value are joined (e.g., -9, -TERM for kill signals)
/// Used for old-style Unix options like: kill -9, nice -10, head -20
public struct CLIPrefixOption: Equatable, Sendable {
    public let prefix: String
    public let value: String

    public init(_ prefix: String, value: String) {
        self.prefix = prefix
        self.value = value
    }

    public var components: [String] {
        [prefix + value]
    }
}

/// A positional argument (e.g., branch name, file path)
public struct CLIPositional: Equatable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var components: [String] {
        [value]
    }
}
