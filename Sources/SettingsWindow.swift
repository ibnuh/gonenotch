import SwiftUI
import Cocoa

// MARK: - Window Controller

class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())

        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "GoneNotch Settings"
        w.contentViewController = hosting
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = w
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General
            SettingsSection("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItemManager.setEnabled(newValue)
                    }
            }

            Divider()

            // Keyboard Shortcut
            SettingsSection("Keyboard Shortcut") {
                HStack {
                    Text("Toggle notch hiding")
                    Spacer()
                    ShortcutBadge("Cmd+Ctrl+N")
                }
            }

            Divider()

            // Display Info
            SettingsSection("Display") {
                InfoRow(label: "Resolution", value: resolution)
                InfoRow(label: "Refresh Rate", value: refreshRate)
                InfoRow(label: "Rendering", value: rendering)
            }

            Divider()

            // About
            SettingsSection("About") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GoneNotch")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Hides the MacBook notch by switching to a below-notch display resolution.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    Link("ibnuhx.com/gonenotch", destination: URL(string: "https://ibnuhx.com/gonenotch")!)
                        .font(.system(size: 12))
                    Spacer()
                    Text("MIT License")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 380)
        .fixedSize()
        .onAppear {
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var resolution: String {
        guard let screen = NSScreen.main else { return "Unknown" }
        return "\(Int(screen.frame.width)) x \(Int(screen.frame.height))"
    }

    private var refreshRate: String {
        let did = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(did) else { return "Unknown" }
        return "\(Int(mode.refreshRate)) Hz"
    }

    private var rendering: String {
        let did = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(did) else { return "Unknown" }
        return mode.pixelWidth > mode.width ? "Retina (HiDPI)" : "Standard"
    }
}

// MARK: - Reusable Components

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private struct ShortcutBadge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.3))
            )
    }
}
