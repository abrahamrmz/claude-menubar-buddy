import Darwin
import Foundation
import BuddyCore

let input = FileHandle.standardInput.readDataToEndOfFile()
let output = HookRuleCLI.run(input: input, environment: ProcessInfo.processInfo.environment)
FileHandle.standardOutput.write(output)
exit(0)
