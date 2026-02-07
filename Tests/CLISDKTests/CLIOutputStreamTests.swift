import Testing
@testable import CLISDK

// Test command ID for consistent testing
private let testCommandID = CommandID()

// Helper to check StreamOutput values
private func isCommand(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .command(_, let text) = output { return text == expected }
    return false
}

private func isStdout(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .stdout(_, let text) = output { return text == expected }
    return false
}

private func isStderr(_ output: StreamOutput, _ expected: String) -> Bool {
    if case .stderr(_, let text) = output { return text == expected }
    return false
}

private func isExit(_ output: StreamOutput, _ expected: Int32) -> Bool {
    if case .exit(_, let code) = output { return code == expected }
    return false
}

@Suite("CLIOutputStream Tests")
struct CLIOutputStreamTests {

    // MARK: - Dual Stream Output Tests

    @Test("CLIClient execute sends to both global and client streams")
    func testExecuteSendsToBothStreams() async throws {
        let cliClient = CLIClient()

        // Create client-owned stream
        let clientStream = CLIOutputStream()

        // Start subscribers that return collected output
        let globalTask = Task { () -> [StreamOutput] in
            var received: [StreamOutput] = []
            for await item in await cliClient.outputStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        let clientTask = Task { () -> [StreamOutput] in
            var received: [StreamOutput] = []
            for await item in await clientStream.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscribers time to register
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Execute command with client stream
        _ = try await cliClient.execute(
            command: "echo",
            arguments: ["hello"],
            printCommand: false,
            output: clientStream
        )

        // Give streams time to receive all output
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Finish client stream
        await clientStream.finishAll()

        // Wait for tasks and get results
        let globalOutput = await globalTask.value
        let clientOutput = await clientTask.value

        // Both streams should have received the command output
        let globalHasEcho = globalOutput.contains { isStdout($0, "hello\n") }
        let clientHasEcho = clientOutput.contains { isStdout($0, "hello\n") }

        #expect(globalHasEcho, "Global stream should receive stdout")
        #expect(clientHasEcho, "Client stream should receive stdout")
    }

    @Test("CLIClient stream sends to both global and client streams")
    func testStreamSendsToBothStreams() async throws {
        let cliClient = CLIClient()

        // Create client-owned stream
        let clientStream = CLIOutputStream()

        // Start subscribers that return collected output
        let globalTask = Task { () -> [StreamOutput] in
            var received: [StreamOutput] = []
            for await item in await cliClient.outputStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        let clientTask = Task { () -> [StreamOutput] in
            var received: [StreamOutput] = []
            for await item in await clientStream.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscribers time to register
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Stream command with client stream
        for await _ in await cliClient.stream(
            command: "echo",
            arguments: ["test"],
            printCommand: false,
            output: clientStream
        ) {
            // Consume the per-command stream
        }

        // Give streams time to receive all output
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Finish client stream
        await clientStream.finishAll()

        // Wait for tasks and get results
        let globalOutput = await globalTask.value
        let clientOutput = await clientTask.value

        // Both streams should have received output
        let globalHasOutput = globalOutput.contains { isStdout($0, "test\n") }
        let clientHasOutput = clientOutput.contains { isStdout($0, "test\n") }

        #expect(globalHasOutput, "Global stream should receive stdout from stream()")
        #expect(clientHasOutput, "Client stream should receive stdout from stream()")
    }

    @Test("Client stream isolation - only receives own operation output")
    func testClientStreamIsolation() async throws {
        let cliClient = CLIClient()

        // Create a client stream for operation 2 only
        let clientStream = CLIOutputStream()

        let clientTask = Task { () -> [StreamOutput] in
            var received: [StreamOutput] = []
            for await item in await clientStream.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscriber time to register
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Operation 1: Execute WITHOUT client stream
        _ = try await cliClient.execute(
            command: "echo",
            arguments: ["operation-one"],
            printCommand: false
        )

        // Operation 2: Execute WITH client stream
        _ = try await cliClient.execute(
            command: "echo",
            arguments: ["operation-two"],
            printCommand: false,
            output: clientStream
        )

        // Give time for output
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Finish client stream
        await clientStream.finishAll()

        let clientOutput = await clientTask.value

        // Client stream should only have operation-two output
        let hasOpOne = clientOutput.contains { isStdout($0, "operation-one\n") }
        let hasOpTwo = clientOutput.contains { isStdout($0, "operation-two\n") }

        #expect(!hasOpOne, "Client stream should NOT receive operation-one output")
        #expect(hasOpTwo, "Client stream should receive operation-two output")
    }

    // MARK: - Original CLIOutputStream Tests

    @Test("Single subscriber receives output")
    func testSingleSubscriber() async {
        let output = CLIOutputStream()

        // Start subscriber
        let task = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send output
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "hello"))
        await output.send(.stderr(commandID: cmdID, text: "error"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received = await task.value

        #expect(received.count == 3)
        #expect(isStdout(received[0], "hello"))
        #expect(isStderr(received[1], "error"))
        #expect(isExit(received[2], 0))
    }

    @Test("Multiple subscribers each receive all output")
    func testMultipleSubscribers() async {
        let output = CLIOutputStream()

        // Start two subscribers
        let task1 = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        let task2 = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscribers time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send output
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "message"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received1 = await task1.value
        let received2 = await task2.value

        // Both should receive the same messages
        #expect(received1.count == 2)
        #expect(received2.count == 2)
        #expect(isStdout(received1[0], "message"))
        #expect(isStdout(received2[0], "message"))
    }

    @Test("Subscriber count tracks active subscribers")
    func testSubscriberCount() async {
        let output = CLIOutputStream()

        #expect(await output.subscriberCount == 0)

        // Start a subscriber
        let task = Task {
            for await item in await output.makeStream() {
                if case .exit = item { break }
            }
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 1)

        // End the stream
        let cmdID = CommandID()
        await output.send(.exit(commandID: cmdID, code: 0))
        await task.value

        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 0)
    }

    @Test("Late subscriber only receives future output")
    func testLateSubscriber() async {
        let output = CLIOutputStream()

        // Send before any subscriber
        let missedCmdID = CommandID()
        await output.send(.stdout(commandID: missedCmdID, text: "missed"))

        // Now subscribe
        let task = Task {
            var received: [StreamOutput] = []
            for await item in await output.makeStream() {
                received.append(item)
                if case .exit = item { break }
            }
            return received
        }

        // Give subscriber time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Send after subscriber
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "received"))
        await output.send(.exit(commandID: cmdID, code: 0))

        let received = await task.value

        // Should only have the messages sent after subscribing
        #expect(received.count == 2)
        #expect(isStdout(received[0], "received"))
    }

    @Test("finishAll closes all streams")
    func testFinishAll() async {
        let output = CLIOutputStream()

        let task1 = Task {
            var count = 0
            for await _ in await output.makeStream() {
                count += 1
            }
            return count
        }

        let task2 = Task {
            var count = 0
            for await _ in await output.makeStream() {
                count += 1
            }
            return count
        }

        // Give subscribers time to register
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(await output.subscriberCount == 2)

        // Send one message then finish
        let cmdID = CommandID()
        await output.send(.stdout(commandID: cmdID, text: "test"))
        await output.finishAll()

        // Wait for tasks to complete - they should exit when stream finishes
        let count1 = await task1.value
        let count2 = await task2.value

        #expect(count1 == 1)
        #expect(count2 == 1)
        #expect(await output.subscriberCount == 0)
    }
}
