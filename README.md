# BetterDisplayFree

A minimal, free, and open-source macOS menu bar app that enables HiDPI (Retina) scaling on external monitors.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## What It Does

BetterDisplayFree enables sharp, Retina-quality text and UI on external monitors that macOS doesn't natively offer HiDPI scaling for. It works by:

1. Creating a virtual display with 2x pixel backing (HiDPI enabled)
2. Mirroring your physical external monitor to this virtual display
3. macOS renders at 2x resolution internally, then downscales to your monitor's native resolution

**Result:** Crisp, sharp text instead of blurry non-HiDPI output.

### One click to activate!
<img src="https://github.com/user-attachments/assets/3d826ffc-e7bd-4a02-b22b-6dce441ad764" width="300" />
<br>

### Then, select your desired scale
<img src="https://github.com/user-attachments/assets/48fe436d-cc19-457b-b1cb-ff4cc59dab9a" width="540" />

*System Settings → Displays showing the virtual display with HiDPI scaling options*

## Features

- **One-click HiDPI toggle** for external monitors
- **Menu bar app** - no dock icon, stays out of your way
- **Auto-detects** connected external monitors
- **Multiple HiDPI resolutions** - choose from various "looks like" options in System Settings
- **Start at Login** option
- **Lightweight** - ~200KB binary, minimal resource usage

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- External monitor connected

## Installation

1. Download the latest `BetterDisplayFree-x.x.x.dmg` from [Releases](https://github.com/amitpdev/BetterDisplayFree/releases)
2. Open the DMG and drag `BetterDisplayFree.app` to your Applications folder
3. Launch from Applications (you may need to right-click → Open the first time)

## Usage

1. Launch the app - a display icon appears in your menu bar
2. Click the icon to see connected external monitors
3. Click on a monitor name to enable HiDPI (checkmark appears)
4. Click again to disable HiDPI
5. Adjust scaling in **System Settings → Displays** using the *Larger Text* to *More Space* slider

## Troubleshooting

**HiDPI option doesn't appear in System Settings:**
- Make sure you click on the "HiDPI Virtual Display" in System Settings → Displays
- Try the "Larger Text" to "More Space" slider

**Monitor flickers when enabling:**
- This is normal during display reconfiguration
- Should stabilize within 1-2 seconds

**App doesn't detect my monitor:**
- Click "Refresh Displays" in the menu
- Ensure the monitor is connected and recognized by macOS

## Limitations

- **Process must stay running** - The virtual display is owned by the app. If you quit, HiDPI is disabled.
- **Extra display visible** - System Settings shows the virtual display alongside your physical monitor.
- **Private API** - Uses undocumented Apple APIs that could break in future macOS versions (though stable since macOS 14).
- **GPU overhead** - Rendering at 2x resolution uses more GPU power.

## Credits

Written by **Amit Palomo**

Inspired by [BetterDisplay](https://betterdisplay.pro) - a more feature-rich commercial alternative.

## License

MIT License - Copyright (c) 2026 Amit Palomo

---

## For Developers

## Building from Source

```bash
git clone https://github.com/amitpdev/BetterDisplayFree.git
cd BetterDisplayFree
swift build -c release
```

The binary will be at `.build/release/BetterDisplayFree`.

### Creating a DMG Installer

```bash
./scripts/create-dmg.sh 1.0.0
```

## How It Works

BetterDisplayFree uses Apple's private `CGVirtualDisplay` API (available since macOS 14) to create a virtual display with HiDPI support. The physical monitor is configured to mirror this virtual display, which tricks macOS into using its Retina rendering pipeline.

### Technical Details

| Aspect | Implementation |
|--------|----------------|
| API | Private `CGVirtualDisplay*` CoreGraphics classes |
| HiDPI Trigger | `CGVirtualDisplaySettings.hiDPI = 1` |
| Resolution | Virtual: 2x backing, Physical: native resolution |
| Mirroring | `CGConfigureDisplayMirrorOfDisplay()` |

### Generated HiDPI Modes

For a 2560×1440 monitor, the app creates these "looks like" resolutions:

- 1920×1080 (HiDPI) - renders at 3840×2160
- 1600×900 (HiDPI) - renders at 3200×1800
- 1440×810 (HiDPI) - renders at 2880×1620
- 1280×720 (HiDPI) - renders at 2560×1440
- And more...

## Logging

BetterDisplayFree uses Apple's unified logging system (`os.log`). View logs with:

```bash
log stream --predicate 'subsystem == "com.amitpalomo.BetterDisplayFree"' --level debug
```

Log categories:
- `UI` - User interface events
- `Display` - Virtual display creation and configuration
- `Monitor` - Monitor detection and enumeration
- `App` - Application lifecycle

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.
