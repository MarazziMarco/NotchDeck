import SwiftUI
import Combine

/// Live diagnostics for the notch interaction system. Populated by the panel
/// controller and interaction coordinator; surfaced by an optional overlay when
/// the user enables "Interaction diagnostics" in Settings (off by default).
@MainActor
final class NotchDiagnostics: ObservableObject {
    @Published var enabled = false

    @Published var compactActivationRect: CGRect = .zero
    @Published var expandedInteractionRect: CGRect = .zero
    @Published var panelFrame: CGRect = .zero
    @Published var pointerLocation: CGPoint = .zero
    @Published var presentation: String = "compact"
    @Published var isPinned = false
    @Published var panelVisible = false
    @Published var panelLevel: Int = 0
    @Published var activeScreen: String = "-"
    @Published var lastOpenReason: String = "-"
    @Published var lastCloseReason: String = "-"

    // Width diagnostics (iteration 12)
    @Published var selectedTab: String = "-"
    @Published var tabProfile: String = "-"
    @Published var panelWidth: CGFloat = 0
    @Published var availableWidth: CGFloat = 0
    @Published var layoutClassName: String = "-"
    @Published var homeOneRow: Bool = true

    // Corner / background diagnostics
    @Published var outerClipRadius: CGFloat = 0
    @Published var contentClipRadius: CGFloat = 0
    @Published var backgroundLayers: String = "-"    // e.g. "opaque-black" / "material+surface"
    @Published var lowerCornerFill: String = "-"     // "black" or "material(grey)"

    // Compact live-activity diagnostics (Pomodoro countdown)
    @Published var compactActivity: String = "-"      // which activity is selected
    @Published var pomodoroRemaining: String = "-"    // formatted MM:SS
    @Published var leftWingFrame: CGRect = .zero
    @Published var rightWingFrame: CGRect = .zero
    @Published var compactTextFrame: CGRect = .zero   // where the MM:SS sits
    @Published var housingFrame: CGRect = .zero       // physical camera housing
    @Published var allocatedCompactWidth: CGFloat = 0

    func noteOpen(_ reason: String) { if enabled { lastOpenReason = reason } }
    func noteClose(_ reason: String) { if enabled { lastCloseReason = reason } }
}

/// Compact overlay printed on the expanded panel when diagnostics are enabled.
struct DiagnosticsOverlay: View {
    @ObservedObject var d: NotchDiagnostics
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            line("state", "\(d.presentation)  pinned=\(d.isPinned)  vis=\(d.panelVisible)  lvl=\(d.panelLevel)")
            line("pointer", "\(Int(d.pointerLocation.x)),\(Int(d.pointerLocation.y))  screen \(d.activeScreen)")
            line("compactRect", rect(d.compactActivationRect))
            line("expandedRect", rect(d.expandedInteractionRect))
            line("open", d.lastOpenReason)
            line("close", d.lastCloseReason)
            line("tab", "\(d.selectedTab) · \(d.tabProfile) · \(d.layoutClassName)")
            line("width", "panel \(Int(d.panelWidth)) / avail \(Int(d.availableWidth)) · \(d.homeOneRow ? "1-row" : "paged")")
            line("compact", "\(d.compactActivity) · MM:SS \(d.pomodoroRemaining) · alloc \(Int(d.allocatedCompactWidth))")
            line("wings", "L \(rect(d.leftWingFrame)) · R \(rect(d.rightWingFrame)) · txt \(rect(d.compactTextFrame))")
            line("clip", "outer \(Int(d.outerClipRadius)) · content \(Int(d.contentClipRadius)) · \(d.backgroundLayers)")
            line("corner", d.lowerCornerFill)
        }
        .padding(6)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.green)
        .allowsHitTesting(false)
    }
    private func line(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) { Text(k).foregroundStyle(.green.opacity(0.6)); Text(v) }
    }
    private func rect(_ r: CGRect) -> String {
        "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))"
    }
}
