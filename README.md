# GoneNotch

A native macOS menu bar app that hides the MacBook notch by switching to a below-notch display resolution. Uses the public `CGDisplaySetDisplayMode` API to toggle between paired display modes.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **One-click notch hiding**: switches to a below-notch resolution that excludes the notch area
- **Global hotkey**: Cmd+Ctrl+N to toggle from anywhere
- **Menu bar app**: status icon with quick toggle, resolution info, and settings
- **Launch at Login**: via SMAppService (macOS 13+)
- **Auto-update**: Sparkle framework with EdDSA-signed updates
- **State persistence**: remembers your preference across launches and reboots
- **Universal binary**: runs natively on both Apple Silicon and Intel Macs
- **Minimal resources**: no background processes, no overlays, just a display mode switch

## Requirements

- macOS 12.0 (Monterey) or later
- MacBook with a notch (14" or 16" models, 2021+)
- Xcode Command Line Tools (`xcode-select --install`)

## Building

```bash
./build.sh
```

This compiles a universal binary (arm64 + x86_64) app bundle to `build/GoneNotch.app`.

## Running

```bash
open build/GoneNotch.app
```

The app runs in the menu bar (no Dock icon). Click the status icon to toggle notch hiding, access settings, or quit.

## How It Works

macOS provides paired display modes for notch MacBooks. Each resolution has an "above notch" and "below notch" variant that differs by 25-70 points in height. GoneNotch detects these paired modes and switches between them using `CGDisplaySetDisplayMode`.

For example, on a 16" MacBook Pro at 1800x1169 (above notch), GoneNotch switches to 1800x1125 (below notch), which shifts the usable display area below the notch.

## Project Structure

```
Sources/
  main.swift              - Entry point
  AppDelegate.swift       - Menu bar app, hotkey, Sparkle updates
  DisplayManager.swift    - Display mode switching logic
  LoginItemManager.swift  - Launch at Login (SMAppService)
  SettingsWindow.swift    - SwiftUI settings view
Resources/
  Info.plist              - App metadata (template with build vars)
  GoneNotch.entitlements  - Entitlements for hardened runtime
Frameworks/
  Sparkle.framework/      - Auto-update framework
  bin/                    - Sparkle signing tools
```

## License

MIT
