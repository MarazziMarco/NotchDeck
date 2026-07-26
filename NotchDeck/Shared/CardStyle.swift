import SwiftUI

/// Consistent dashboard card treatment: dark fill, hairline, rounded corners.
struct DashboardCardModifier: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignTokens.Palette.cardFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(DesignTokens.Palette.hairline, lineWidth: 0.6)
            )
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 12) -> some View {
        modifier(DashboardCardModifier(padding: padding))
    }
}

/// Small section header used across dashboards.
struct SectionLabel: View {
    let text: String
    var accessory: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            if let accessory {
                Text(accessory)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
