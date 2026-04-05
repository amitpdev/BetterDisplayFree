import SwiftUI
import AppKit
import ServiceManagement

enum AppVersion {
    static let current: String = {
        let bundle = Bundle.main
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        if let versionFileURL = bundle.url(forResource: "VERSION", withExtension: nil),
           let version = try? String(contentsOf: versionFileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            return version
        }
        #if DEBUG
        return "dev"
        #else
        return "1.0.0"
        #endif
    }()
}

@main
struct BetterDisplayFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitorDetector = MonitorDetector.shared
    @StateObject private var displayManager = DisplayManager.shared
    
    var body: some Scene {
        MenuBarExtra("BetterDisplayFree", systemImage: "display") {
            MenuBarView()
                .environmentObject(monitorDetector)
                .environmentObject(displayManager)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var monitorDetector: MonitorDetector
    @EnvironmentObject var displayManager: DisplayManager
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if monitorDetector.externalMonitors.isEmpty {
                Text("No external monitors")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(monitorDetector.externalMonitors) { monitor in
                    MonitorToggleView(monitor: monitor)
                }
            }
            
            Divider()
            
            Button("Refresh Displays") {
                monitorDetector.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("Open Display Settings...") {
                openDisplaySettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Toggle("Start at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.isEnabled = newValue
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            
            Divider()
            
            Button("About BetterDisplayFree...") {
                AboutWindow.show()
            }
            
            Button("Quit") {
                displayManager.cleanup()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
    }
    
    private func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MonitorToggleView: View {
    let monitor: ExternalMonitor
    @EnvironmentObject var displayManager: DisplayManager
    @State private var isProcessing: Bool = false
    
    private var isEnabled: Bool {
        displayManager.isHiDPIEnabled(for: monitor.displayID)
    }
    
    private var displayName: String {
        isEnabled ? "\(monitor.name) (HiDPI)" : monitor.name
    }
    
    var body: some View {
        Button(action: { toggleHiDPI() }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                    Text(monitor.resolution)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if isEnabled {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .disabled(isProcessing)
    }
    
    private func toggleHiDPI() {
        isProcessing = true
        let shouldEnable = !isEnabled
        
        Log.ui.info("toggleHiDPI for '\(monitor.name)' (ID: \(monitor.displayID)) - shouldEnable=\(shouldEnable)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success: Bool
            if shouldEnable {
                success = displayManager.enableHiDPI(for: monitor.displayID)
            } else {
                success = displayManager.disableHiDPI(for: monitor.displayID)
            }
            
            DispatchQueue.main.async {
                isProcessing = false
                if success {
                    Log.ui.info("toggleHiDPI completed successfully")
                } else {
                    Log.ui.error("Failed to \(shouldEnable ? "enable" : "disable") HiDPI")
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupSignalHandlers()
    }
    
    private func setupSignalHandlers() {
        let signals = [SIGINT, SIGTERM]
        
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                DisplayManager.shared.cleanup()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        DisplayManager.shared.cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
            }
        }
    }
}

enum AboutWindow {
    private static var window: NSWindow?
    
    static func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let aboutView = AboutView()
        let hostingView = NSHostingView(rootView: aboutView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "About BetterDisplayFree"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        window = newWindow
    }
}

struct AboutView: View {
    private let repoURL = "https://github.com/amitpdev/BetterDisplayFree"
    private let version = AppVersion.current
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("BetterDisplayFree")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Version \(version)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Enable HiDPI scaling on external monitors")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Free and open source")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Link(repoURL, destination: URL(string: repoURL)!)
                    .font(.caption2)
            }
        }
        .padding(24)
        .frame(width: 300, height: 280)
    }
}
