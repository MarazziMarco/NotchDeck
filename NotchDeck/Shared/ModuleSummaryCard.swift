import SwiftUI

/// Reusable summary card for small/medium Home dashboard sizes. Keeps modules
/// visually consistent without each re-implementing the same layout.
struct ModuleSummaryCard: View {
    let icon: String
    let title: String
    var value: String?
    var subtitle: String?
    var tint: StatusTint = .neutral
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint == .neutral ? DesignTokens.Palette.secondaryText : tint.color)
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Spacer(minLength: 0)
            }
            if let value {
                Text(value)
                    .font(.system(size: compact ? 20 : 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                    .lineLimit(1)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .lineLimit(compact ? 1 : 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
