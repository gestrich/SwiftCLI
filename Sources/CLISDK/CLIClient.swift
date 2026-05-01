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

    /// Whether to print stdout/stderr to the console in real-time
    private let printOutput: Bool

    /// Cache for executable paths
    private var executableCache: [String: String] = [:]

    public init(defaultWorkingDirectory: String? = nil, printOutput: Bool = true) {
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.printOutput = printOutput

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
        stdin: Data? = nil,
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
                stdin: stdin,
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
        stdin: Data? = nil,
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
                    try await self.streamProcess(
                        command: info.resolvedCommand,
                        arguments: arguments,
                        workingDirectory: info.effectiveWorkingDirectory,
                        environment: info.processEnvironment,
                        stdin: stdin,
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

            if printCommand && printOutput {
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

        if printCommand && printOutput {
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
        stdin: Data? = nil,
        commandID: CommandID,
        output: CLIOutputStream? = nil
    ) async throws -> ExecutionResult {
        let cancellationHandle = CancellationHandle()
        return try await withTaskCancellationHandler {
            try await self.runProcess(
                command: command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                timeout: timeout,
                inheritIO: inheritIO,
                stdin: stdin,
                commandID: commandID,
                commandContinuation: nil,
                cancellationHandle: cancellationHandle,
                output: output
            )
        } onCancel: {
            cancellationHandle.cancel()
        }
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
        stdin: Data? = nil,
        commandID: CommandID,
        commandContinuation: AsyncStream<StreamOutput>.Continuation?,
        cancellationHandle: CancellationHandle? = nil,
        output: CLIOutputStream? = nil
    ) async throws -> ExecutionResult {
        let startTime = Date()
        let process = Process()
        cancellationHandle?.register(process)
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Thread-safe accumulators for ExecutionResult
        let stdoutAccumulator = OutputAccumulator()
        let stderrAccumulator = OutputAccumulator()

        // Capture values for use in non-isolated closures
        let shouldPrint = self.printOutput
        let globalOutputStream = self.globalOutput
        let clientOutputStream = output

        let outputPipe: Pipe?
        let errorPipe: Pipe?
        var stdinPipe: Pipe?
        var stdoutEOFSignal: AsyncStream<Void>? = nil
        var stderrEOFSignal: AsyncStream<Void>? = nil

        if inheritIO {
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            outputPipe = nil
            errorPipe = nil
        } else {
            // Set up stdin pipe if data was provided
            if stdin != nil {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                stdinPipe = inputPipe
            }
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outputPipe = outPipe
            errorPipe = errPipe

            // EOF signals: handlers self-cancel and signal when the pipe write-end closes.
            let (stdoutEOFStream, stdoutEOFCont) = AsyncStream<Void>.makeStream()
            stdoutEOFSignal = stdoutEOFStream
            let (stderrEOFStream, stderrEOFCont) = AsyncStream<Void>.makeStream()
            stderrEOFSignal = stderrEOFStream

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // EOF — enqueue via Task so we never call into the Swift concurrency
                    // runtime directly from a GCD callback (crashes libdispatch on Linux).
                    Task {
                        stdoutEOFCont.yield()
                        stdoutEOFCont.finish()
                    }
                } else if let text = String(data: data, encoding: .utf8) {
                    stdoutAccumulator.append(text)
                    if shouldPrint {
                        print(text, terminator: "")
                    }

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
                if data.isEmpty {
                    Task {
                        stderrEOFCont.yield()
                        stderrEOFCont.finish()
                    }
                } else if let text = String(data: data, encoding: .utf8) {
                    stderrAccumulator.append(text)
                    if shouldPrint {
                        print(text, terminator: "")
                    }

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

        // Set up termination handler BEFORE run() to avoid a race where the
        // process exits before the handler is installed.
        let terminationSignal = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in
                continuation.yield()
                continuation.finish()
            }
        }

        try process.run()

        // Write stdin data and close the pipe after the process starts
        if let stdinData = stdin, let inputPipe = stdinPipe {
            inputPipe.fileHandleForWriting.write(stdinData)
            inputPipe.fileHandleForWriting.closeFile()
        }

        // Wait for process to exit without blocking a cooperative thread.
        for await _ in terminationSignal { break }

        timeoutTask?.cancel()

        // Wait for readabilityHandlers to consume all pipe data and signal EOF.
        if let stdoutEOF = stdoutEOFSignal {
            for await _ in stdoutEOF { break }
        }
        if let stderrEOF = stderrEOFSignal {
            for await _ in stderrEOF { break }
        }

        // Cancel handlers from outside — safe on Linux unlike in-handler cancellation.
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startTime)

        // Ensure output ends with newline for clean separation between commands
        let stdout = stdoutAccumulator.value
        if !stdout.isEmpty && !stdout.hasSuffix("\n") {
            let newline = "\n"
            if shouldPrint {
                print(newline, terminator: "")
            }
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

    // MARK: - Line-Buffered Streaming

    /// Stream stdout line-by-line as raw strings.
    /// Returns an `AsyncThrowingStream` that throws `CLIClientError.executionFailed` on non-zero exit.
    public func streamLines(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        stdin: Data? = nil,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<String, Error> {
        streamLines(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            stdin: stdin,
            parser: PassthroughLineParser(),
            output: output
        )
    }

    /// Stream stdout line-by-line, transforming each line with a parser.
    /// Returns an `AsyncThrowingStream` that throws `CLIClientError.executionFailed` on non-zero exit.
    public func streamLines<P: CLILineParser>(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        stdin: Data? = nil,
        parser: P,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<P.Output, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let prepared = await self.prepareCommand(
                    command: command,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    printCommand: printCommand,
                    output: output
                )

                switch prepared {
                case .success(let info):
                    do {
                        try await self.runLineBufferedProcess(
                            command: info.resolvedCommand,
                            arguments: arguments,
                            workingDirectory: info.effectiveWorkingDirectory,
                            environment: info.processEnvironment,
                            stdin: stdin,
                            commandID: info.commandID,
                            parser: parser,
                            continuation: continuation,
                            output: output
                        )
                    } catch {
                        continuation.finish(throwing: error)
                        let errorOutput = StreamOutput.error(commandID: info.commandID, error: error)
                        await self.globalOutput.send(errorOutput)
                        await output?.send(errorOutput)
                    }
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Stream a typed CLI command's stdout line-by-line as raw strings.
    public func streamLines<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        stdin: Data? = nil,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let commandLine = command.commandLine
        guard let programName = commandLine.first else {
            return AsyncThrowingStream { $0.finish(throwing: CLIClientError.invalidCommand("Empty command line")) }
        }
        let arguments = Array(commandLine.dropFirst())
        return streamLines(
            command: programName,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            stdin: stdin,
            output: output
        )
    }

    /// Stream a typed CLI command's stdout line-by-line, transforming each line with a parser.
    public func streamLines<C: CLICommand, P: CLILineParser>(
        _ command: C,
        parser: P,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        stdin: Data? = nil,
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<P.Output, Error> {
        let commandLine = command.commandLine
        guard let programName = commandLine.first else {
            return AsyncThrowingStream { $0.finish(throwing: CLIClientError.invalidCommand("Empty command line")) }
        }
        let arguments = Array(commandLine.dropFirst())
        return streamLines(
            command: programName,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            stdin: stdin,
            parser: parser,
            output: output
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
        stdin: Data? = nil,
        commandID: CommandID,
        continuation: AsyncStream<StreamOutput>.Continuation,
        output: CLIOutputStream? = nil
    ) async throws {
        // Use unified runProcess - it handles continuation and global broadcast
        _ = try await runProcess(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: nil,
            inheritIO: false,
            stdin: stdin,
            commandID: commandID,
            commandContinuation: continuation,
            output: output
        )
    }

    /// Line-buffered process execution using `bytes.lines` for stdout.
    /// Unlike `runProcess()` which uses `readabilityHandler` for raw data chunks,
    /// this reads stdout one line at a time and yields parsed values to the continuation.
    /// Stderr is still captured via `readabilityHandler`.
    private func runLineBufferedProcess<P: CLILineParser>(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        stdin: Data? = nil,
        commandID: CommandID,
        parser: P,
        continuation: AsyncThrowingStream<P.Output, Error>.Continuation,
        output: CLIOutputStream? = nil
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stderrAccumulator = OutputAccumulator()
        let shouldPrint = self.printOutput
        let globalOutputStream = self.globalOutput
        let clientOutputStream = output

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdinPipe: Pipe?
        if stdin != nil {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            stdinPipe = inputPipe
        }

        // Stderr via readabilityHandler (same as runProcess)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                stderrAccumulator.append(text)
                if shouldPrint {
                    print(text, terminator: "")
                }

                let streamOutput = StreamOutput.stderr(commandID: commandID, text: text)
                Task {
                    await globalOutputStream.send(streamOutput)
                }
                if let clientOutput = clientOutputStream {
                    Task {
                        await clientOutput.send(streamOutput)
                    }
                }
            }
        }

        // Set up termination handler BEFORE run() to avoid a race where the
        // process exits before the handler is installed.
        let terminationSignal = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in
                continuation.yield()
                continuation.finish()
            }
        }

        try process.run()

        // Write stdin data and close
        if let stdinData = stdin, let inputPipe = stdinPipe {
            inputPipe.fileHandleForWriting.write(stdinData)
            inputPipe.fileHandleForWriting.closeFile()
        }

        // Read stdout line-by-line
        for try await line in asyncLines(from: stdoutPipe.fileHandleForReading) {
            let lineWithNewline = line + "\n"
            if shouldPrint {
                print(lineWithNewline, terminator: "")
            }

            let streamOutput = StreamOutput.stdout(commandID: commandID, text: lineWithNewline)
            await globalOutputStream.send(streamOutput)
            await clientOutputStream?.send(streamOutput)

            if let parsed = try parser.parse(line: line) {
                continuation.yield(parsed)
            }
        }

        // Wait for process to exit without blocking a cooperative thread.
        for await _ in terminationSignal { break }

        // Clean up stderr handler
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus

        // Send exit to output streams
        let exitOutput = StreamOutput.exit(commandID: commandID, code: exitCode)
        await globalOutput.send(exitOutput)
        await clientOutputStream?.send(exitOutput)

        if exitCode != 0 {
            let stderr = stderrAccumulator.value
            continuation.finish(throwing: CLIClientError.executionFailed(
                command: "\(command) \(arguments.joined(separator: " "))",
                exitCode: exitCode,
                output: stderr
            ))
        } else {
            continuation.finish()
        }
    }
}

/// Cross-platform async line reader for FileHandle (FileHandle.bytes.lines is not available on Linux)
private func asyncLines(from fileHandle: FileHandle) -> AsyncStream<String> {
    AsyncStream { continuation in
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                fileHandle.readabilityHandler = nil
                continuation.finish()
            } else if let chunk = String(data: data, encoding: .utf8) {
                for line in chunk.components(separatedBy: "\n") where !line.isEmpty {
                    continuation.yield(line)
                }
            }
        }
    }
}


private final class CancellationHandle: Sendable {
    private let mutex = Mutex<Process?>(nil)

    func register(_ process: Process) {
        mutex.withLock { $0 = process }
    }

    func cancel() {
        mutex.withLock { $0 }?.terminate()
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
