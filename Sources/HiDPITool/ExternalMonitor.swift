import Foundation
import CoreGraphics
import AppKit

struct ExternalMonitor: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let resolution: String
    let isBuiltIn: Bool
    
    var displayID: CGDirectDisplayID { id }
    
    static func == (lhs: ExternalMonitor, rhs: ExternalMonitor) -> Bool {
        lhs.id == rhs.id
    }
}

final class MonitorDetector: ObservableObject {
    static let shared = MonitorDetector()
    
    @Published private(set) var externalMonitors: [ExternalMonitor] = []
    @Published private(set) var allMonitors: [ExternalMonitor] = []
    
    private init() {
        refresh()
        setupDisplayReconfigurationCallback()
    }
    
    func refresh() {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        
        guard displayCount > 0 else {
            externalMonitors = []
            allMonitors = []
            return
        }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        
        var monitors: [ExternalMonitor] = []
        var external: [ExternalMonitor] = []
        
        let virtualDisplayIDs = DisplayManager.shared.recentVirtualDisplayIDs
        let physicalDisplayIDs = Set(DisplayManager.shared.virtualDisplays.keys)
        
        Log.monitor.debug("refresh() - found \(displays.count) displays")
        Log.monitor.debug("virtualDisplayIDs: \(virtualDisplayIDs)")
        Log.monitor.debug("physicalDisplayIDs (with HiDPI): \(physicalDisplayIDs)")
        
        for displayID in displays {
            let isInMirrorSet = CGDisplayIsInMirrorSet(displayID) != 0
            let mirrorsDisplay = CGDisplayMirrorsDisplay(displayID)
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let name = getDisplayName(for: displayID) ?? "Display \(displayID)"
            
            Log.monitor.debug("Display \(displayID) '\(name)': builtIn=\(isBuiltIn), inMirrorSet=\(isInMirrorSet), mirrors=\(mirrorsDisplay)")
            
            if virtualDisplayIDs.contains(displayID) {
                Log.monitor.debug("  -> SKIP: is our virtual display")
                continue
            }
            
            if isInMirrorSet && mirrorsDisplay != kCGNullDirectDisplay {
                if !physicalDisplayIDs.contains(displayID) {
                    Log.monitor.debug("  -> SKIP: in mirror set but not our physical display")
                    continue
                } else {
                    Log.monitor.debug("  -> KEEP: is our physical display with HiDPI enabled")
                }
            }
            
            let resolution = getResolutionString(for: displayID)
            
            let monitor = ExternalMonitor(
                id: displayID,
                name: name,
                resolution: resolution,
                isBuiltIn: isBuiltIn
            )
            
            monitors.append(monitor)
            if !isBuiltIn {
                external.append(monitor)
                Log.monitor.debug("  -> ADDED as external monitor")
            } else {
                Log.monitor.debug("  -> ADDED as built-in monitor")
            }
        }
        
        Log.monitor.info("Detected \(external.count) external monitor(s)")
        
        DispatchQueue.main.async {
            self.allMonitors = monitors
            self.externalMonitors = external
        }
    }
    
    private func getDisplayName(for displayID: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                return screen.localizedName
            }
        }
        
        let vendorID = CGDisplayVendorNumber(displayID)
        let modelID = CGDisplayModelNumber(displayID)
        
        if vendorID != 0 || modelID != 0 {
            return "Display \(vendorID)-\(modelID)"
        }
        
        return nil
    }
    
    private func getResolutionString(for displayID: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return "Unknown"
        }
        
        let width = mode.pixelWidth
        let height = mode.pixelHeight
        let refreshRate = mode.refreshRate
        
        if refreshRate > 0 {
            return "\(width)×\(height) @ \(Int(refreshRate))Hz"
        } else {
            return "\(width)×\(height)"
        }
    }
    
    private func setupDisplayReconfigurationCallback() {
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in
            guard let userInfo = userInfo else { return }
            let detector = Unmanaged<MonitorDetector>.fromOpaque(userInfo).takeUnretainedValue()
            
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.setMainFlag) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    detector.refresh()
                }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    deinit {
        CGDisplayRemoveReconfigurationCallback({ _, _, _ in }, nil)
    }
}
