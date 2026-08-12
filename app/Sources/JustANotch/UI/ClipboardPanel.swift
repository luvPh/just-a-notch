import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore

    @State private var hoveringPanel = false

    var body: some View {
        Group {
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
                .scrollIndicators(.never)
                // Nút xoá-tất-cả nổi góc trên-phải, chỉ hiện khi rê chuột vào panel,
                // không chiếm 1 hàng header riêng.
                .overlay(alignment: .topTrailing) {
                    if hoveringPanel {
                        Button { store.clearUnpinned() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .help("Xoá tất cả (giữ mục ghim)")
                        .padding(2)
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding(4)
        .onHover { hoveringPanel = $0 }
        .animation(.easeInOut(duration: 0.15), value: hoveringPanel)
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
        .foregroundStyle(.black)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 1.0 : 0.92)))
        .contentShape(Rectangle())
        .onTapGesture { store.copyBack(item.id) }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case let .text(s):
            Text(s).lineLimit(1).truncationMode(.tail)
                .font(.system(size: 11.5, design: .monospaced))
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
