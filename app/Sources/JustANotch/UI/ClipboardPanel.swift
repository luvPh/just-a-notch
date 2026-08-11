import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard").font(.headline)
                Spacer()
                Button {
                    store.clearUnpinned()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Xoá tất cả (giữ mục ghim)")
            }
            if store.items.isEmpty {
                Text("Chưa có gì được sao chép.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.items) { item in
                            ClipboardRow(item: item, store: store)
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            preview
            Spacer(minLength: 4)
            if hovering || item.pinned {
                Button { store.togglePin(item.id) } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).help("Ghim")
            }
            if hovering {
                Button { store.delete(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain).help("Xoá")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.10 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture { store.copyBack(item.id) }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case let .text(s):
            Text(s).lineLimit(2).font(.system(.callout, design: .monospaced))
        case .image:
            if let img = store.image(for: item) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 44, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }
}
