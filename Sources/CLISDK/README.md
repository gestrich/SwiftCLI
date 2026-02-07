# CLIKit

A Swift framework for building type-safe command-line tool wrappers using macros.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIClient                            │
│  - Executes commands                                        │
│  - Returns ExecutionResult or typed Output                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        CLIProgram                           │
│  - Represents an executable (e.g., Git, Docker)             │
│  - programName: String                                      │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │                    CLICommand                       │   │
│   │  - Nested subcommand (e.g., Git.Merge)              │   │
│   │  - commandLine: [String]                            │   │
│   │  - Optional: parse() for structured output          │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Core Types

### CLIProgram

Represents an executable (git, docker, aws). Contains nested command types.

```swift
@CLIProgram
struct Git {
    // commands nested here
}
```

### CLICommand

Represents a subcommand with its arguments. Uses macros for declarative definition.

```swift
@CLICommand
struct Merge {
    @Flag var noFastForward: Bool = false
    @Option("-m") var message: String?
    @Positional var branch: String
}
```

### CLIArgument

The building blocks of commands:

| Type | Description | Example |
|------|-------------|---------|
| `CLIFlag` | Boolean flag | `--force`, `-f` |
| `CLIOption` | Option with value | `--message "text"` |
| `CLIPrefixOption` | Joined prefix + value | `-9`, `-TERM` |
| `CLIPositional` | Positional argument | `feature-branch` |

### CLIClient

Executes commands and returns results. Each consumer should create their own instance to ensure output streams are isolated.

### CLIOutputParser

Protocol for reusable parsers (StringParser, LinesParser, JSONOutputParser).

## Macro-Based API

### Command Definition

```swift
@CLIProgram
struct Git {
    @CLICommand
    struct Merge {
        @Flag var noFastForward: Bool = false          // --no-fast-forward
        @Option("-m") var message: String?             // -m only
        @Positional var branch: String
    }

    @CLICommand
    struct Log {
        @Option var format: String = "%H|%an|%s"       // --format
        @Option("-n") var maxCount: String?            // -n only

        // Output type inferred from return type
        func parse(_ output: String) throws -> [GitCommit] {
            // parse output into structs
        }
    }
}
```

### Name Inference

Names are inferred from struct/property names (kebab-cased):

| Declaration | Inferred Name |
|-------------|---------------|
| `@CLIProgram struct Git` | `git` |
| `@CLICommand struct UpdateIndex` | `update-index` |
| `@Flag var noFastForward` | `--no-fast-forward` |

Override with explicit names:

```swift
@CLIProgram("custom-name")
@CLICommand("custom-cmd")
@Flag("--noFF") var noFF  // --noFF (explicit, no kebab conversion)
```

### Flags and Options

```swift
// Flags (boolean)
@Flag var force: Bool = false                      // --force (inferred)
@Flag("-f") var force: Bool = false                // -f only
@Flag("--force", "-f") var force: Bool = false     // --force and -f

// Options (with value)
@Option var output: String?                        // --output (inferred)
@Option("-o") var output: String?                  // -o only
@Option("--output", "-o") var output: String?      // --output and -o

// Prefix Options (joined prefix + value, for old-style Unix options)
@PrefixOption("-") var signal: String?             // -9, -TERM (joined)

// Positional (ordered by declaration)
@Positional var source: String                     // first
@Positional var destination: String                // second
```

### Prefix Options

Some Unix commands use old-style options where the prefix and value are combined into a single argument:

```swift
@CLIProgram
struct Kill {
    @PrefixOption("-") var signal: String?    // produces "-9" not "-" "9"
    @Positional var pid: String
}

Kill(signal: "9", pid: "12345").commandLine
// → ["kill", "-9", "12345"]
```

Common use cases:
- `kill -9 PID` (signal)
- `nice -10 command` (priority)
- `head -20 file` (line count)
- `renice -5 PID` (priority)

This differs from `@Option` which produces separate arguments:
```swift
@Option("-n") var count: String?   // produces ["-n", "20"]
@PrefixOption("-") var count: String?  // produces ["-20"]
```

## Usage

### Basic Execution

```swift
let service = CLIClient()

// Run a command, get raw result
let result = try await service.execute(
    command: "git",
    arguments: ["status", "--porcelain"]
)
print(result.stdout)

// Run a typed command
let merge = Git.Merge(noFastForward: true, message: "Merge feature", branch: "feature")
print(merge.commandLine)  // ["git", "merge", "--no-fast-forward", "-m", "Merge feature", "feature"]
```

### Structured Output

By default, `execute()` returns a trimmed `String`. Use a parser for structured output:

```swift
// Default: returns trimmed String
let output = try await service.execute(Git.Diff())

// With parser: returns [GitCommit]
let commits = try await service.execute(Git.Log(maxCount: "10"), parser: GitLogParser())

for commit in commits {
    print("\(commit.hash.prefix(7)) - \(commit.subject)")
}

// With parser: returns GitStatusResult
let status = try await service.execute(Git.StatusPorcelain(), parser: GitStatusParser())
```

### Built-in Parsers

| Parser | Output | Description |
|--------|--------|-------------|
| `StringParser` | `String` | Trimmed string (default) |
| `LinesParser` | `[String]` | Split by newlines |
| `JSONOutputParser<T>` | `T` | Decoded JSON |

## File Structure

```
CLIKit/
├── Macros.swift              # @CLIProgram, @CLICommand, @Flag, etc.
├── CLIProgram.swift          # CLIProgram protocol
├── CLICommand.swift          # CLICommand protocol
├── CLIArgument.swift         # CLIFlag, CLIOption, CLIPositional
├── CLIClient.swift           # Command execution client
├── CLIClientError.swift      # Error types
├── CLIOutputParser.swift     # Parser protocol + built-ins
├── ExecutionResult.swift     # Execution result types
├── StringUtils.swift         # Kebab-case conversion
└── Examples/
    └── Git.swift             # Example Git commands
```
