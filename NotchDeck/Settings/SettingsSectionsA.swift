import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SettingsGroup(title: "Notch") {
            Toggle("Open on hover", isOn: $settings.settings.hoverToOpen)
            HStack {
                Text("Open delay")
                Slider(value: $settings.settings.openDelay, in: 0...1)
                Text(String(format: "%.2fs", settings.settings.openDelay)).monospacedDigit().frame(width: 48)
            }
            HStack {
                Text("Close delay")
                Slider(value: $settings.settings.closeDelay, in: 0...2)
                Text(String(format: "%.2fs", settings.settings.closeDelay)).monospacedDigit().frame(width: 48)
            }
            Picker("Default face", selection: $settings.settings.defaultFace) {
                Text("Utilities").tag(NotchFace.utilities)
                Text("Agents").tag(NotchFace.agents)
            }
            Picker("Display", selection: $settings.settings.monitorSelection) {
                ForEach(MonitorSelection.allCases) { Text($0.label).tag($0) }
            }
        }
        SettingsGroup(title: "Startup") {
            Toggle("Launch at login", isOn: Binding(
                get: { settings.settings.launchAtLogin },
                set: { settings.settings.launchAtLogin = $0; LoginItemService.setEnabled($0) }))
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        SettingsGroup(title: "Background & Home") {
            Picker("Background intensity", selection: $settings.settings.backgroundIntensity) {
                ForEach(BackgroundIntensity.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Show Home design dividers", isOn: $settings.settings.showHomeDividers)
            Text("Accent colours come from the widgets; the panel base stays near-black.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup(title: "Quick Note (Home)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paper colour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    ForEach(NoteColor.allCases) { preset in
                        noteColourSwatch(preset)
                    }
                }
                ColorPicker(
                    "Custom colour",
                    selection: customNoteColour,
                    supportsOpacity: false
                )
                .accessibilityLabel("Custom Quick Note colour")
                .accessibilityHint("Choose any paper colour for Quick Note")
            }
            Picker("Paper style", selection: $settings.settings.paperStyleIntensity) {
                ForEach(PaperStyleIntensity.allCases) { Text($0.label).tag($0) }
            }
            Text("The Home note is a local-only sticky note. No cloud, no system Notes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsGroup(title: "Mirror") {
            Toggle("Circular mirror on Home", isOn: $settings.settings.mirrorCircular)
            Toggle("Zoomed-in preview (better for quick checks)", isOn: $settings.settings.mirrorZoomed)
        }
        SettingsGroup(title: "Layout") {
            Picker("Panel width", selection: $settings.settings.panelWidthPreference) {
                ForEach(PanelWidthPreference.allCases) { Text($0.label).tag($0) }
            }
            Picker("Dashboard density", selection: $settings.settings.dashboardDensity) {
                ForEach(DashboardDensity.allCases) { Text($0.label).tag($0) }
            }
            Picker("Tab labels", selection: $settings.settings.tabLabelMode) {
                ForEach(TabLabelMode.allCases) { Text($0.label).tag($0) }
            }
            Picker("Maximum Home modules", selection: Binding(
                get: { settings.settings.maxHomeModulesPreference ?? 0 },
                set: { settings.settings.maxHomeModulesPreference = $0 == 0 ? nil : $0 })) {
                Text("Automatic").tag(0)
                Text("3").tag(3); Text("4").tag(4); Text("5").tag(5)
            }
            Toggle("Follow the display with the pointer", isOn: $settings.settings.followActiveDisplay)
            Text("Width and height always stay within safe screen margins; sizing is derived from the actual logical screen geometry, not the Mac model.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        SettingsGroup(title: "Motion & Contrast") {
            Toggle("Reduce motion (override system)", isOn: $settings.settings.reduceMotionOverride)
            Text("Animations are also reduced automatically when macOS “Reduce Motion” is on.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var customNoteColour: Binding<Color> {
        Binding(
            get: { settings.settings.resolvedNotePaperColor.color },
            set: { newColour in
                guard let persisted = NotePaperColor(color: newColour) else { return }
                settings.settings.selectCustomNoteColor(persisted)
            }
        )
    }

    private func noteColourSwatch(_ preset: NoteColor) -> some View {
        let selected = settings.settings.noteCustomColor == nil
            && settings.settings.noteColor == preset
        let ink = preset.paperComponents.inkColor
        return Button {
            settings.settings.selectNotePreset(preset)
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(preset.paper)
                .frame(width: 28, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            selected ? Color.accentColor : Color.white.opacity(0.16),
                            lineWidth: selected ? 3 : 1
                        )
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ink)
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.label) Quick Note colour")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Use \(preset.label.lowercased()) paper")
    }
}

/// The Modules destination in Settings. See `ModulesScreen`.
struct ModulesSettingsView: View {
    var body: some View { ModulesScreen() }
}

struct ClipboardSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var clipboard: ClipboardService

    var body: some View {
        SettingsGroup(title: "Clipboard History") {
            Stepper("Maximum items: \(settings.settings.clipboardMaxItems)",
                    value: $settings.settings.clipboardMaxItems, in: 10...500, step: 10)
                .onChange(of: settings.settings.clipboardMaxItems) { _, v in
                    clipboard.updateMaxItems(v)
                }
            Toggle("Show indicator in compact notch", isOn: $settings.settings.clipboardShowCompactIndicator)
            Toggle("Pause monitoring", isOn: Binding(
                get: { settings.settings.clipboardMonitoringPaused },
                set: { settings.settings.clipboardMonitoringPaused = $0; clipboard.isPaused = $0 }))
            Toggle("Private mode (don't capture)", isOn: Binding(
                get: { settings.settings.clipboardPrivateMode },
                set: { settings.settings.clipboardPrivateMode = $0; clipboard.isPrivateMode = $0 }))
            Button("Clear history", role: .destructive) { clipboard.clearAll() }
            Text("Clipboard history is stored only on this Mac. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FileShelfSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var shelf: FileShelfStore
    var body: some View {
        SettingsGroup(title: "File Shelf") {
            Picker("When you drop a file", selection: Binding(
                get: { settings.settings.fileShelfIntakeMode },
                set: { settings.settings.fileShelfIntakeMode = $0; shelf.intakeMode = $0 })) {
                ForEach(FileShelfIntakeMode.allCases) { Text($0.label).tag($0) }
            }
            if settings.settings.fileShelfIntakeMode == .moveIntoShelf {
                Text("The item is moved from its current folder into NotchDeck and stored safely until you place it somewhere else. It survives quitting and relaunching.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The original stays exactly where it is. The shelf only holds a reference to it.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("After dragging out", selection: Binding(
                    get: { settings.settings.fileShelfRetentionPolicy },
                    set: { settings.settings.fileShelfRetentionPolicy = $0; shelf.retentionPolicy = $0 })) {
                    ForEach(FileShelfRetentionPolicy.allCases) { Text($0.label).tag($0) }
                }
                Picker("Keep references", selection: Binding(
                    get: { settings.settings.fileShelfRetention },
                    set: { settings.settings.fileShelfRetention = $0; shelf.retention = $0 })) {
                    ForEach(FileShelfRetention.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}

struct MirrorSettingsView: View {
    @EnvironmentObject private var mirror: MirrorService
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        SettingsGroup(title: "Mirror") {
            Text("The camera starts only while Mirror is open and stops the moment you close it. No recording, no network.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Orientation", selection: Binding(
                get: { settings.settings.mirrorOrientation },
                set: { settings.settings.mirrorOrientation = $0 })) {
                ForEach(MirrorOrientation.allCases) { Text($0.label).tag($0) }
            }
            Button("Refresh cameras") { mirror.refreshCameras() }
            if mirror.availableCameras.isEmpty {
                Text("No cameras detected.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(mirror.availableCameras, id: \.uniqueID) { cam in
                    Text("• \(cam.localizedName)").font(.caption)
                }
            }
        }
    }
}

struct PomodoroSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pomodoro: PomodoroService
    var body: some View {
        SettingsGroup(title: "Pomodoro") {
            Toggle("Enable Pomodoro module", isOn: $settings.settings.pomodoroEnabled)
            Picker("Widget style", selection: $settings.settings.pomodoroWidgetStyle) {
                ForEach(PomodoroWidgetStyle.allCases) { Text($0.label).tag($0) }
            }
            Stepper("Focus: \(settings.settings.pomodoroWorkMinutes) min",
                    value: $settings.settings.pomodoroWorkMinutes, in: 5...90, step: 5)
            Stepper("Short break: \(settings.settings.pomodoroShortBreakMinutes) min",
                    value: $settings.settings.pomodoroShortBreakMinutes, in: 1...30)
            Stepper("Long break: \(settings.settings.pomodoroLongBreakMinutes) min",
                    value: $settings.settings.pomodoroLongBreakMinutes, in: 5...45, step: 5)
            Stepper("Sessions before long break: \(settings.settings.pomodoroSessionsBeforeLongBreak)",
                    value: $settings.settings.pomodoroSessionsBeforeLongBreak, in: 2...8)
                .onChange(of: settings.settings.pomodoroSessionsBeforeLongBreak) { _, _ in syncConfig() }
                .onChange(of: settings.settings.pomodoroWorkMinutes) { _, _ in syncConfig() }
        }
    }
    private func syncConfig() {
        pomodoro.updateConfig(PomodoroConfig(
            workMinutes: settings.settings.pomodoroWorkMinutes,
            shortBreakMinutes: settings.settings.pomodoroShortBreakMinutes,
            longBreakMinutes: settings.settings.pomodoroLongBreakMinutes,
            sessionsBeforeLongBreak: settings.settings.pomodoroSessionsBeforeLongBreak))
    }
}
