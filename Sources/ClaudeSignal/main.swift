import Foundation
import ClaudeSignalCore

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--simulate" {
    exit(Simulate.run(Array(args.dropFirst())))
}
// App mode is wired in Task 15.
print("claude-signal \(claudeSignalCoreVersion) (app mode not yet wired)")
