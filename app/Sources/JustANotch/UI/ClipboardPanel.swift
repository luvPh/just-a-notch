import SwiftUI

/// Clipboard dạng dải thẻ ngang: ô tìm kiếm (hỗ trợ `@link`, `@image`…),
/// chip lọc theo loại, rồi các thẻ xem trước với app nguồn · thời gian · dung lượng.
struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore

    @State private var chip: ClipboardFilter.Chip = .all
    @State private var query = ""
    @State private var copiedID: UUID?
    /// Lộ dần: false khi vừa mở tab / đổi bộ lọc → các thẻ lần lượt hiện sau khi notch nở xong.
    @State private var revealed = false
    @State private var revealTask: DispatchWorkItem?
    @State private var headerShown = false   // chỉ hiện dần 1 lần khi mở tab

    private var filtered: [ClipboardItem] {
        ClipboardFilter.apply(store.items, chip: chip, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .opacity(headerShown ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: headerShown)
            if filtered.isEmpty {
                NotchEmptyState(symbol: store.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                                title: store.items.isEmpty ? "Chưa có gì được sao chép" : "Không có mục nào khớp",
                                hint: store.items.isEmpty ? "Copy bất cứ thứ gì, nó sẽ hiện ở đây" : nil)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                            ClipboardCard(item: item, store: store, copied: copiedID == item.id) {
                                store.copyBack(item.id)
                                copiedID = item.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    if copiedID == item.id { copiedID = nil }
                                }
                            }
                            // Lần lượt: mỗi thẻ trễ 45ms, nổi lên 10pt + mờ → rõ, lò xo êm.
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 10)
                            .scaleEffect(revealed ? 1 : 0.96, anchor: .bottom)
                            .animation(.spring(response: 0.42, dampingFraction: 0.86)
                                .delay(revealed ? Double(min(i, 8)) * 0.045 : 0), value: revealed)
                        }
                    }
                    .padding(1)   // chừa chỗ cho viền 1pt khỏi bị cắt
                    .padding(.horizontal, 10)
                    .background(VerticalWheelToHorizontal())   // lăn chuột dọc → cuộn ngang
                }
                .scrollIndicators(.never)
                .edgeFade(.horizontal, 22)
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 2)
        .onAppear {
            reveal(after: 0.32)                    // chờ notch nở xong
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { headerShown = true }
        }
        .onChange(of: chip) { _, _ in reveal(after: 0.05) }
        .onChange(of: query) { _, _ in reveal(after: 0.05) }
    }

    // MARK: Header — một hàng gọn: chip lọc (chữ, không icon/số) | 🔍 | 🗑.
    // Bấm 🔍 → hàng chip nhường chỗ cho ô tìm kiếm (hỗ trợ @link, @image…).

    @State private var searching = false
    @FocusState private var searchFocused: Bool

    private var header: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                if searching {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Tìm, hoặc @link @image @code…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(query.hasPrefix("@") ? NotchTheme.accent : .white)
                            .focused($searchFocused)
                            .onExitCommand { closeSearch() }
                    }
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Capsule().fill(NotchTheme.card))
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            chipButton(.all, "Tất cả")
                            chipButton(.pinned, "Ghim")
                            ForEach(ClipboardCategory.allCases, id: \.self) { c in
                                chipButton(.category(c), c.label)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                    .scrollIndicators(.never)
                    .edgeFade(.horizontal, 12, leading: false)   // chỉ mờ mép phải
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NotchIconButton(symbol: searching ? "xmark" : "magnifyingglass",
                            help: searching ? "Đóng tìm kiếm" : "Tìm kiếm", active: searching) {
                searching ? closeSearch() : openSearch()
            }
            NotchIconButton(symbol: "trash", help: "Xoá tất cả (giữ mục ghim)") { store.clearUnpinned() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: searching)
    }

    private func reveal(after delay: Double) {
        revealTask?.cancel()
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { revealed = false }
        let w = DispatchWorkItem { revealed = true }
        revealTask = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func openSearch() {
        searching = true
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        searching = false; query = ""; searchFocused = false
    }

    private func count(_ c: ClipboardFilter.Chip) -> Int {
        ClipboardFilter.apply(store.items, chip: c, query: "").count
    }

    private func chipButton(_ c: ClipboardFilter.Chip, _ title: String) -> some View {
        NotchChip(title: title, badge: chip == c ? "\(count(c))" : nil, on: chip == c) { chip = c }
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
        // Hai phần tách bạch: khung xem trước (bo góc riêng, lùi vào 4pt) ở trên,
        // dải thông tin (app · thời gian · dung lượng) nằm trên nền thẻ ở dưới.
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                background
                if category != .image && category != .color {
                    textPreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                } else if category == .color {
                    Text(item.plainText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding([.horizontal, .top], 4)
            footer
        }
        .frame(width: 160)
        // Liquid glass: nền trong mờ + viền sáng ở mép trên; hover sáng lên, không phóng to.
        .notchGlass(hover: hovering)
        .overlay(alignment: .topTrailing) { if hovering { actions } }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var background: some View {
        switch category {
        case .image:
            if let img = store.image(for: item) {
                // Ảnh nằm trong overlay → không đẩy giãn khung thẻ (chân thẻ khỏi bị lệch).
                Color.clear.overlay(Image(nsImage: img).resizable().scaledToFill()).clipped()
            } else {
                Color.clear.overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        case .color:
            if let c = ClipboardColor.parse(item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Color(red: c.r, green: c.g, blue: c.b)
            } else { Color.black.opacity(0.25) }
        default:
            Color.black.opacity(0.25)
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
        .padding(.horizontal, 9).frame(height: 24)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            CardActionButton(symbol: item.pinned ? "pin.slash.fill" : "pin.fill",
                             help: item.pinned ? "Bỏ ghim" : "Ghim") { store.togglePin(item.id) }
            CardActionButton(symbol: "xmark", help: "Xoá", destructive: true) { store.delete(item.id) }
        }
        .padding(5)
        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topTrailing)))
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

/// Nút tròn trên thẻ: vùng bấm 24pt, nền kính tối, hover sáng lên + phóng nhẹ, nhấn lún xuống.
private struct CardActionButton: View {
    let symbol: String
    let help: String
    var destructive = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hover && destructive ? NotchTheme.accent : .white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(hover ? 0.8 : 0.6)))
                .overlay(Circle().strokeBorder(.white.opacity(hover ? 0.35 : 0.12), lineWidth: 0.8))
                .contentShape(Circle())
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(PressDownStyle())
        .help(help)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hover)
    }
}

private struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
