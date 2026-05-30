import AppKit
import Foundation
import ClaudeSignalCore

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--simulate" {
    exit(Simulate.run(Array(args.dropFirst())))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let controller = AppController()
app.delegate = controller
app.run()
