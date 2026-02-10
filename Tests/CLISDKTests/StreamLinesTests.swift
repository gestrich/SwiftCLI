import Foundation
import Testing
@testable import CLISDK

@Suite("streamLines Tests")
struct StreamLinesTests {

    // MARK: - streamLines with echo

    @Test("streamLines returns individual lines from echo")
    func testStreamLinesEcho() async throws {
        let client = CLIClient()
        var lines: [String] = []

        let stream = await client.streamLines(
            command: "/bin/bash",
            arguments: ["-c", "echo line1; echo line2; echo line3"],
            printCommand: false
        )

        for try await line in stream {
            lines.append(line)
        }

        #expect(lines == ["line1", "line2", "line3"])
    }

    // MARK: - streamLines with stdin piped to cat

    @Test("streamLines with stdin data piped to cat returns the input lines")
    func testStreamLinesStdinCat() async throws {
        let client = CLIClient()
        let input = "hello\nworld\n".data(using: .utf8)!
        var lines: [String] = []

        let stream = await client.streamLines(
            command: "cat",
            printCommand: false,
            stdin: input
        )

        for try await line in stream {
            lines.append(line)
        }

        #expect(lines == ["hello", "world"])
    }

    // MARK: - streamLines with parser that parses/skips

    @Test("streamLines with custom parser skips lines that return nil")
    func testStreamLinesWithParser() async throws {
        let client = CLIClient()
        var results: [Int] = []

        let stream = await client.streamLines(
            command: "/bin/bash",
            arguments: ["-c", "echo 1; echo skip; echo 2; echo skip; echo 3"],
            printCommand: false,
            parser: IntLineParser()
        )

        for try await value in stream {
            results.append(value)
        }

        #expect(results == [1, 2, 3])
    }

    // MARK: - streamLines throws on non-zero exit

    @Test("streamLines throws CLIClientError.executionFailed on non-zero exit")
    func testStreamLinesThrowsOnFailure() async throws {
        let client = CLIClient()

        do {
            let stream = await client.streamLines(
                command: "false",
                printCommand: false
            )
            for try await _ in stream {}
            Issue.record("Expected error to be thrown")
        } catch is CLIClientError {
            // Expected
        }
    }

    @Test("streamLines error contains correct exit code")
    func testStreamLinesErrorExitCode() async throws {
        let client = CLIClient()

        do {
            let stream = await client.streamLines(
                command: "/bin/bash",
                arguments: ["-c", "exit 42"],
                printCommand: false
            )
            for try await _ in stream {}
            Issue.record("Expected error to be thrown")
        } catch let error as CLIClientError {
            if case .executionFailed(_, let exitCode, _) = error {
                #expect(exitCode == 42)
            } else {
                Issue.record("Expected executionFailed, got \(error)")
            }
        }
    }

    // MARK: - execute with stdin piped to cat

    @Test("execute with stdin data piped to cat returns the input")
    func testExecuteStdinCat() async throws {
        let client = CLIClient()
        let input = "hello from stdin\n".data(using: .utf8)!

        let result = try await client.execute(
            command: "cat",
            printCommand: false,
            stdin: input
        )

        #expect(result.isSuccess)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello from stdin")
    }

    @Test("execute with multi-line stdin data piped to cat")
    func testExecuteStdinMultiLine() async throws {
        let client = CLIClient()
        let input = "line1\nline2\nline3\n".data(using: .utf8)!

        let result = try await client.execute(
            command: "cat",
            printCommand: false,
            stdin: input
        )

        #expect(result.isSuccess)
        #expect(result.stdout == "line1\nline2\nline3\n")
    }
}

// MARK: - PassthroughLineParser Tests

@Suite("PassthroughLineParser Tests")
struct PassthroughLineParserTests {

    @Test("PassthroughLineParser returns non-empty lines")
    func testNonEmptyLine() {
        let parser = PassthroughLineParser()
        #expect(parser.parse(line: "hello") == "hello")
    }

    @Test("PassthroughLineParser returns nil for empty lines")
    func testEmptyLine() {
        let parser = PassthroughLineParser()
        #expect(parser.parse(line: "") == nil)
    }

    @Test("PassthroughLineParser preserves whitespace-only lines")
    func testWhitespaceLine() {
        let parser = PassthroughLineParser()
        #expect(parser.parse(line: "  ") == "  ")
    }
}

// MARK: - JSONLineParser Tests

@Suite("JSONLineParser Tests")
struct JSONLineParserTests {

    private struct TestMessage: Decodable, Sendable, Equatable {
        let type: String
        let value: Int
    }

    @Test("JSONLineParser decodes valid JSON lines")
    func testValidJSON() {
        let parser = JSONLineParser<TestMessage>()
        let result = parser.parse(line: #"{"type":"test","value":42}"#)
        #expect(result == TestMessage(type: "test", value: 42))
    }

    @Test("JSONLineParser returns nil for invalid JSON")
    func testInvalidJSON() {
        let parser = JSONLineParser<TestMessage>()
        #expect(parser.parse(line: "not json") == nil)
    }

    @Test("JSONLineParser returns nil for empty lines")
    func testEmptyLine() {
        let parser = JSONLineParser<TestMessage>()
        #expect(parser.parse(line: "") == nil)
    }

    @Test("JSONLineParser returns nil for JSON with wrong schema")
    func testWrongSchema() {
        let parser = JSONLineParser<TestMessage>()
        #expect(parser.parse(line: #"{"name":"test"}"#) == nil)
    }

    @Test("JSONLineParser uses custom decoder")
    func testCustomDecoder() {
        struct SnakeMessage: Decodable, Sendable, Equatable {
            let myField: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parser = JSONLineParser<SnakeMessage>(decoder: decoder)
        let result = parser.parse(line: #"{"my_field":"hello"}"#)
        #expect(result == SnakeMessage(myField: "hello"))
    }

    @Test("JSONLineParser works with streamLines end-to-end")
    func testJSONLineParserIntegration() async throws {
        struct Item: Decodable, Sendable, Equatable {
            let id: Int
        }
        let client = CLIClient()
        let jsonLines = #"echo '{"id":1}'; echo 'garbage'; echo '{"id":2}'"#
        var items: [Item] = []

        let stream = await client.streamLines(
            command: "/bin/bash",
            arguments: ["-c", jsonLines],
            printCommand: false,
            parser: JSONLineParser<Item>()
        )

        for try await item in stream {
            items.append(item)
        }

        #expect(items == [Item(id: 1), Item(id: 2)])
    }
}

// MARK: - Test Helpers

/// A test parser that parses integer lines and skips non-integer lines
private struct IntLineParser: CLILineParser {
    func parse(line: String) -> Int? {
        Int(line)
    }
}
