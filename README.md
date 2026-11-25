# PowerSaver for macOS

A lightweight, event-driven macOS menu bar app and battery optimization toolkit that adapts to **any Mac** (Apple Silicon or Intel, MacBook or desktop) and lets every user customize which apps, background agents, and helpers are suspended on battery power.

## Features

- **Zero-CPU Idle Power Monitoring**: Uses IOKit (`IOPSNotificationCreateRunLoopSource`) to react instantaneously when unplugging or plugging in the charger — no background polling timers.
- **Adapts to Any User's Mac**:
  - Automatically discovers your `~/Library/LaunchAgents` so you can check/uncheck which background agents should pause on battery directly from the menu bar.
  - Dynamically lists currently running apps so you can add/remove apps in **Extreme Mode** or **Protect** any app from ever being auto-closed.
  - Works on both **MacBooks** (with live battery percentage & time remaining) and **Desktop Macs** (Mac mini / Mac Studio / iMac).
- **Windowless Idle App Detector**: Inspects open windows via `CGWindowListCopyWindowInfo` when opening the menu (ignoring minimized windows and windows on other Spaces) and lets you close apps left running in RAM with no open windows — manually or automatically on unplug.
- **Persistent User Configuration (`config.json`)**: Stored at `~/Library/Application Support/PowerSaver/config.json` and editable directly via **Open Config (JSON)...** or the menu bar toggles.
- **System-Level `pmset` Optimization (Apple Silicon & Intel Safe)**: `scripts/system-optimize.sh` applies each `pmset -b` key individually so unsupported Intel-only flags never cause failures on Apple Silicon Macs, and includes `--restore` to revert anytime.

## Installation

### Option 1: macOS Installer Package (`.pkg` / `.dmg` / `.zip`)

Download the latest Universal (`Apple Silicon + Intel`) package from the [Releases](https://github.com/Rafli161102/powersaver-mac/releases) page:

- **`PowerSaver-1.3.pkg`**: Double-click to install `/Applications/PowerSaver.app` and automatically register the auto-start LaunchAgent.
- **`PowerSaver-1.3.dmg`**: Open and drag `PowerSaver.app` into `Applications`.
- **`PowerSaver-1.3-universal.zip`**: Extract and move `PowerSaver.app` to `Applications`.

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

To restore standard macOS `pmset` battery defaults:

```zsh
sudo ./scripts/system-optimize.sh --restore
```

## Menu Bar Controls

| Menu Item | Shortcut | Description |
|---|---|---|
| **Power Saver Mode** | `⌘I` | Manually toggle Power Saver Mode on or off |
| **Auto-Switch on Unplug** | `⌘A` | Automatically switch modes when unplugging/plugging charger |
| **Auto-Close Windowless Apps** | `⌘W` | Close regular apps with zero open windows when entering Power Saver Mode |
| **Extreme Mode** | `⌘E` | Quit apps you selected in **Extreme Mode Apps** when Power Saver Mode is active |
| **Windowless Idle Apps** | — | Quit individual/all windowless apps or mark an app as Protected |
| **Background Agents** | — | Auto-discovered `~/Library/LaunchAgents` + toggles for updaters/helpers |
| **Extreme Mode Apps** | — | Dynamically populated list of apps to quit in Extreme Mode |
| **Protected Apps** | — | Bundle IDs never auto-closed (click any entry to unprotect) |
| **Clean Background Now** | `⌘R` | Immediately run background cleanup |
| **Open Config (JSON)...** | `⌘,` | Open `config.json` in your default editor |

## Uninstallation

```zsh
./uninstall.sh
```
