import AppKit

AppLanguage.applyStoredPreference()
let application = NSApplication.shared
let candelaDelegate = AppDelegate()
application.delegate = candelaDelegate
application.run()
