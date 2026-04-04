import Foundation
import os.log

enum Log {
    private static let subsystem = "com.amitpalomo.BetterDisplayFree"
    
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let display = Logger(subsystem: subsystem, category: "Display")
    static let monitor = Logger(subsystem: subsystem, category: "Monitor")
    static let app = Logger(subsystem: subsystem, category: "App")
}
