import SwiftUI

/// Bridges `NSVisualEffectView` so the expanded panel uses genuine macOS
/// materials instead of a flat fill.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

/// Reduce-motion aware modifier that applies an animation only when motion is
/// allowed. Reads the system setting and the user override.
struct MotionModifier: ViewModifier {
    let reduceMotion: Bool
    let animation: Animation
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: reduceMotion)
    }
}
