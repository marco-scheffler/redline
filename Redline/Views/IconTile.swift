import SwiftUI

/// iOS/macOS-settings-style tinted rounded square with an SF Symbol.
/// Lights up in its accent colour while the related test runs.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var active: Bool = false
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.20)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(active ? Color.white : tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(active ? 0 : 0.35), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(active ? 0.5 : 0), radius: active ? 6 : 0)
            .animation(.easeInOut(duration: 0.25), value: active)
    }
}

/// Small rounded info pill with a leading colour dot (used in the header).
struct InfoChip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
