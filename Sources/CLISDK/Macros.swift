/// Marks a struct as a CLI program (executable)
/// The program name is inferred from the struct name (lowercased, kebab-cased)
/// or can be explicitly provided.
///
/// If the struct contains `@Flag`, `@Option`, or `@Positional` properties,
/// it becomes both a program AND a command (for simple CLIs without subcommands).
///
/// Example (program with subcommands):
/// ```swift
/// @CLIProgram
/// struct Git {
///     @CLICommand
///     struct Merge { ... }
/// }
/// ```
///
/// Example (simple program without subcommands):
/// ```swift
/// @CLIProgram
/// struct Lsof {
///     @Option("-i") var port: String
///     @Flag("-t") var pidOnly: Bool = false
/// }
/// // Usage: Lsof(port: ":8080")
/// // commandLine: ["lsof", "-i", ":8080"]
/// ```
@attached(extension, conformances: CLIProgram, CLICommand, names: named(programName), named(commandPath), named(arguments), named(Program))
@attached(member, names: named(init))
public macro CLIProgram(_ name: String? = nil) = #externalMacro(module: "CLIMacrosSDK", type: "CLIProgramMacro")

/// Marks a struct as a CLI command (subcommand)
/// Must be nested inside a @CLIProgram struct.
/// The command name is inferred from the struct name (lowercased, kebab-cased)
/// or can be explicitly provided.
///
/// Example:
/// ```swift
/// @CLIProgram
/// struct Git {
///     @CLICommand
///     struct Merge {
///         @Flag var noFastForward: Bool = false
///         @Positional var branch: String
///     }
/// }
/// ```
@attached(extension, conformances: CLICommand, names: named(commandPath), named(arguments), named(Program))
@attached(member, names: named(init))
public macro CLICommand(_ name: String? = nil) = #externalMacro(module: "CLIMacrosSDK", type: "CLICommandMacro")

/// Marks a property as a boolean flag
///
/// - No arguments: infers `--kebab-case` from property name
/// - One argument: uses that exact string (e.g., "-f" or "--force")
/// - Two arguments: uses both forms (e.g., "--force", "-f")
///
/// Example:
/// ```swift
/// @Flag var force: Bool = false                    // --force (inferred)
/// @Flag("-f") var force: Bool = false              // -f only
/// @Flag("--force", "-f") var force: Bool = false   // --force and -f
/// @Flag("-version") var version: Bool = false      // -version (java style)
/// ```
@attached(peer)
public macro Flag(_ names: String...) = #externalMacro(module: "CLIMacrosSDK", type: "FlagMacro")

/// Marks a property as an option with a value
///
/// - No arguments: infers `--kebab-case` from property name
/// - One argument: uses that exact string (e.g., "-m" or "--message")
/// - Two arguments: uses both forms (e.g., "--message", "-m")
///
/// Example:
/// ```swift
/// @Option var output: String?                        // --output (inferred)
/// @Option("-o") var output: String?                  // -o only
/// @Option("--output", "-o") var output: String?      // --output and -o
/// @Option("-m") var message: String?                 // -m only
/// ```
@attached(peer)
public macro Option(_ names: String...) = #externalMacro(module: "CLIMacrosSDK", type: "OptionMacro")

/// Marks a property as a prefix option where prefix and value are joined
///
/// Used for old-style Unix options where the prefix and value form a single argument:
/// - `kill -9` (signal)
/// - `nice -10` (priority)
/// - `head -20` (line count)
///
/// Example:
/// ```swift
/// @PrefixOption("-") var signal: String?  // Produces "-9" not "-" "9"
/// ```
@attached(peer)
public macro PrefixOption(_ prefix: String) = #externalMacro(module: "CLIMacrosSDK", type: "PrefixOptionMacro")

/// Marks a property as a positional argument
/// Positionals are ordered by declaration order
///
/// Example:
/// ```swift
/// @Positional var source: String       // first positional
/// @Positional var destination: String  // second positional
/// ```
@attached(peer)
public macro Positional() = #externalMacro(module: "CLIMacrosSDK", type: "PositionalMacro")
