import SwiftUI

/// Per-resource accent colours, drawn from the system palette so they match macOS.
enum Accent {
    static let cpu = Color.blue
    static let gpu = Color.cyan
    static let memory = Color.purple
    static let disk = Color.orange
    static let monitor = Color.blue
    static let go = Color.green
    static let stop = Color.red
}

/// A material-backed rounded card with a hairline border — the building block
/// every section sits in.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Section header row: tinted SF Symbol tile + title + trailing status text.
struct CardHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let status: String
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, active: active)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(active ? tint : Color.secondary)
                .lineLimit(1)
        }
    }
}
