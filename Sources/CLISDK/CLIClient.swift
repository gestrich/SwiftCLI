import Foundation
import Synchronization

/// A service for executing command-line operations with async/await support
public actor CLIClient {
    /// Global output stream - broadcasts all CLI output to any subscriber.
    private let globalOutput = CLIOutputStream()

    /// Create a new stream subscription for CLI output.
    /// Each caller gets an independent stream receiving all future output.
    public func outputStream() async -> AsyncStream<StreamOutput> {
        await globalOutput.makeStream()
    }

    /// Pre-computed environment with common paths
    private let defaultEnvironment: [String: String]

    /// Default working directory for commands (nil uses current directory)
    private var defaultWorkingDirectory: String?

    /// Cache for executable paths
    private var executableCache: [String: String] = [:]

    public init(defaultWorkingDirectory: String? = nil) {
        self.defaultWorkingDirectory = defaultWorkingDirectory

        // Pre-compute environment with common tool paths
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        var brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

        // Add nvm node bin path if nvm is installed
        if let nvmNodeBin = Self.findNvmNodeBinPath() {
            brewPaths.insert(nvmNodeBin, at: 0)
        }

        let pathComponents = currentPath.components(separatedBy: ":")

        // Add paths if they're not already in PATH
        var updatedPathComponents = pathComponents
        for brewPath in brewPaths {
            if !pathComponents.contains(brewPath) {
                updatedPathComponents.insert(brewPath, at: 0)
            }
        }

        environment["PATH"] = updatedPathComponents.joined(separator: ":")
        self.defaultEnvironment = environment
    }

    /// Find the nvm node bin path (for cdk, npm, etc.)
    private static func findNvmNodeBinPath() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmVersionsPath = "\(homeDir)/.nvm/versions/node"

        // Check if nvm versions directory exists
        guard FileManager.default.fileExists(atPath: nvmVersionsPath) else {
            return nil
        }

        // First, try to read the default alias
        let defaultAliasPath = "\(homeDir)/.nvm/alias/default"
        if let defaultVersion = try? String(contentsOfFile: defaultAliasPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            // defaultVersion might be a version like "22" or "lts/iron" or "v22.17.0"
            // Try to find a matching version directory
            if let matchingVersion = findMatchingNodeVersion(nvmVersionsPath: nvmVersionsPath, alias: defaultVersion) {
                let binPath = "\(nvmVersionsPath)/\(matchingVersion)/bin"
                if FileManager.default.fileExists(atPath: binPath) {
                    return binPath
                }
            }
        }

        // Fallback: find the latest installed version
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath) {
            let sortedVersions = versions.filter { $0.hasPrefix("v") }.sorted { v1, v2 in
                v1.compare(v2, options: .numeric) == .orderedDescending
            }
            if let latestVersion = sortedVersions.first {
                let binPath = "\(nvmVersionsPath)/\(latestVersion)/bin"
                if FileManager.default.fileExists(atPath: binPath) {
                    return binPath
                }
            }
        }

        return nil
    }

    /// Find a node version directory matching an alias
    private static func findMatchingNodeVersion(nvmVersionsPath: String, alias: String) -> String? {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath) else {
            return nil
        }

        // If alias is already a full version like "v22.17.0"
        if versions.contains(alias) {
            return alias
        }

        // If alias is a major version like "22", find matching "v22.x.x"
        let versionPrefix = alias.hasPrefix("v") ? alias : "v\(alias)"
        let matching = versions.filter { $0.hasPrefix(versionPrefix) }.sorted { v1, v2 in
            v1.compare(v2, options: .numeric) == .orderedDescending
        }

        return matching.first
    }

    /// Set the default working directory for all commands
    public func setDefaultWorkingDirectory(_ directory: String?) {
        self.defaultWorkingDirectory = directory
    }

    /// Execute a command with full control over the execution environment
    /// - Parameters:
    ///   - command: The command to execute (can be a path or command name)
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables (merged with defaults)
    ///   - timeout: Optional timeout in seconds
    ///   - printCommand: If true, prints the formatted command before execution
    ///   - inheritIO: If true, inherits stdin/stdout/stderr from parent process (for interactive commands)
    /// - Returns: ExecutionResult containing exit code, stdout, and stderr
    public func execute(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        printCommand: Bool = true,
        inheritIO: Bool = false,
        output: CLIOutputStream? = nil
    ) async throws -> ExecutionResult {
        // Resolve and prepare command - this handles errors and sends to global stream
        let prepared = await prepareCommand(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            output: output
        )

        switch prepared {
        case .success(let info):
            return try await executeProcess(
                command: info.resolvedCommand,
                arguments: arguments,
                workingDirectory: info.effectiveWorkingDirectory,
                environment: info.processEnvironment,
                timeout: timeout,
                startTime: Date(),
                inheritIO: inheritIO,
                commandID: info.commandID,
                output: output
            )
        case .failure(let error):
            throw error
        }
    }

    /// Convenience method for simple command execution
    /// - Parameters:
    ///   - command: Command string (can include arguments)
    ///   - directory: Working directory
    /// - Returns: The stdout output as a string
    public func run(
        _ command: String,
        in directory: String? = nil
    ) async throws -> String {
        let components = command.components(separatedBy: " ")
        guard !components.isEmpty else {
            throw CLIClientError.invalidCommand("Empty command")
        }

        let executable = components[0]
        let arguments = Array(components.dropFirst())

        let result = try await execute(
            command: executable,
            arguments: arguments,
            workingDirectory: directory
        )

        if result.exitCode != 0 {
            throw CLIClientError.executionFailed(
                command: command,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return result.stdout
    }

    /// Execute a command and stream its output
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables
    ///   - printCommand: If true, prints the formatted command before execution
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: AsyncStream of output lines
    public func stream(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) -> AsyncStream<StreamOutput> {
        AsyncStream { continuation in
            Task {
                // Prepare command - handles resolution, environment merging, and error reporting
                let prepared = await self.prepareCommand(
                    command: command,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    printCommand: printCommand,
                    continuation: continuation,
                    output: output
                )

                guard case .success(let info) = prepared else {
                    // prepareCommand already sent error to continuation and finished it
                    return
                }

                do {
                    try self.streamProcess(
                        command: info.resolvedCommand,
                        arguments: arguments,
                        workingDirectory: info.effectiveWorkingDirectory,
                        environment: info.processEnvironment,
                        commandID: info.commandID,
                        continuation: continuation,
                        output: output
                    )
                } catch {
                    // Error during process execution (not resolution)
                    let errorOutput = StreamOutput.error(commandID: info.commandID, error: error)
                    continuation.yield(errorOutput)
                    continuation.finish()
                    await self.globalOutput.send(errorOutput)
                    await output?.send(errorOutput)
                }
            }
        }
    }

    /// Execute a typed CLI command and stream its output
    /// - Parameters:
    ///   - command: The typed CLI command to execute
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables
    ///   - printCommand: If true, prints the formatted command before execution
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: AsyncStream of output lines
    public func stream<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) -> AsyncStream<StreamOutput> {
        let commandLine = command.commandLine
        guard let programName = commandLine.first else {
            let errorID = CommandID()
            return AsyncStream { (continuation: AsyncStream<StreamOutput>.Continuation) in
                continuation.yield(.error(commandID: errorID, error: CLIClientError.invalidCommand("Empty command line")))
                continuation.finish()
            }
        }
        let arguments = Array(commandLine.dropFirst())
        return stream(
            command: programName,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            output: output
        )
    }

    // MARK: - Private Methods

    private func formatCommand(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> String {
        var parts: [String] = []

        // Add environment variables
        if let environment {
            for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
                parts.append("\(key)='\(value)'")
            }
        }

        // Add command
        parts.append(command)

        // Add arguments (properly quoted)
        for arg in arguments {
            if arg.contains(" ") || arg.contains("'") || arg.contains("\"") {
                // Escape single quotes and wrap in single quotes
                let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("'\(escaped)'")
            } else {
                parts.append(arg)
            }
        }

        return parts.joined(separator: " ")
    }

    /// Information needed to execute a prepared command
    private struct PreparedCommand {
        let commandID: CommandID
        let resolvedCommand: String
        let effectiveWorkingDirectory: String?
        let processEnvironment: [String: String]
    }

    /// Prepare a command for execution: resolve path, merge environment, send to global stream
    /// This is the single place that handles command resolution errors for both execute and stream
    private func prepareCommand(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        printCommand: Bool,
        continuation: AsyncStream<StreamOutput>.Continuation? = nil,
        output: CLIOutputStream? = nil
    ) async -> Result<PreparedCommand, Error> {
        let commandID = CommandID()

        // Use provided working directory or fall back to default
        let effectiveWorkingDirectory = workingDirectory ?? defaultWorkingDirectory

        // Resolve command path
        let resolvedCommand: String
        do {
            resolvedCommand = try resolveCommand(command, workingDirectory: effectiveWorkingDirectory)
        } catch {
            // Send command and error to streams so UI shows what failed
            let commandLine = "→ \(command) \(arguments.joined(separator: " "))\n"
            let commandOutput = StreamOutput.command(id: commandID, text: commandLine)
            let errorOutput = StreamOutput.error(commandID: commandID, error: error)

            await globalOutput.send(commandOutput)
            await output?.send(commandOutput)
            await output?.send(errorOutput)

            continuation?.yield(commandOutput)
            continuation?.yield(errorOutput)
            continuation?.finish()

            if printCommand {
                print(commandLine, terminator: "")
                print("❌ Error: \(error.localizedDescription)")
            }
            return .failure(error)
        }

        // Merge environments
        var processEnvironment = defaultEnvironment
        if let customEnvironment = environment {
            for (key, value) in customEnvironment {
                processEnvironment[key] = value
            }
        }

        // Send command to streams
        let formattedCommand = formatCommand(
            command: resolvedCommand,
            arguments: arguments,
            environment: environment
        )
        let commandLine = "→ \(formattedCommand)\n"
        let commandOutput = StreamOutput.command(id: commandID, text: commandLine)

        await globalOutput.send(commandOutput)
        await output?.send(commandOutput)
        continuation?.yield(commandOutput)

        if printCommand {
            print(commandLine, terminator: "")
        }

        return .success(PreparedCommand(
            commandID: commandID,
            resolvedCommand: resolvedCommand,
            effectiveWorkingDirectory: effectiveWorkingDirectory,
            processEnvironment: processEnvironment
        ))
    }

    private func resolveCommand(_ command: String, workingDirectory: String? = nil) throws -> String {
        // If it's already an absolute path, use it
        if command.starts(with: "/") {
            guard FileManager.default.fileExists(atPath: command) else {
                throw CLIClientError.commandNotFound(command)
            }
            return command
        }

        // If it's a relative path (starts with ./ or ../), resolve relative to working directory
        if command.starts(with: "./") || command.starts(with: "../") {
            let baseDir = workingDirectory ?? FileManager.default.currentDirectoryPath
            let resolvedPath = (baseDir as NSString).appendingPathComponent(command)
            let standardizedPath = (resolvedPath as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardizedPath) else {
                throw CLIClientError.commandNotFound(command)
            }
            return standardizedPath
        }

        // Check cache
        if let cached = executableCache[command] {
            return cached
        }

        // Common direct paths
        let commonPaths = [
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                executableCache[command] = path
                return path
            }
        }

        // Fall back to using 'which' command
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = [command]
        which.environment = defaultEnvironment

        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()

        try which.run()
        which.waitUntilExit()

        if which.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                executableCache[command] = path
                return path
            }
        }

        throw CLIClientError.commandNotFound(command)
    }

    private func executeProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        startTime: Date,
        inheritIO: Bool,
        commandID: CommandID,
        output: CLIOutputStream? = nil
    ) async throws -> ExecutionResult {
        return try self.runProcess(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            inheritIO: inheritIO,
            commandID: commandID,
            commandContinuation: nil,
            output: output
        )
    }

    /// Unified process execution - always streams output in real-time and broadcasts to global stream
    /// - Parameters:
    ///   - command: Executable path
    ///   - arguments: Command arguments
    ///   - workingDirectory: Working directory
    ///   - environment: Environment variables
    ///   - timeout: Optional timeout
    ///   - inheritIO: If true, inherit stdin/stdout/stderr (no capture)
    ///   - commandID: Unique ID for this command execution
    ///   - commandContinuation: Optional per-command stream continuation
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: ExecutionResult with accumulated stdout/stderr
    private func runProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        inheritIO: Bool,
        commandID: CommandID,
        commandContinuation: AsyncStream<StreamOutput>.Continuation?,
        output: CLIOutputStream? = nil
    ) throws -> ExecutionResult {
        let startTime = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Thread-safe accumulators for ExecutionResult
        let stdoutAccumulator = OutputAccumulator()
        let stderrAccumulator = OutputAccumulator()

        // Capture streams for use in closures
        let globalOutputStream = self.globalOutput
        let clientOutputStream = output

        let outputPipe: Pipe?
        let errorPipe: Pipe?

        if inheritIO {
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            outputPipe = nil
            errorPipe = nil
        } else {
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outputPipe = outPipe
            errorPipe = errPipe

            // Real-time output handling (always)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stdoutAccumulator.append(text)
                    print(text, terminator: "")

                    let streamOutput = StreamOutput.stdout(commandID: commandID, text: text)

                    // Yield to per-command stream (if provided)
                    commandContinuation?.yield(streamOutput)

                    // Broadcast to global stream
                    Task {
                        await globalOutputStream.send(streamOutput)
                    }

                    // Send to client's stream (if provided)
                    if let clientOutput = clientOutputStream {
                        Task {
                            await clientOutput.send(streamOutput)
                        }
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stderrAccumulator.append(text)
                    print(text, terminator: "")

                    let streamOutput = StreamOutput.stderr(commandID: commandID, text: text)

                    commandContinuation?.yield(streamOutput)

                    // Broadcast to global stream
                    Task {
                        await globalOutputStream.send(streamOutput)
                    }

                    // Send to client's stream (if provided)
                    if let clientOutput = clientOutputStream {
                        Task {
                            await clientOutput.send(streamOutput)
                        }
                    }
                }
            }
        }

        // Timeout handling
        var timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        timeoutTask?.cancel()

        // Clean up handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startTime)

        // Ensure output ends with newline for clean separation between commands
        let stdout = stdoutAccumulator.value
        if !stdout.isEmpty && !stdout.hasSuffix("\n") {
            let newline = "\n"
            print(newline, terminator: "")
            let newlineOutput = StreamOutput.stdout(commandID: commandID, text: newline)
            commandContinuation?.yield(newlineOutput)
            Task {
                await globalOutputStream.send(newlineOutput)
            }
            if let clientOutput = clientOutputStream {
                Task {
                    await clientOutput.send(newlineOutput)
                }
            }
        }

        // Yield exit to streams
        let exitOutput = StreamOutput.exit(commandID: commandID, code: exitCode)
        commandContinuation?.yield(exitOutput)
        commandContinuation?.finish()

        Task {
            await self.globalOutput.send(exitOutput)
        }
        if let clientOutput = clientOutputStream {
            Task {
                await clientOutput.send(exitOutput)
            }
        }

        // Check timeout
        if let timeout, duration >= timeout && exitCode != 0 {
            throw CLIClientError.timeout(
                command: "\(command) \(arguments.joined(separator: " "))",
                duration: timeout
            )
        }

        return ExecutionResult(
            exitCode: exitCode,
            stdout: stdoutAccumulator.value,
            stderr: stderrAccumulator.value,
            duration: duration
        )
    }

    // MARK: - Typed Command Execution

    /// Execute a typed command and return both the parsed output and execution result.
    /// This is the lowest-level typed command API - use when you need both the parsed result
    /// and execution metadata (exit code, stderr, duration).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - parser: Parser to transform stdout into the desired type
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: Tuple of (parsed output, execution result). Parse only attempted if command succeeds.
    /// - Throws: CLIClientError if command not found or parsing fails
    public func executeWithResult<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) async throws -> (P.Output?, ExecutionResult) {
        let result = try await execute(
            command: C.Program.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            output: output
        )

        if result.isSuccess {
            let parsed = try parser.parse(result.stdout)
            return (parsed, result)
        } else {
            return (nil, result)
        }
    }

    /// Execute a typed command and return just the ExecutionResult.
    /// Use when you only need to check exit codes or inspect stdout/stderr directly.
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    ///   - inheritIO: If true, inherits stdin/stdout/stderr from parent process (for interactive commands)
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: ExecutionResult containing exit code, stdout, stderr, and duration
    public func executeForResult<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        inheritIO: Bool = false,
        output: CLIOutputStream? = nil
    ) async throws -> ExecutionResult {
        try await execute(
            command: C.Program.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            inheritIO: inheritIO,
            output: output
        )
    }

    /// Execute a typed command and return parsed output.
    /// Throws if the command fails (non-zero exit code).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - parser: Parser to transform stdout into the desired type
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: Parsed output of type `P.Output`
    /// - Throws: CLIClientError if command fails or parsing fails
    public func execute<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) async throws -> P.Output {
        let (parsed, result) = try await executeWithResult(
            command,
            parser: parser,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            output: output
        )

        guard let parsed else {
            throw CLIClientError.executionFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return parsed
    }

    /// Execute a typed command and return trimmed string output.
    /// Throws if the command fails (non-zero exit code).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Returns: Trimmed stdout string
    public func execute<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) async throws -> String {
        try await execute(
            command,
            parser: StringParser(),
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            output: output
        )
    }

    // MARK: - Private Streaming

    private func streamProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        commandID: CommandID,
        continuation: AsyncStream<StreamOutput>.Continuation,
        output: CLIOutputStream? = nil
    ) throws {
        // Use unified runProcess - it handles continuation and global broadcast
        _ = try runProcess(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: nil,
            inheritIO: false,
            commandID: commandID,
            commandContinuation: continuation,
            output: output
        )
    }
}

/// Thread-safe string accumulator for capturing output in concurrent contexts
private final class OutputAccumulator: Sendable {
    private let storage = Mutex("")

    var value: String {
        storage.withLock { $0 }
    }

    func append(_ text: String) {
        storage.withLock { $0 += text }
    }
}
