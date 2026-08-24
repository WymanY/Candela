import AppKit

AppLanguage.applyStoredPreference()
let candelaDelegate = AppDelegate()
NSApplication.shared.delegate = candelaDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
