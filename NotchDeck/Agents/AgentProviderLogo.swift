import SwiftUI

extension AgentAccentRole {
    /// Restrained accent colour — never a loud multi-colour logo palette.
    var color: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .codex: return Color(white: 0.82)
        case .gemini: return Color(red: 0.45, green: 0.62, blue: 0.95)
        case .copilot: return Color(white: 0.80)
        case .cursor: return Color(white: 0.75)
        case .aider: return Color(red: 0.55, green: 0.80, blue: 0.58)
        case .opencode: return Color(red: 0.60, green: 0.72, blue: 0.92)
        case .neutral: return DesignTokens.Palette.statusRunning
        }
    }
}

/// Data-driven provider mark. Uses a bundled asset when available (white logo on
/// dark backgrounds, black on light), otherwise an original monogram — never a
/// generic sparkle for a known provider. Falls back automatically if the asset
/// fails to load, without breaking layout.
struct AgentProviderLogo: View {
    let appearance: AgentProviderAppearance
    var size: CGFloat = 34
    /// Explicit background override; when nil the effective colour scheme decides.
    var darkBackground: Bool? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var onDark: Bool { darkBackground ?? (colorScheme == .dark) }

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityLabel(Text(appearance.accessibilityLabel))
    }

    @ViewBuilder private var content: some View {
        if let assetName = appearance.assetName(darkBackground: onDark),
           let nsImage = NSImage(named: assetName) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()                       // preserve aspect ratio, never stretch
                .padding(size * 0.08)
        } else {
            monogram
        }
    }

    private var monogram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(appearance.accent.color.opacity(0.16))
            Text(appearance.monogram)
                .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
                .foregroundStyle(appearance.accent.color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

extension AgentProviderLogo {
    init(session: AgentSession, size: CGFloat = 34, darkBackground: Bool? = nil) {
        self.init(appearance: session.appearance, size: size, darkBackground: darkBackground)
    }
}
