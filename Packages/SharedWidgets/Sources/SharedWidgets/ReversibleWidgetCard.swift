import SwiftUI
import AppKit

public enum ProductivityWidgetKind: String, CaseIterable, Sendable {
    case shelf, focus, music, countdown, habits
    public var title: String {
        switch self { case .shelf: return "Scaffale file"; case .focus: return "Pomodoro · Focus"; case .music: return "Musica"; case .countdown: return "Conto alla rovescia"; case .habits: return "Abitudini" }
    }
    public var symbol: String {
        switch self { case .shelf: return "tray.full"; case .focus: return "timer"; case .music: return "music.note"; case .countdown: return "flag.checkered"; case .habits: return "checkmark.circle" }
    }
}

public struct SharedProductivityWidget: View {
    private let kind: ProductivityWidgetKind
    private let library: SharedWidgetLibrary
    private let isEditing: Bool
    @MainActor public init(kind: ProductivityWidgetKind, library: SharedWidgetLibrary? = nil, isEditing: Bool = false) {
        self.kind = kind; self.library = library ?? .shared; self.isEditing = isEditing
    }
    public var body: some View {
        GeometryReader { geometry in
            let scale = max(0.01, min(1, geometry.size.width / 240, geometry.size.height / 240))
            card.frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
    private var card: some View {
        Group {
            switch kind {
            case .focus: SharedFocusCard(library: library, isEditing: isEditing)
            case .shelf: SharedShelfCard(library: library, isEditing: isEditing)
            case .music: SharedMusicCard(library: library, isEditing: isEditing)
            case .countdown: SharedCountdownCard(library: library, isEditing: isEditing)
            case .habits: SharedHabitsCard(library: library, isEditing: isEditing)
            }
        }
    }
}

struct ReversibleWidgetCard<Front: View, Settings: View>: View {
    let kind: ProductivityWidgetKind
    let accent: Color
    @Binding var flipped: Bool
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: () throws -> Void
    @ViewBuilder let front: () -> Front
    @ViewBuilder let settings: () -> Settings
    @State private var saveError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !flipped {
            VStack(alignment: .leading, spacing: 10) {
                header(back: false)
                front().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .transition(widgetFlipTransition(reduceMotion: reduceMotion))
            } else {
            VStack(alignment: .leading, spacing: 10) {
                header(back: true)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) { settings() }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 3)
                }
                .scrollIndicators(.hidden)
                if let saveError { Text(saveError).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
                HStack {
                    Button("Annulla") { flipped = false }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Button("Save") {
                        do { try onSave(); saveError = nil; flipped = false }
                        catch { saveError = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent).tint(accent.opacity(0.8))
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(16)
            .transition(widgetFlipTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.22), Color(red: 0.055, green: 0.075, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(RadialGradient(colors: [accent.opacity(0.1), .clear], center: .topLeading, startRadius: 0, endRadius: 230)).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.2), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.32), value: flipped)
        .allowsHitTesting(!isEditing)
        .onChange(of: isEditing) { _, editing in if editing { flipped = false } }
        .onChange(of: flipped) { _, showingSettings in
            if !showingSettings { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
    }
    private func header(back: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: back ? "slider.horizontal.3" : kind.symbol).foregroundStyle(accent)
            Text(back ? "Impostazioni" : kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 3)
            Button {
                if back { flipped = false } else { saveError = nil; onEdit() }
            } label: {
                Image(systemName: back ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .medium)).frame(width: 28, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
            .help(back ? "Annulla e torna al widget" : "Gira la card e configura")
            .accessibilityLabel(back ? "Annulla impostazioni" : "Impostazioni \(kind.title)")
        }
    }
}

struct WidgetColorPicker: View {
    let title: String
    @Binding var hex: String
    var body: some View {
        ColorPicker(title, selection: Binding(get: { TimetableColors.color(hex) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        }), supportsOpacity: false)
        .font(.system(size: 12))
    }
}

struct WidgetActionError: View {
    let message: String?
    var body: some View {
        if let message { Text(message).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
    }
}
