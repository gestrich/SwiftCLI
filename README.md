# SwiftCLI

A Swift framework for building type-safe command-line tool wrappers using macros.

## Overview

SwiftCLI provides a macro-based DSL for defining CLI programs and their commands as Swift types. Commands are built declaratively with `@CLIProgram`, `@CLICommand`, `@Flag`, `@Option`, and `@Positional` macros, and executed asynchronously via `CLIClient`.

## Adding as a Dependency

```swift
dependencies: [
    .package(path: "../SwiftCLI"),  // local
    // or
    .package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "CLISDK", package: "SwiftCLI"),
        ]
    ),
]
```

## Usage

### Defining Commands

```swift
import CLISDK

@CLIProgram
struct Git {
    @CLICommand
    struct Merge {
        @Flag var noFastForward: Bool = false     // --no-fast-forward
        @Option("-m") var message: String?         // -m "text"
        @Positional var branch: String
    }

    @CLICommand
    struct Log {
        @Option var format: String = "%H|%an|%s"  // --format
        @Option("-n") var maxCount: String?        // -n 10
    }
}
```

### Executing Commands

```swift
let client = CLIClient()

// Typed command execution
let output = try await client.execute(Git.Merge(branch: "feature"))

// With a parser for structured output
let commits = try await client.execute(
    Git.Log(maxCount: "10"),
    parser: GitLogParser()
)

// Raw command execution
let result = try await client.execute(
    command: "git",
    arguments: ["status", "--porcelain"]
)
print(result.stdout)
```

### Argument Types

| Macro | Description | Example Output |
|-------|-------------|----------------|
| `@Flag` | Boolean flag | `--force`, `-f` |
| `@Option` | Option with value | `--message "text"` |
| `@PrefixOption` | Joined prefix + value | `-9`, `-TERM` |
| `@Positional` | Positional argument | `feature-branch` |

### Name Inference

Names are inferred from property names using kebab-case conversion:

| Declaration | Inferred Name |
|-------------|---------------|
| `@CLIProgram struct Git` | `git` |
| `@CLICommand struct UpdateIndex` | `update-index` |
| `@Flag var noFastForward` | `--no-fast-forward` |

Override with explicit names: `@Flag("--noFF")`, `@CLIProgram("custom-name")`.

## Architecture

The package contains two targets:

- **CLISDK** — The main library with `CLIClient`, protocols (`CLIProgram`, `CLICommand`), argument types, output parsers, and standard command definitions (Git, Curl, Docker, etc.).
- **CLIMacrosSDK** — Swift macro implementations that power the `@CLIProgram`, `@CLICommand`, `@Flag`, `@Option`, `@PrefixOption`, and `@Positional` macros.

See [Sources/CLISDK/README.md](Sources/CLISDK/README.md) for detailed architecture documentation.
