import CLISDK
import Testing

@Suite("Id Command Tests")
struct IdCommandTests {

    @Test("Id program name")
    func testProgramName() {
        #expect(Id.programName == "id")
    }

    @Test("Id command line with userId flag")
    func testIdUserId() {
        let cmd = Id(userId: true)
        #expect(cmd.commandLine == ["id", "-u"])
    }

    @Test("Id command line with groupId flag")
    func testIdGroupId() {
        let cmd = Id(groupId: true)
        #expect(cmd.commandLine == ["id", "-g"])
    }

    @Test("Id command line with no flags")
    func testIdNoFlags() {
        let cmd = Id()
        #expect(cmd.commandLine == ["id"])
    }

    @Test("Id command string with userId")
    func testIdCommandString() {
        let cmd = Id(userId: true)
        #expect(cmd.commandString == "id -u")
    }

    @Test("IdParser parses valid integer")
    func testIdParserValid() throws {
        let parser = IdParser()
        let result = try parser.parse("501\n")
        #expect(result == 501)
    }

    @Test("IdParser handles whitespace")
    func testIdParserWhitespace() throws {
        let parser = IdParser()
        let result = try parser.parse("  20  \n")
        #expect(result == 20)
    }

    @Test("IdParser throws on invalid input")
    func testIdParserInvalid() {
        let parser = IdParser()
        #expect(throws: CLIClientError.self) {
            try parser.parse("not-a-number")
        }
    }
}

@Suite("Kill Command Tests")
struct KillCommandTests {

    @Test("Kill program name")
    func testProgramName() {
        #expect(Kill.programName == "kill")
    }

    @Test("Kill command line with PID only")
    func testKillPidOnly() {
        let cmd = Kill(pid: "12345")
        #expect(cmd.commandLine == ["kill", "12345"])
    }

    @Test("Kill command line with signal")
    func testKillWithSignal() {
        let cmd = Kill(signal: "9", pid: "12345")
        #expect(cmd.commandLine == ["kill", "-9", "12345"])
    }

    @Test("Kill command line with TERM signal")
    func testKillWithTermSignal() {
        let cmd = Kill(signal: "TERM", pid: "12345")
        #expect(cmd.commandLine == ["kill", "-TERM", "12345"])
    }

    @Test("Kill command string")
    func testKillCommandString() {
        let cmd = Kill(signal: "9", pid: "12345")
        #expect(cmd.commandString == "kill -9 12345")
    }
}

@Suite("Lsof Command Tests")
struct LsofCommandTests {

    @Test("Lsof program name")
    func testProgramName() {
        #expect(Lsof.programName == "lsof")
    }

    @Test("Lsof command line")
    func testLsof() {
        let cmd = Lsof(port: ":8080")
        #expect(cmd.commandLine == ["lsof", "-i", ":8080"])
    }

    @Test("Lsof with different port")
    func testLsofDifferentPort() {
        let cmd = Lsof(port: ":3000")
        #expect(cmd.commandLine == ["lsof", "-i", ":3000"])
    }

    @Test("Lsof with pidOnly flag")
    func testLsofPidOnly() {
        let cmd = Lsof(port: ":8080", pidOnly: true)
        #expect(cmd.commandLine == ["lsof", "-i", ":8080", "-t"])
    }

    @Test("Lsof command string")
    func testLsofCommandString() {
        let cmd = Lsof(port: ":8080", pidOnly: true)
        #expect(cmd.commandString == "lsof -i :8080 -t")
    }

    @Test("LsofPidParser parses multiple PIDs")
    func testLsofPidParserMultiple() throws {
        let parser = LsofPidParser()
        let result = try parser.parse("12345\n67890\n")
        #expect(result == [12345, 67890])
    }

    @Test("LsofPidParser handles single PID")
    func testLsofPidParserSingle() throws {
        let parser = LsofPidParser()
        let result = try parser.parse("501\n")
        #expect(result == [501])
    }

    @Test("LsofPidParser handles empty output")
    func testLsofPidParserEmpty() throws {
        let parser = LsofPidParser()
        let result = try parser.parse("")
        #expect(result == [])
    }

    @Test("LsofPidParser handles whitespace")
    func testLsofPidParserWhitespace() throws {
        let parser = LsofPidParser()
        let result = try parser.parse("  123\n456  \n")
        #expect(result == [123, 456])
    }

    @Test("LsofPidParser throws on invalid input")
    func testLsofPidParserInvalid() {
        let parser = LsofPidParser()
        #expect(throws: CLIClientError.self) {
            try parser.parse("not-a-pid")
        }
    }
}

@Suite("Sh Command Tests")
struct ShCommandTests {

    @Test("Sh program name")
    func testProgramName() {
        #expect(Sh.programName == "sh")
    }

    @Test("Sh command line with simple command")
    func testShSimpleCommand() {
        let cmd = Sh(command: "echo hello")
        #expect(cmd.commandLine == ["sh", "-c", "echo hello"])
    }

