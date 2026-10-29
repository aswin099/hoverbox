import HoverboxCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.shakeEnabled) private var shakeEnabled = true
    @AppStorage(Prefs.sensitivity) private var sensitivity = ShakeDetector.Sensitivity.medium.rawValue
    @AppStorage(Prefs.keepAfterDragOut) private var keepAfterDragOut = false
    @State private var excluded = Prefs.excludedBundleIDs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Opening a shelf") {
                Toggle("Shake the pointer while dragging to open a shelf", isOn: $shakeEnabled)
                Picker("Shake sensitivity", selection: $sensitivity) {
                    Text("Low: big, deliberate shakes").tag(ShakeDetector.Sensitivity.low.rawValue)
                    Text("Medium").tag(ShakeDetector.Sensitivity.medium.rawValue)
                    Text("High: small shakes are enough").tag(ShakeDetector.Sensitivity.high.rawValue)
                }
                .disabled(!shakeEnabled)
                KeyboardShortcuts.Recorder("New shelf shortcut:", name: .newShelf)
            }

            Section {
                Toggle("Keep items on the shelf after dragging them out", isOn: $keepAfterDragOut)
            } header: {
                Text("Shelves")
            } footer: {
                Text("Hold Shift as you drop to keep items just for that drag. Pinned shelves always keep their items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if excluded.isEmpty {
                    Text("None. Shake works in every app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button("Remove") { setExcluded(excluded.filter { $0 != bundleID }) }
                    }
                }
                Menu("Add App…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { setExcluded(excluded + [id]) }
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Don't open shelves when shaking in")
            } footer: {
                Text("Useful for games and design tools where you drag a lot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Hoverbox asks for no permissions and never connects to the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func setExcluded(_ list: [String]) {
        excluded = Array(Set(list)).sorted()
        Prefs.excludedBundleIDs = excluded
    }
}

/// Icon and name for an app, looked up from its bundle ID.
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}
