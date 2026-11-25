# PowerSaver for macOS

A lightweight, event-driven macOS menu bar app and battery optimization toolkit that automatically suspends unused background agents, helpers, and windowless idle apps whenever your Mac runs on battery power.

## Features

- **Zero-CPU Idle Power Monitoring**: Uses IOKit (`IOPSNotificationCreateRunLoopSource`) to react instantaneously when unplugging or plugging in the charger — no background polling timers.
- **Automatic Mode Switching**:
  - **On Battery (Power Saver ON)**: Suspends unused background updaters and heavy helpers (`ai.hermes.gateway`, `ollama`, `llama-server`, `figma_agent`, `steam_osx`, `iwallpaper`, `LyricsXHelper`, idle Adobe background helpers), enforces App Nap, and disables Chrome background mode.
  - **On AC Power (Normal Mode)**: Automatically restores only the agents and apps that PowerSaver previously suspended.
- **Windowless Idle App Detector**: Inspects open windows via `CGWindowListCopyWindowInfo` when opening the menu (ignoring minimized windows and windows on other Spaces) and lets you close apps left running in RAM with no open windows — manually or automatically on unplug.
- **Live Battery & System Telemetry**: Shows current battery percentage, estimated time remaining, Low Power Mode state, and suspended item list directly in the menu bar.
- **Extreme Mode**: Optionally quits menu bar utilities (`Atoll`, `Macs Fan Control`, `Rectangle`, `Maccy`) on battery while keeping security tools (`LuLu`) untouched.
- **System-Level `pmset` Optimization**: Includes `scripts/system-optimize.sh` (also runnable via native Touch ID / administrator prompt from the menu) to tune `displaysleep`, `tcpkeepalive`, `standbydelayhigh`, `standbydelaylow`, and disable idle third-party system updaters.

## Installation

### Option 1: macOS Installer Package (`.pkg` / `.dmg` / `.zip`)

Download the latest Universal (`Apple Silicon + Intel`) package from the [Releases](https://github.com/Rafli161102/powersaver-mac/releases) page:

- **`PowerSaver-1.2.pkg`**: Double-click to install `/Applications/PowerSaver.app` and automatically register the auto-start LaunchAgent.
- **`PowerSaver-1.2.dmg`**: Open and drag `PowerSaver.app` into `Applications`.
- **`PowerSaver-1.2-universal.zip`**: Extract and move `PowerSaver.app` to `Applications`.

> **Note on Gatekeeper**: Releases are ad-hoc signed. If macOS warns about an unidentified developer, right-click `PowerSaver.app` → **Open**, or run:
> ```zsh
> xattr -dr com.apple.quarantine /Applications/PowerSaver.app
> ```

### Option 2: One-Line Terminal Install (No Manual Clone Needed)

```zsh
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Rafli161102/powersaver-mac/main/install.sh)"
```

### Option 3: Homebrew

```zsh
brew tap Rafli161102/powersaver-mac https://github.com/Rafli161102/powersaver-mac.git
brew install --HEAD powersaver
powersaver
```

### Option 4: Build from Source or Create Packages Locally

```zsh
git clone https://github.com/Rafli161102/powersaver-mac.git
cd powersaver-mac
./install.sh
```

To build distributable Universal packages (`.zip`, `.pkg`, `.dmg`, and `checksums.txt`) into `dist/`:

```zsh
./package.sh
# or: make package
```

Once installed, look for the **bolt** (`⚡`, Normal Mode) or **leaf** (`🍃`, Power Saver Mode) icon in the top-right macOS menu bar.

### Optional: System-Level Battery Tuning (`sudo`)

Run from the menu bar (**Apply Battery pmset Optimization (sudo)...**) or directly in Terminal:

```zsh
sudo ./scripts/system-optimize.sh
```

This sets battery (`pmset -b`) parameters to:
- `lowpowermode 1`, `powernap 0`, `proximitywake 0`, `womp 0`, `tcpkeepalive 0`
- `displaysleep 3`, `disksleep 5`, `sleep 1`
- `standby 1`, `standbydelayhigh 3600`, `standbydelaylow 900`, `ttyskeepawake 0`

## Repository Structure

```text
powersaver-mac/
├── install.sh                               # Universal build + local LaunchAgent installer (local or curl)
├── package.sh                               # Builds Universal .app, .zip, .pkg, and .dmg in dist/
├── uninstall.sh                             # Restores suspended items and removes PowerSaver.app
├── Makefile                                 # Convenience targets (build, install, package, uninstall)
├── Formula/
│   └── powersaver.rb                        # Homebrew formula
├── .github/workflows/
│   └── release.yml                          # GitHub Actions CI to publish Universal release packages
├── src/
│   └── PowerSaverApp.swift                  # Native Swift menu bar app (AppKit + IOKit)
├── scripts/
│   ├── power-saver.sh                       # Suspends idle background agents and helper processes
│   ├── normal-mode.sh                       # Restores previously suspended agents and apps
│   └── system-optimize.sh                   # Root pmset battery tuning & system updater cleanup
└── resources/
    ├── Info.plist                           # App bundle metadata (LSUIElement, sudden termination, single instance)
    ├── com.rafli.powersaver.plist.template  # User LaunchAgent template
    └── pkg-scripts/postinstall              # LaunchAgent setup script for .pkg installer
```

## Requirements

- macOS 13.0 or later (Apple Silicon & Intel Universal)
- Xcode Command Line Tools (`swiftc`, `codesign`) — only needed if building from source (`xcode-select --install`)

## Menu Bar Controls

| Menu Item | Shortcut | Description |
|---|---|---|
| **Power Saver Mode** | `⌘I` | Manually toggle Power Saver Mode on or off |
| **Auto-Switch on Unplug** | `⌘A` | Automatically switch modes when unplugging/plugging charger |
| **Auto-Close Windowless Apps** | `⌘W` | Close regular apps with zero open windows when entering Power Saver Mode |
| **Extreme Mode** | `⌘E` | Also quit configured menu bar utilities in Power Saver Mode |
| **Windowless Idle Apps** | — | Inspect and close individual or all windowless apps currently in memory |
| **Suspended Items** | — | View background agents/apps currently paused by PowerSaver |
| **Clean Background Now** | `⌘R` | Immediately run background cleanup |

## Uninstallation

```zsh
./uninstall.sh
```

To restore default macOS `pmset` battery settings if you ran `system-optimize.sh`:

```zsh
sudo pmset -b displaysleep 10 disksleep 10 tcpkeepalive 1 standbydelayhigh 86400 standbydelaylow 10800 ttyskeepawake 1
```
