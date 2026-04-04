import Foundation
import CoreGraphics

final class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published private(set) var virtualDisplays: [CGDirectDisplayID: VirtualDisplayInfo] = [:]
    private(set) var recentVirtualDisplayIDs: Set<CGDirectDisplayID> = []
    
    struct VirtualDisplayInfo {
        let virtualDisplay: CGVirtualDisplay
        let physicalDisplayID: CGDirectDisplayID
        let virtualDisplayID: CGDirectDisplayID
    }
    
    private init() {}
    
    func enableHiDPI(for physicalDisplayID: CGDirectDisplayID) -> Bool {
        if virtualDisplays[physicalDisplayID] != nil {
            Log.display.info("HiDPI already enabled for display \(physicalDisplayID)")
            return true
        }
        
        if CGDisplayIsInMirrorSet(physicalDisplayID) != 0 {
            Log.display.info("Display \(physicalDisplayID) is already in a mirror set")
            return true
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
        
        usleep(200_000)
        
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
        guard let info = virtualDisplays[physicalDisplayID] else {
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
        
        virtualDisplays.removeValue(forKey: physicalDisplayID)
        _ = info.virtualDisplay
        
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
        
        if originalMain != virtualDisplayID && CGMainDisplayID() == virtualDisplayID {
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
