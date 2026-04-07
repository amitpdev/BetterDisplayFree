import Foundation
import CoreGraphics
import AppKit

@MainActor
final class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published private(set) var virtualDisplays: [CGDirectDisplayID: VirtualDisplayInfo] = [:]
    private(set) var recentVirtualDisplayIDs: Set<CGDirectDisplayID> = []
    
    struct VirtualDisplayInfo {
        let virtualDisplay: CGVirtualDisplay
        let physicalDisplayID: CGDirectDisplayID
        let virtualDisplayID: CGDirectDisplayID
    }
    
    private init() {
        setupDisplayReconfigurationCallback()
        setupSleepWakeNotifications()
    }
    
    private func setupSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
    }

    private func handleSystemWake() {
        Log.display.info("System woke up, checking display connections...")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.cleanupDisconnectedDisplays()
        }
    }
    
    private func cleanupDisconnectedDisplays() {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)

        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &onlineDisplays, &displayCount)
        // Use the count from the second call to avoid trailing kCGNullDirectDisplay zeros
        // if a display was removed between the two calls.
        let onlineSet = Set(onlineDisplays.prefix(Int(displayCount)))
        
        let orphanedPhysicalIDs = virtualDisplays.keys.filter { !onlineSet.contains($0) }
        
        for physicalID in orphanedPhysicalIDs {
            Log.display.info("Physical display \(physicalID) no longer connected after wake, cleaning up")
            virtualDisplays.removeValue(forKey: physicalID)
        }
        
        let orphanedVirtualIDs = recentVirtualDisplayIDs.filter { !onlineSet.contains($0) }
        for virtualID in orphanedVirtualIDs {
            Log.display.debug("Virtual display \(virtualID) no longer exists, removing from tracking")
            recentVirtualDisplayIDs.remove(virtualID)
        }
        
        if !orphanedPhysicalIDs.isEmpty || !orphanedVirtualIDs.isEmpty {
            Log.display.info("Cleanup complete: removed \(orphanedPhysicalIDs.count) orphaned HiDPI configs")
        }
    }
    
    private func setupDisplayReconfigurationCallback() {
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()

            if flags.contains(.removeFlag) {
                Task { @MainActor in
                    manager.handleDisplayRemoved(displayID)
                }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func handleDisplayRemoved(_ displayID: CGDirectDisplayID) {
        if virtualDisplays[displayID] != nil {
            Log.display.info("Physical display \(displayID) was disconnected, cleaning up HiDPI")
            virtualDisplays.removeValue(forKey: displayID)
        }
        
        if recentVirtualDisplayIDs.contains(displayID) {
            Log.display.info("Virtual display \(displayID) was removed, cleaning up tracking")
            recentVirtualDisplayIDs.remove(displayID)
        }
    }
    
    func enableHiDPI(for physicalDisplayID: CGDirectDisplayID) async -> Bool {
        if virtualDisplays[physicalDisplayID] != nil {
            Log.display.info("HiDPI already enabled for display \(physicalDisplayID)")
            return true
        }

        if CGDisplayIsInMirrorSet(physicalDisplayID) != 0 {
            Log.display.error("Display \(physicalDisplayID) is already in a mirror set not owned by this app; cannot enable HiDPI")
            return false
        }
        
        guard let mode = CGDisplayCopyDisplayMode(physicalDisplayID) else {
            Log.display.error("Failed to get display mode for display \(physicalDisplayID)")
            return false
        }
        
        let nativeWidth = mode.pixelWidth
        let nativeHeight = mode.pixelHeight
        let refreshRate = mode.refreshRate > 0 ? mode.refreshRate : 60.0
        
        let screenSize = CGDisplayScreenSize(physicalDisplayID)
        
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "HiDPI Virtual Display"
        descriptor.maxPixelsWide = UInt32(nativeWidth * 2)
        descriptor.maxPixelsHigh = UInt32(nativeHeight * 2)
        descriptor.sizeInMillimeters = screenSize
        descriptor.vendorID = CGDisplayVendorNumber(physicalDisplayID)
        descriptor.productID = CGDisplayModelNumber(physicalDisplayID) + 0x1000
        descriptor.serialNum = CGDisplaySerialNumber(physicalDisplayID) + 1
        
        let virtualDisplay = CGVirtualDisplay(descriptor: descriptor)
        
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        
        let modes = generateHiDPIModes(
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            refreshRate: refreshRate
        )
        settings.modes = modes
        
        Log.display.info("Created \(modes.count) HiDPI modes for \(nativeWidth)×\(nativeHeight) display")
        
        guard virtualDisplay.apply(settings) else {
            Log.display.error("Failed to apply virtual display settings")
            return false
        }
        
        let virtualDisplayID = virtualDisplay.displayID
        Log.display.info("Created virtual display with ID: \(virtualDisplayID)")
        
        let info = VirtualDisplayInfo(
            virtualDisplay: virtualDisplay,
            physicalDisplayID: physicalDisplayID,
            virtualDisplayID: virtualDisplayID
        )
        virtualDisplays[physicalDisplayID] = info
        recentVirtualDisplayIDs.insert(virtualDisplayID)
        Log.display.debug("Registered virtual display in tracking dictionary")
        
        // Non-blocking wait for the virtual display to become available in the system display list.
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        if !configureMirroring(physicalDisplayID: physicalDisplayID, virtualDisplayID: virtualDisplayID) {
            Log.display.error("Failed to configure mirroring")
            virtualDisplays.removeValue(forKey: physicalDisplayID)
            return false
        }
        
        Log.display.info("HiDPI enabled for display \(physicalDisplayID)")
        return true
    }
    
    private func generateHiDPIModes(nativeWidth: Int, nativeHeight: Int, refreshRate: Double) -> [CGVirtualDisplayMode] {
        var modes: [CGVirtualDisplayMode] = []
        
        let aspectRatio = Double(nativeWidth) / Double(nativeHeight)
        
        var targetWidths: [Int] = []
        
        if abs(aspectRatio - 16.0/9.0) < 0.01 {
            targetWidths = [1920, 1600, 1440, 1280, 1152, 1024, 960, 896, 800]
        } else if abs(aspectRatio - 16.0/10.0) < 0.01 {
            targetWidths = [1920, 1680, 1440, 1280, 1024, 960, 800]
        } else {
            let baseWidth = nativeWidth / 2
            targetWidths = [
                baseWidth,
                Int(Double(baseWidth) * 0.833),
                Int(Double(baseWidth) * 0.75),
                Int(Double(baseWidth) * 0.667),
                Int(Double(baseWidth) * 0.5)
            ]
        }
        
        for width in targetWidths {
            let height = Int(Double(width) / aspectRatio)
            
            if width * 2 <= nativeWidth * 2 && height * 2 <= nativeHeight * 2 {
                let mode = CGVirtualDisplayMode(
                    width: UInt(width),
                    height: UInt(height),
                    refreshRate: CGFloat(refreshRate)
                )
                modes.append(mode)
                Log.display.debug("  Added HiDPI mode: \(width)×\(height) (backing: \(width*2)×\(height*2))")
            }
        }
        
        let nativeMode = CGVirtualDisplayMode(
            width: UInt(nativeWidth),
            height: UInt(nativeHeight),
            refreshRate: CGFloat(refreshRate)
        )
        
        let hasNative = modes.contains { Int($0.width) == nativeWidth && Int($0.height) == nativeHeight }
        if !hasNative {
            modes.insert(nativeMode, at: 0)
            Log.display.debug("  Added native mode: \(nativeWidth)×\(nativeHeight)")
        }
        
        return modes
    }
    
    func disableHiDPI(for physicalDisplayID: CGDirectDisplayID) -> Bool {
        guard virtualDisplays[physicalDisplayID] != nil else {
            return true
        }
        
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            Log.display.error("Failed to begin display configuration")
            return false
        }
        
        CGConfigureDisplayMirrorOfDisplay(config, physicalDisplayID, kCGNullDirectDisplay)
        
        guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else {
            Log.display.error("Failed to complete display configuration")
            CGCancelDisplayConfiguration(config)
            return false
        }
        
        // removeValue releases VirtualDisplayInfo (and its CGVirtualDisplay),
        // which happens after CGCompleteDisplayConfiguration above — correct ordering.
        virtualDisplays.removeValue(forKey: physicalDisplayID)

        Log.display.info("HiDPI disabled for display \(physicalDisplayID)")
        return true
    }
    
    func isHiDPIEnabled(for displayID: CGDirectDisplayID) -> Bool {
        return virtualDisplays[displayID] != nil
    }
    
    private func configureMirroring(physicalDisplayID: CGDirectDisplayID, virtualDisplayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            Log.display.error("Failed to begin display configuration")
            return false
        }
        
        let originalMain = CGMainDisplayID()
        
        if CGDisplayMirrorsDisplay(originalMain) == virtualDisplayID {
            CGConfigureDisplayMirrorOfDisplay(config, originalMain, kCGNullDirectDisplay)
        }
        
        let error = CGConfigureDisplayMirrorOfDisplay(config, physicalDisplayID, virtualDisplayID)
        if error != .success {
            Log.display.error("Failed to configure mirror: \(error.rawValue)")
            CGCancelDisplayConfiguration(config)
            return false
        }
        
        // Ensure the original main display keeps its origin if mirroring displaced it.
        if originalMain != virtualDisplayID {
            CGConfigureDisplayOrigin(config, originalMain, 0, 0)
        }
        
        guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else {
            Log.display.error("Failed to complete mirror configuration")
            CGCancelDisplayConfiguration(config)
            return false
        }
        
        Log.display.info("Mirroring configured: physical \(physicalDisplayID) mirrors virtual \(virtualDisplayID)")
        return true
    }
    
    func cleanup() {
        for (displayID, _) in virtualDisplays {
            _ = disableHiDPI(for: displayID)
        }
    }
}