    @Test("Sh command line with complex command")
    func testShComplexCommand() {
        let cmd = Sh(command: "cd /tmp && ls -la")
        #expect(cmd.commandLine == ["sh", "-c", "cd /tmp && ls -la"])
    }

    @Test("Sh command line with environment variables")
    func testShWithEnvVars() {
        let cmd = Sh(command: "FOO=bar ./script.sh")
        #expect(cmd.commandLine == ["sh", "-c", "FOO=bar ./script.sh"])
    }

    @Test("Sh command line with background process")
    func testShBackgroundProcess() {
        let cmd = Sh(command: "./process > /tmp/out.log 2>&1 & echo $!")
        #expect(cmd.commandLine == ["sh", "-c", "./process > /tmp/out.log 2>&1 & echo $!"])
    }

    @Test("Sh command string")
    func testShCommandString() {
        let cmd = Sh(command: "echo hello")
        #expect(cmd.commandString == "sh -c \"echo hello\"")
    }
}

@Suite("Open Command Tests")
struct OpenCommandTests {

    @Test("Open program name")
    func testProgramName() {
        #expect(Open.programName == "open")
    }

    @Test("Open command line with application")
    func testOpenWithApplication() {
        let cmd = Open(application: "Docker")
        #expect(cmd.commandLine == ["open", "-a", "Docker"])
    }

    @Test("Open command line with path")
    func testOpenWithPath() {
        let cmd = Open(path: "/path/to/file.txt")
        #expect(cmd.commandLine == ["open", "/path/to/file.txt"])
    }

    @Test("Open command line with application and path")
    func testOpenWithAppAndPath() {
        let cmd = Open(application: "TextEdit", path: "/path/to/file.txt")
        #expect(cmd.commandLine == ["open", "-a", "TextEdit", "/path/to/file.txt"])
    }

    @Test("Open command line with no arguments")
    func testOpenNoArgs() {
        let cmd = Open()
        #expect(cmd.commandLine == ["open"])
    }

    @Test("Open command string")
    func testOpenCommandString() {
        let cmd = Open(application: "Docker")
        #expect(cmd.commandString == "open -a Docker")
    }
}

@Suite("Rm Command Tests")
struct RmCommandTests {

    @Test("Rm program name")
    func testProgramName() {
        #expect(Rm.programName == "rm")
    }

    @Test("Rm command line with single path")
    func testRmSinglePath() {
        let cmd = Rm(paths: ["file.txt"])
        #expect(cmd.commandLine == ["rm", "file.txt"])
    }

    @Test("Rm command line with multiple paths")
    func testRmMultiplePaths() {
        let cmd = Rm(paths: ["file1.txt", "file2.txt", "dir/"])
        #expect(cmd.commandLine == ["rm", "file1.txt", "file2.txt", "dir/"])
    }

    @Test("Rm command line with recursive flag")
    func testRmRecursive() {
        let cmd = Rm(recursive: true, paths: ["dir/"])
        #expect(cmd.commandLine == ["rm", "-r", "dir/"])
    }

    @Test("Rm command line with force flag")
    func testRmForce() {
        let cmd = Rm(force: true, paths: ["file.txt"])
        #expect(cmd.commandLine == ["rm", "-f", "file.txt"])
    }

    @Test("Rm command line with recursive and force flags")
    func testRmRecursiveForce() {
        let cmd = Rm(recursive: true, force: true, paths: ["dir/"])
        #expect(cmd.commandLine == ["rm", "-r", "-f", "dir/"])
    }

    @Test("Rm command line with multiple paths and flags")
    func testRmFullUsage() {
        let cmd = Rm(recursive: true, force: true, paths: [".build", "lambda.zip", "bootstrap"])
        #expect(cmd.commandLine == ["rm", "-r", "-f", ".build", "lambda.zip", "bootstrap"])
    }

    @Test("Rm command string")
    func testRmCommandString() {
        let cmd = Rm(recursive: true, force: true, paths: ["dir/"])
        #expect(cmd.commandString == "rm -r -f dir/")
    }
}

@Suite("Which Command Tests")
struct WhichCommandTests {

    @Test("Which program name")
    func testProgramName() {
        #expect(Which.programName == "which")
    }

    @Test("Which command line with command only")
    func testWhichCommandOnly() {
        let cmd = Which(command: "aws-vault")
        #expect(cmd.commandLine == ["which", "aws-vault"])
    }

    @Test("Which command line with all flag")
    func testWhichWithAllFlag() {
        let cmd = Which(all: true, command: "python")
        #expect(cmd.commandLine == ["which", "-a", "python"])
    }

    @Test("Which command string")
    func testWhichCommandString() {
        let cmd = Which(command: "aws-vault")
        #expect(cmd.commandString == "which aws-vault")
    }

    @Test("Which command string with all flag")
    func testWhichCommandStringWithAll() {
        let cmd = Which(all: true, command: "python")
        #expect(cmd.commandString == "which -a python")
    }
}
