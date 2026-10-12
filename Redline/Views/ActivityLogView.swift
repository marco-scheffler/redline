import SwiftUI

struct ActivityLogView: View {
    let log: ActivityLog

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(log.entries) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(entry.time)
                                        .foregroundStyle(.tertiary)
                                    Text(entry.message)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(height: 92)
                    .onChange(of: log.entries.count) {
                        if let last = log.entries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }
}
