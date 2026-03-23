import Cocoa
import CoreGraphics

class DisplayManager {
    private(set) var isEnabled = false
    private let stateKey = "GoneNotchEnabled"
    private var cachedDisplayID: CGDirectDisplayID?

    var savedStateIsEnabled: Bool {
        if UserDefaults.standard.object(forKey: stateKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: stateKey)
    }

    @discardableResult
    func enable() -> Bool {
        guard let did = resolveNotchDisplay() else { return false }
        guard let current = CGDisplayCopyDisplayMode(did) else { return false }

        if isBelowNotchMode(current, display: did) {
            isEnabled = true
            persistState()
            return true
        }

        guard let target = findBelowNotchMode(for: current, display: did) else { return false }

        if CGDisplaySetDisplayMode(did, target, nil) == .success {
            isEnabled = true
            persistState()
            return true
        }
        return false
    }

    @discardableResult
    func disable() -> Bool {
        guard let did = resolveNotchDisplay() else {
            isEnabled = false
            persistState()
            return true
        }
        guard let current = CGDisplayCopyDisplayMode(did) else {
            isEnabled = false
            persistState()
            return true
        }

        guard isBelowNotchMode(current, display: did),
              let target = findAboveNotchMode(for: current, display: did) else {
            isEnabled = false
            persistState()
            return true
        }

        if CGDisplaySetDisplayMode(did, target, nil) == .success {
            isEnabled = false
            persistState()
            return true
        }
        return false
    }

    @discardableResult
    func toggle() -> Bool {
        if isEnabled { return disable() } else { return enable() }
    }

    func syncState() {
        guard let did = resolveNotchDisplay(),
              let current = CGDisplayCopyDisplayMode(did) else { return }
        isEnabled = isBelowNotchMode(current, display: did)
    }

    // MARK: - Notch Display Resolution

    /// Finds the notch display ID. Caches the result since safeAreaInsets
    /// becomes 0 when the display is in below-notch mode.
    private func resolveNotchDisplay() -> CGDirectDisplayID? {
        if let cached = cachedDisplayID { return cached }

        // Primary: check safeAreaInsets (works in above-notch mode)
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                        cachedDisplayID = num
                        return num
                    }
                }
            }
        }

        // Fallback: check if main display has notch-paired modes
        // This works even when already in below-notch mode
        let did = CGMainDisplayID()
        if hasNotchPairedModes(display: did) {
            cachedDisplayID = did
            return did
        }

        return nil
    }

    private func hasNotchPairedModes(display: CGDirectDisplayID) -> Bool {
        guard let current = CGDisplayCopyDisplayMode(display),
              let allModes = allDisplayModes(display: display) else { return false }
        let isHiDPI = current.pixelWidth > current.width

        return allModes.contains { mode in
            guard mode.width == current.width,
                  (mode.pixelWidth > mode.width) == isHiDPI,
                  abs(mode.refreshRate - current.refreshRate) < 1.0 else { return false }
            let diff = abs(Int(mode.height) - Int(current.height))
            return diff >= 25 && diff <= 70
        }
    }

    // MARK: - Mode Lookup

    private func findBelowNotchMode(for current: CGDisplayMode, display: CGDirectDisplayID) -> CGDisplayMode? {
        return findPairedMode(for: current, display: display, wantShorter: true)
    }

    private func findAboveNotchMode(for current: CGDisplayMode, display: CGDirectDisplayID) -> CGDisplayMode? {
        return findPairedMode(for: current, display: display, wantShorter: false)
    }

    private func findPairedMode(for current: CGDisplayMode, display: CGDirectDisplayID, wantShorter: Bool) -> CGDisplayMode? {
        guard let allModes = allDisplayModes(display: display) else { return nil }
        let isHiDPI = current.pixelWidth > current.width

        return allModes.first { mode in
            guard mode.width == current.width,
                  (mode.pixelWidth > mode.width) == isHiDPI,
                  abs(mode.refreshRate - current.refreshRate) < 1.0 else { return false }

            let diff = wantShorter
                ? Int(current.height) - Int(mode.height)
                : Int(mode.height) - Int(current.height)
            return diff >= 25 && diff <= 70
        }
    }

    private func isBelowNotchMode(_ mode: CGDisplayMode, display: CGDirectDisplayID) -> Bool {
        return findAboveNotchMode(for: mode, display: display) != nil
    }

    // MARK: - Helpers

    private func allDisplayModes(display: CGDirectDisplayID) -> [CGDisplayMode]? {
        let opts: NSDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true]
        return CGDisplayCopyAllDisplayModes(display, opts) as? [CGDisplayMode]
    }

    private func persistState() {
        UserDefaults.standard.set(isEnabled, forKey: stateKey)
    }
}
