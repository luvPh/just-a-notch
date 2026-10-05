import SwiftUI

/// Clipboard dạng dải thẻ ngang: ô tìm kiếm (hỗ trợ `@link`, `@image`…),
/// chip lọc theo loại, rồi các thẻ xem trước với app nguồn · thời gian · dung lượng.
struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore

    @State private var chip: ClipboardFilter.Chip = .all
    @State private var query = ""
    @State private var copiedID: UUID?

    private var filtered: [ClipboardItem] {
        ClipboardFilter.apply(store.items, chip: chip, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if filtered.isEmpty {
                Text(store.items.isEmpty ? "Chưa có gì được sao chép." : "Không có mục nào khớp.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(filtered) { item in
                            ClipboardCard(item: item, store: store, copied: copiedID == item.id) {
                                store.copyBack(item.id)
                                copiedID = item.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    if copiedID == item.id { copiedID = nil }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 2)
        .animation(.easeInOut(duration: 0.18), value: chip)
    }

    // MARK: Header — search + chips

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Tìm, hoặc @link…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(query.hasPrefix("@") ? Color.pink : .white)
            }
            .padding(.horizontal, 8).frame(width: 150, height: 22)
            .background(Capsule().fill(.white.opacity(0.09)))

            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    chipButton(.all, "Tất cả", "clock")
                    chipButton(.pinned, "Ghim", "pin")
                    ForEach(ClipboardCategory.allCases, id: \.self) { c in
                        chipButton(.category(c), c.label, c.symbol)
                    }
                }
            }
            .scrollIndicators(.never)

            Button { store.clearUnpinned() } label: {
                Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.09)))
            }
            .buttonStyle(.plain).help("Xoá tất cả (giữ mục ghim)")
        }
    }

    private func count(_ c: ClipboardFilter.Chip) -> Int {
        ClipboardFilter.apply(store.items, chip: c, query: "").count
    }

    private func chipButton(_ c: ClipboardFilter.Chip, _ title: String, _ symbol: String) -> some View {
        let on = chip == c
        return Button { chip = c } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .semibold))
                Text("\(count(c))").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(on ? .black.opacity(0.45) : .white.opacity(0.4))
            }
            .foregroundStyle(on ? .black : .white.opacity(0.85))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(on ? .white : .white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

private struct ClipboardCard: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    let copied: Bool
    let onTap: () -> Void
    @State private var hovering = false

    private var category: ClipboardCategory { ClipboardCategory.of(item) }

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            if category != .image && category != .color {
                textPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 28)
            } else if category == .color {
                Text(item.plainText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            footer
        }
        .frame(width: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.35 : 0.08), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { if hovering { actions } }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var background: some View {
        switch category {
        case .image:
            if let img = store.image(for: item) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            } else {
                Color(white: 0.13).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        case .color:
            if let c = ClipboardColor.parse(item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Color(red: c.r, green: c.g, blue: c.b)
            } else { Color(white: 0.13) }
        default:
            Color(white: 0.13)
        }
    }

    @ViewBuilder private var textPreview: some View {
        let s = item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch category {
        case .code:
            Text(s).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1))
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Label(URL(string: s)?.host ?? s, systemImage: "link")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
                Text(s).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        default:
            Text(s).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.92))
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let icon = store.appIcon(for: item) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            }
            if copied {
                Label("Đã chép", systemImage: "checkmark").font(.system(size: 9.5, weight: .semibold))
            } else {
                Text(Self.ago(item.createdAt)).font(.system(size: 9.5, weight: .semibold))
            }
            Spacer(minLength: 2)
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
            Text(Self.size(store.byteSize(of: item))).font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 8).frame(height: 24)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var actions: some View {
        HStack(spacing: 3) {
            Button { store.togglePin(item.id) } label: {
                Image(systemName: item.pinned ? "pin.slash.fill" : "pin.fill")
            }.help(item.pinned ? "Bỏ ghim" : "Ghim")
            Button { store.delete(item.id) } label: { Image(systemName: "xmark") }.help("Xoá")
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
        .padding(.horizontal, 7).frame(height: 20)
        .background(Capsule().fill(.black.opacity(0.65)))
        .padding(5)
        .transition(.opacity)
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "Vừa xong" }
        if s < 3600 { return "\(s / 60) phút trước" }
        if s < 86400 { return "\(s / 3600) giờ trước" }
        return "\(s / 86400) ngày trước"
    }

    static func size(_ b: Int) -> String {
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return "\(b / 1024) KB" }
        return String(format: "%.1f MB", Double(b) / 1_048_576)
    }
}
