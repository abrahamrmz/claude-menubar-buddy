import Darwin
import Foundation
import BuddyCore

let input = FileHandle.standardInput.readDataToEndOfFile()
let environment = ProcessInfo.processInfo.environment
let output = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "session-end"
    ? HookRuleCLI.sessionEnd(input: input, environment: environment)
    : HookRuleCLI.run(input: input, environment: environment)
FileHandle.standardOutput.write(output)
exit(0)
