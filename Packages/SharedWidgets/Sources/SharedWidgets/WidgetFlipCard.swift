import SwiftUI
import AppKit

/// Reversible settings around an existing face, preserving its own colors and layout.
public struct WidgetFlipCard<Front: View, Settings: View>: View {
    private let title: String
    private let symbol: String
    @Binding private var flipped: Bool
    private let isEditing: Bool
    private let onEdit: () -> Void
    private let onSave: () throws -> Void
    private let front: () -> Front
    private let settings: () -> Settings
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(title: String, symbol: String, flipped: Binding<Bool>, isEditing: Bool = false,
                onEdit: @escaping () -> Void, onSave: @escaping () throws -> Void,
                @ViewBuilder front: @escaping () -> Front, @ViewBuilder settings: @escaping () -> Settings) {
        self.title = title; self.symbol = symbol; _flipped = flipped; self.isEditing = isEditing
        self.onEdit = onEdit; self.onSave = onSave; self.front = front; self.settings = settings
    }
    public var body: some View {
        ZStack {
            front()
                .overlay(alignment: .topTrailing) {
                    Button { error = nil; onEdit() } label: {
                        Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 26)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain).padding(12)
                    .accessibilityLabel("Impostazioni \(title)")
                }
                .opacity(flipped ? 0 : 1).allowsHitTesting(!flipped && !isEditing).accessibilityHidden(flipped)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Button { flipped = false } label: { Image(systemName: "xmark").frame(width: 26, height: 26) }
                        .buttonStyle(.plain).accessibilityLabel("Annulla impostazioni")
                }
                ScrollView {
                    settings().frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.visible)
                if let error { Text(error).foregroundStyle(.orange).font(.caption2).lineLimit(2) }
                HStack {
                    Button("Annulla") { flipped = false }.buttonStyle(.plain)
                    Spacer()
                    Button("Save") {
                        do { try onSave(); error = nil; flipped = false }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).tint(.indigo)
                }.font(.system(size: 12, weight: .semibold))
            }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .background(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.22), Color(red: 0.055, green: 0.075, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            .opacity(flipped ? 1 : 0).allowsHitTesting(flipped && !isEditing).accessibilityHidden(!flipped)
        }
        .rotation3DEffect(.degrees(reduceMotion || !flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.3), value: flipped)
        .onChange(of: isEditing) { _, editing in if editing { flipped = false } }
        .onChange(of: flipped) { _, value in if !value { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }
}
