import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Tab Files: duyệt catalogue lồng nhau + mở file. Điều hướng drill-down.
struct FilesPanel: View {
    @ObservedObject var store: FileShortcutStore
    @Binding var expanded: Bool
    @Binding var pinned: Bool
    /// Số favorite đang chọn — đẩy lên VM để hiển thị ở wing trái.
    @Binding var selCount: Int

    /// Đường dẫn id từ root xuống catalogue đang mở (rỗng = Home). Nằm trong
    /// store để giữ nguyên khi panel bị dựng lại (đóng/mở notch, đổi tab).
    private var path: [UUID] {
        get { store.browsePath }
        nonmutating set { store.browsePath = newValue }
    }
    @State private var addMenuOpen = false
    @State private var creatingCatalogue = false
    @State private var newName = ""
    /// Các catalogue đang xổ inline (disclosure) trong cây.
    @State private var expandedIDs: Set<UUID> = []
    /// Lịch sử điều hướng cho nút "step back" (quay lại nơi vừa xem).
    @State private var history: [[UUID]] = []
    /// Đang kéo file/folder tới panel (để tô sáng vùng thả).
    @State private var dropTargeted = false
    /// Multi-select trong cây (id → thông tin mục). Cmd/Shift-click.
    @State private var selection: [UUID: Selected] = [:]
    @State private var lastTreeTap: UUID?
    /// Multi-select trong lưới favorites.
    @State private var favSelection: Set<UUID> = []
    @State private var lastFavTap: UUID?
    /// Tự phát hiện double-click (không dùng count:2 để tránh trễ single-click).
    @State private var lastClickID: UUID?
    @State private var lastClickAt: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var navSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)
    }
    private var canStepBack: Bool { !history.isEmpty }
    private var canFolderUp: Bool { !path.isEmpty }

    /// Đi tới catalogue mới, ghi lại nơi đang đứng vào lịch sử (cho step back).
    private func navigate(to newPath: [UUID]) {
        guard newPath != path else { return }
        history.append(path)
        withAnimation(navSpring) { path = newPath }
    }
    /// Step back: quay lại đúng nơi vừa xem trước đó (theo lịch sử).
    private func stepBack() {
        guard let prev = history.popLast() else { return }
        withAnimation(navSpring) { path = prev }
    }
    /// Folder back: lên 1 cấp thư mục cha.
    private func folderUp() {
        guard !path.isEmpty else { return }
        navigate(to: Array(path.dropLast()))
    }

    // MARK: - Multi-select (cây thư mục)

    /// Thứ tự hiển thị phẳng của cây tại `current` (theo expandedIDs) — cho Shift-range.
    private func flatVisibleIDs() -> [UUID] {
        func walk(_ cats: [Catalogue], _ files: [FileShortcut]) -> [UUID] {
            var out: [UUID] = []
            for c in cats {
                out.append(c.id)
                if expandedIDs.contains(c.id) { out += walk(c.children, c.files) }
            }
            out += files.map { $0.id }
            return out
        }
        return walk(current.children, current.files)
    }

    /// Bảng tra id → Selected cho mọi mục đang hiển thị (để Shift-range dựng entry).
    private func visibleSelectables() -> [UUID: Selected] {
        var map: [UUID: Selected] = [:]
        func walk(_ cats: [Catalogue], _ files: [FileShortcut], parent: [UUID]) {
            for c in cats {
                map[c.id] = Selected(id: c.id, isCatalogue: true, parentPath: parent, name: c.name, file: nil)
                if expandedIDs.contains(c.id) { walk(c.children, c.files, parent: parent + [c.id]) }
            }
            for f in files {
                map[f.id] = Selected(id: f.id, isCatalogue: false, parentPath: parent, name: f.name, file: f)
            }
        }
        walk(current.children, current.files, parent: path)
        return map
    }

    private func toggleTreeSelect(_ item: Selected) {
        if selection[item.id] != nil { selection[item.id] = nil } else { selection[item.id] = item }
        lastTreeTap = item.id
    }

    /// 1 click: chọn duy nhất mục này (thay cả lựa chọn hiện tại).
    private func selectOnly(_ item: Selected) {
        selection = [item.id: item]
        lastTreeTap = item.id
    }

    /// Click 1 phát: chọn NGAY (không trễ). Nếu là click thứ 2 nhanh (<0.3s) trên
    /// cùng mục → mở. Tự phát hiện double-click, tránh độ trễ của count:2.
    private func handleTreeClick(_ item: Selected, open: () -> Void) {
        let now = Date()
        if lastClickID == item.id, now.timeIntervalSince(lastClickAt) < 0.3 {
            clearSelection(); open(); lastClickID = nil
        } else {
            selectOnly(item); lastClickID = item.id; lastClickAt = now
        }
    }
    private func handleFavClick(_ id: UUID, open: () -> Void) {
        let now = Date()
        if lastClickID == id, now.timeIntervalSince(lastClickAt) < 0.3 {
            clearFavSelection(); open(); lastClickID = nil
        } else {
            favSelection = [id]; lastFavTap = id; lastClickID = id; lastClickAt = now
        }
    }

    private func rangeTreeSelect(_ id: UUID) {
        let order = flatVisibleIDs()
        let table = visibleSelectables()
        guard let end = order.firstIndex(of: id) else { return }
        let startId = lastTreeTap ?? id
        let start = order.firstIndex(of: startId) ?? end
        for i in stride(from: min(start, end), through: max(start, end), by: 1) {
            if let sel = table[order[i]] { selection[sel.id] = sel }
        }
        lastTreeTap = id
    }

    private func clearSelection() { selection.removeAll(); lastTreeTap = nil }

    // MARK: Hành động hàng loạt (cây)

    private func deleteSelected() {
        // Xoá file trước, catalogue sau (tránh path đổi giữa chừng cho file).
        for s in selection.values where !s.isCatalogue { store.deleteFile(id: s.id, atParentPath: s.parentPath) }
        for s in selection.values where s.isCatalogue { store.deleteCatalogue(id: s.id, atParentPath: s.parentPath) }
        clearSelection()
    }

    private func favoriteSelected() {
        for s in selection.values {
            if s.isCatalogue {
                store.addFavoriteCatalogue(path: s.parentPath + [s.id], name: s.name)
            } else if let f = s.file {
                store.addFavoriteFile(f)
            }
        }
        clearSelection()
    }

    private func openSelected() {
        for s in selection.values { if let f = s.file { store.open(f) } }
        clearSelection()
    }

    private func moveSelected(to dest: [UUID]) {
        // File trước rồi catalogue (giữ path nguồn ổn định).
        for s in selection.values where !s.isCatalogue { store.moveFile(id: s.id, from: s.parentPath, to: dest) }
        for s in selection.values where s.isCatalogue { store.moveCatalogue(id: s.id, from: s.parentPath, to: dest) }
        store.save()
        clearSelection()
    }

    // MARK: Thanh hành động cho lựa chọn (cây)

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Text("\(selection.count) đã chọn")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            if selection.values.contains(where: { !$0.isCatalogue }) {
                selActionButton("arrow.up.forward.app", tint: fileTint) { openSelected() }
            }
            selActionButton("star", tint: catTint) { favoriteSelected() }
            Menu {
                Button { moveSelected(to: []) } label: { Label("Home (gốc)", systemImage: "house") }
                if !store.root.children.isEmpty {
                    Divider()
                    moveTargetMenu(store.root.children, parentPath: [])
                }
            } label: {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                    .frame(width: 26, height: 24)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            selActionButton("trash", tint: Color(red: 1, green: 0.42, blue: 0.42)) { deleteSelected() }
            selActionButton("xmark", tint: .white.opacity(0.7)) { clearSelection() }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func selActionButton(_ symbol: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        SelActionButton(symbol: symbol, tint: tint, action: action)
    }

    private func moveTargetMenu(_ cats: [Catalogue], parentPath: [UUID]) -> AnyView {
        AnyView(
            ForEach(cats) { cat in
                let full = parentPath + [cat.id]
                if cat.children.isEmpty {
                    Button(cat.name) { moveSelected(to: full) }
                } else {
                    Menu {
                        Button { moveSelected(to: full) } label: { Label("Vào \(cat.name)", systemImage: "arrow.down.right.circle") }
                        Divider()
                        moveTargetMenu(cat.children, parentPath: full)
                    } label: { Label(cat.name, systemImage: "folder") }
                }
            }
        )
    }

    // MARK: Multi-select (lưới favorites)

    private func toggleFavSelect(_ id: UUID) {
        if favSelection.contains(id) { favSelection.remove(id) } else { favSelection.insert(id) }
        lastFavTap = id
    }
    private func rangeFavSelect(_ id: UUID) {
        let order = store.favorites.map { $0.id }
        guard let end = order.firstIndex(of: id) else { return }
        let start = order.firstIndex(of: lastFavTap ?? id) ?? end
        for i in stride(from: min(start, end), through: max(start, end), by: 1) { favSelection.insert(order[i]) }
        lastFavTap = id
    }
    private func clearFavSelection() { favSelection.removeAll(); lastFavTap = nil }
    private func deleteFavSelected() {
        for id in favSelection { store.removeFavorite(id: id) }
        clearFavSelection()
    }
    private func openFavSelected() {
        for id in favSelection {
            if let f = store.favorites.first(where: { $0.id == id }), !f.isCatalogue { store.openFavoriteFile(f) }
        }
        clearFavSelection()
    }


    private var addMenuSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.72)
    }
    private let catTint = Color(red: 0.56, green: 0.71, blue: 1.0)
    private let fileTint = Color(red: 0.60, green: 0.83, blue: 0.56)
    private let folderTint = Color(red: 0.98, green: 0.74, blue: 0.42)

    private var current: Catalogue { store.root.node(atPath: path) ?? store.root }
    private var atHome: Bool { path.isEmpty }

    var body: some View {
        Group {
            if expanded {
                // WIDE: toolbar ở hàng wing + cây thư mục đầy đủ. Drop → thêm vào thư mục đang mở.
                VStack(alignment: .leading, spacing: 8) {
                    topBar.frame(height: 34)
                    if !selection.isEmpty { selectionBar.transition(.move(edge: .top).combined(with: .opacity)) }
                    dropZone(list, toFavorites: false)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: selection.isEmpty)
            } else {
                // NHỎ: nút ghim + expand ở hàng wing bên phải + lưới Truy cập nhanh.
                // Drop → ghim thẳng vào Truy cập nhanh.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Spacer()
                        PinButton(pinned: $pinned)
                        ExpandButton(expanded: $expanded)
                    }
                    .frame(height: 34)
                    .padding(.trailing, -6)   // nhích sát wing phải
                    dropZone(favoritesView, toFavorites: true)
                }
            }
        }
        .padding(.leading, expanded ? 12 : 4)   // tab nhỏ: sát divider, tránh cắt tile
        .padding(.trailing, 12)
        .padding(.bottom, expanded ? 12 : 4)   // tab nhỏ: bớt chân để thêm chỗ cho favorites
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { clearSelection(); clearFavSelection() }   // bấm khoảng trống → bỏ chọn
        .onChange(of: favSelection.count) { _, n in selCount = n }
        .onDisappear { selCount = 0 }   // rời panel → xoá đếm ở wing
    }

    /// Bọc vùng nội dung (list/favorites) làm vùng thả — KHÔNG gồm toolbar.
    private func dropZone(_ content: some View, toFavorites: Bool) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { handleDrop($0, toFavorites: toFavorites) }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(catTint.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .background(RoundedRectangle(cornerRadius: 12).fill(catTint.opacity(0.07)))
                        .overlay(
                            Label(toFavorites ? "Thả để ghim" : "Thả để thêm vào đây", systemImage: "arrow.down.doc")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.black.opacity(0.55)))
                        )
                        .padding(3)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.14), value: dropTargeted)
    }

    /// Nhận file/folder thả vào. `toFavorites`: true → ghim; false → thêm vào thư mục hiện tại.
    private func handleDrop(_ providers: [NSItemProvider], toFavorites: Bool) -> Bool {
        var handled = false
        let dest = path
        let add: (URL?) -> Void = { url in
            guard let url, url.isFileURL else { return }
            DispatchQueue.main.async {
                if toFavorites { store.addFavoriteURL(url) } else { store.addFile(url: url, atPath: dest) }
            }
        }
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in add(url) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data { add(URL(dataRepresentation: data, relativeTo: nil)) }
                    else if let url = item as? URL { add(url) }
                }
            }
        }
        return handled
    }

    // MARK: - Truy cập nhanh (favorites) — tab Files dạng nhỏ

    @ViewBuilder private var favoritesView: some View {
        if store.favorites.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "star").font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                Text("Chưa có Truy cập nhanh")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text("Mở rộng ⤢ để duyệt, chuột phải một mục để ghim.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(store.favorites) { fav in favoriteTile(fav) }
                }
                .padding(4)   // chừa chỗ cho hiệu ứng hover (phóng to) không bị ScrollView cắt
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Màu + icon phân biệt 3 loại: catalogue (xanh dương), folder thật (cam), file (xanh lá).
    private func favoriteIcon(_ fav: Favorite) -> (String, Color) {
        if fav.isCatalogue { return ("folder.fill", catTint) }
        if fav.isDirectory { return ("folder.fill", folderTint) }
        return ("doc.fill", fileTint)
    }

    private func favoriteTile(_ fav: Favorite) -> some View {
        let (symbol, tint) = favoriteIcon(fav)
        let selected = favSelection.contains(fav.id)
        return VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 12)).foregroundStyle(tint)          // nhỏ hơn ~15%
                .frame(width: 29, height: 26)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
            Text(fav.name).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 46)
        }
        .frame(width: 48)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9).fill(catTint.opacity(selected ? 0.28 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(catTint.opacity(selected ? 0.6 : 0), lineWidth: 1))
        .modifier(TileHoverStyle())
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded { toggleFavSelect(fav.id) })
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { rangeFavSelect(fav.id) })
        .onTapGesture {   // 1 click chọn ngay · double-click mở
            handleFavClick(fav.id) { openFavorite(fav) }
        }
        .contextMenu {
            if !favSelection.isEmpty {
                Button { openFavSelected() } label: { Label("Mở tất cả (\(favSelection.count))", systemImage: "arrow.up.forward.app") }
                Button("Bỏ ghim đã chọn (\(favSelection.count))", role: .destructive) { deleteFavSelected() }
                Button("Bỏ chọn") { clearFavSelection() }
                Divider()
            }
            Button("Bỏ ghim", role: .destructive) { store.removeFavorite(id: fav.id) }
        }
    }

    private func openFavorite(_ fav: Favorite) {
        if fav.isCatalogue {
            // Bấm favorite catalogue → tự expand sang wide và nhảy tới catalogue đó.
            history.append(path)
            withAnimation(navSpring) {
                store.browsePath = fav.cataloguePath ?? []
                expanded = true
            }
        } else {
            store.openFavoriteFile(fav)
        }
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            navButton("house", enabled: !atHome) { navigate(to: []) }
            navButton("arrow.up.backward", enabled: canFolderUp) { folderUp() }   // folder back: lên 1 cấp
            navButton("arrow.uturn.backward", enabled: canStepBack) { stepBack() } // step back: lịch sử
            Spacer(minLength: 4)
            addControls
            // Không cần nút ghim ở wide: wide đã tự giữ notch mở.
            ExpandButton(expanded: $expanded)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                tree(current.children, files: current.files, parentPath: path, depth: 0)
            }
        }
        .scrollIndicators(.never)
    }

    /// Cây thư mục đệ quy: folder có thể xổ inline (disclosure), vẫn drill-down được.
    /// Trả về `AnyView` để phá vòng lặp kiểu của `some View` khi tự gọi lại.
    private func tree(_ cats: [Catalogue], files: [FileShortcut], parentPath: [UUID], depth: Int) -> AnyView {
        AnyView(
            VStack(spacing: 2) {
                ForEach(cats) { cat in
                    catalogueRow(cat, parentPath: parentPath, depth: depth)
                    if expandedIDs.contains(cat.id) {
                        tree(cat.children, files: cat.files, parentPath: parentPath + [cat.id], depth: depth + 1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                ForEach(files) { file in
                    fileRow(file).padding(.leading, CGFloat(depth) * 16)
                }
            }
        )
    }

    private func catalogueRow(_ cat: Catalogue, parentPath: [UUID], depth: Int) -> some View {
        let isOpen = expandedIDs.contains(cat.id)
        let count = cat.children.count + cat.files.count
        let hasContents = count > 0
        return HStack(spacing: 6) {
            DiscloseButton(isOpen: isOpen, enabled: hasContents) { toggleExpand(cat.id) }

            Image(systemName: isOpen ? "folder.fill" : "folder.fill")
                .font(.system(size: 13)).frame(width: 18).foregroundStyle(.white)
            Text(cat.name).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if hasContents {
                Text("\(count)").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .padding(.leading, CGFloat(depth) * 16)
        .modifier(RowHoverStyle())
        .background(selectionBg(cat.id))
        .contentShape(Rectangle())
        // Cmd-click: chọn/bỏ 1 mục · Shift-click: chọn dải · click thường: drill-down.
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded {
            toggleTreeSelect(Selected(id: cat.id, isCatalogue: true, parentPath: parentPath, name: cat.name, file: nil))
        })
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { rangeTreeSelect(cat.id) })
        .onTapGesture {   // 1 click chọn ngay · double-click mở
            handleTreeClick(Selected(id: cat.id, isCatalogue: true, parentPath: parentPath, name: cat.name, file: nil)) {
                navigate(to: parentPath + [cat.id])
            }
        }
        .contextMenu {
            Button { store.addFavoriteCatalogue(path: parentPath + [cat.id], name: cat.name) } label: {
                Label("Ghim vào Truy cập nhanh", systemImage: "star")
            }
            Button("Xoá", role: .destructive) { store.deleteCatalogue(id: cat.id, atParentPath: parentPath) }
        }
    }

    /// Nền tô sáng khi mục được chọn (multi-select).
    @ViewBuilder private func selectionBg(_ id: UUID) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(catTint.opacity(selection[id] != nil ? 0.28 : 0))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(catTint.opacity(selection[id] != nil ? 0.6 : 0), lineWidth: 1))
    }

    private func toggleExpand(_ id: UUID) {
        withAnimation(addMenuSpring) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    @ViewBuilder private func fileRow(_ file: FileShortcut) -> some View {
        let resolved = store.resolveURL(for: file)
        let missing = resolved.isMissing
        let isDir = resolved.resolved?.hasDirectoryPath ?? false
        let icon = missing ? "exclamationmark.triangle.fill" : (isDir ? "folder" : "doc")
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(missing ? .yellow.opacity(0.8) : (isDir ? folderTint : .white.opacity(0.85)))
            Text(file.name).font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(missing ? 0.45 : 1)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .modifier(RowHoverStyle())
        .background(selectionBg(file.id))
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded {
            toggleTreeSelect(Selected(id: file.id, isCatalogue: false, parentPath: path, name: file.name, file: file))
        })
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { rangeTreeSelect(file.id) })
        .onTapGesture {   // 1 click chọn ngay · double-click mở
            handleTreeClick(Selected(id: file.id, isCatalogue: false, parentPath: path, name: file.name, file: file)) {
                store.open(file)
            }
        }
        .contextMenu {
            Button { store.addFavoriteFile(file) } label: {
                Label("Ghim vào Truy cập nhanh", systemImage: "star")
            }
            Button("Xoá", role: .destructive) { store.deleteFile(id: file.id, atParentPath: path) }
        }
    }

    /// Nút + luôn hiển thị (tránh nhấp nhầm). BẤM để xổ/đóng 3 nút NGANG cùng hàng,
    /// hiện lần lượt trái→phải với hiệu ứng pop (kiểu B trong prototype).
    private var addControls: some View {
        // spacing 0 để khi đóng, 3 nút thu về 0 và + nằm sát nút expand (không hở).
        HStack(spacing: 0) {
            AddPlusButton(open: addMenuOpen, tint: catTint) {
                withAnimation(addMenuSpring) { addMenuOpen.toggle() }
            }
            popItem(0, "folder.badge.plus", catTint) { creatingCatalogue = true }
            popItem(1, "doc.badge.plus", fileTint) { pickFiles() }
            popItem(2, "folder.fill.badge.plus", folderTint) { pickFolder() }
        }
        .popover(isPresented: $creatingCatalogue, arrowEdge: .bottom) {
            catalogueNameField
        }
    }

    /// Một nút trong cụm +: khi mở thì "pop" (scale 0.4→1) và giãn bề ngang ra;
    /// khi đóng thu về 0 để không chiếm chỗ. Lệch pha theo index (trái→phải).
    private func popItem(_ index: Int, _ symbol: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        menuButton(symbol, tint: tint, action)
            .scaleEffect(addMenuOpen ? 1 : 0.4, anchor: .leading)
            .opacity(addMenuOpen ? 1 : 0)
            .frame(width: addMenuOpen ? 30 : 0)
            .padding(.leading, addMenuOpen ? 6 : 0)   // khoảng cách gói trong nút → đóng thì về 0
            .allowsHitTesting(addMenuOpen)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.14).delay(Double(index) * 0.04)
                    : .spring(response: 0.4, dampingFraction: 0.58).delay(Double(index) * 0.06),
                value: addMenuOpen)
    }

    private func menuButton(_ symbol: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        MenuButton(symbol: symbol, tint: tint) {
            withAnimation(addMenuSpring) { addMenuOpen = false }
            action()
        }
    }

    private var catalogueNameField: some View {
        HStack(spacing: 6) {
            TextField("Tên catalogue", text: $newName)
                .textFieldStyle(.roundedBorder).frame(width: 160)
                .onSubmit(commitCatalogue)
            Button("Tạo", action: commitCatalogue)
        }
        .padding(10)
    }

    private func commitCatalogue() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addCatalogue(named: name, atPath: path)
        newName = ""
        creatingCatalogue = false
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        liftAboveNotch(panel)
        if panel.runModal() == .OK {
            for url in panel.urls { store.addFile(url: url, atPath: path) }
        }
    }

    /// Chọn một hoặc nhiều folder thật ngoài ổ đĩa làm shortcut (mở ra Finder khi bấm).
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Chọn folder"
        liftAboveNotch(panel)
        if panel.runModal() == .OK {
            for url in panel.urls { store.addFile(url: url, atPath: path) }
        }
    }

    /// Notch nổi ở level .statusBar và sẽ che cửa sổ chọn file. Nâng open panel
    /// lên cao hơn để nó nằm TRÊN notch (notch vẫn ở trên mọi thứ khác).
    private func liftAboveNotch(_ panel: NSOpenPanel) {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    }

    private func navButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        iconButton(symbol, action: action).opacity(enabled ? 1 : 0.3).disabled(!enabled)
    }

    private func iconButton(_ symbol: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, tint: tint, action: action)
    }
}

/// Nút + của cụm thêm: chỉ ICON bên trong xoay 45° (thành ×) khi mở — nền bo góc
/// giữ nguyên (không xoay thành hình thoi). Có hover riêng.
private struct AddPlusButton: View {
    let open: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.9))
                .rotationEffect(.degrees(open ? 45 : 0))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(hovering ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: open)
    }
}

/// Nút thêm (catalogue / file / folder) — có hover riêng: nền & viền tint đậm hơn,
/// phóng nhẹ khi rê chuột.
private struct MenuButton: View {
    let symbol: String
    let tint: Color
    let perform: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 28)
                .background(tint.opacity(hovering ? 0.34 : 0.18), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(hovering ? 0.5 : 0.22), lineWidth: hovering ? 1 : 0.5))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Nút expand/collapse tab: đổi icon MƯỢT bằng symbolEffect(.replace) và toggle
/// trong một spring duy nhất để không "nhảy" khi panel đổi kích thước. Có hover riêng.
private struct ExpandButton: View {
    @Binding var expanded: Bool
    @State private var hovering = false
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left"
                                       : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(hovering ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Nút ghim (📌): bật để GIỮ notch mở dù bấm ra ngoài — cho kéo-thả ở dạng nhỏ.
/// Khi bật: đổi màu cam + icon pin.fill.
private struct PinButton: View {
    @Binding var pinned: Bool
    @State private var hovering = false
    private let onTint = Color(red: 0.98, green: 0.74, blue: 0.42)
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pinned.toggle() }
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(pinned ? onTint : .white.opacity(hovering ? 1 : 0.85))
                .rotationEffect(.degrees(pinned ? -30 : 0))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(pinned ? 0.20 : (hovering ? 0.18 : 0.08)),
                            in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Giữ cửa sổ mở (để kéo-thả)")
    }
}

/// Nút icon nhỏ có hover riêng: nền sáng lên + phóng nhẹ khi rê chuột.
private struct IconButton: View {
    let symbol: String
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.85))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(hovering ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(hovering ? 1.08 : 1.0)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Nút trong thanh hành động multi-select — có hover riêng: nền tint đậm hơn + phóng nhẹ.
private struct SelActionButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26, height: 24)
                .background(tint.opacity(hovering ? 0.32 : 0.16), in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Một mục đã chọn trong cây (đủ thông tin để xoá/ghim/mở/di chuyển).
private struct Selected {
    let id: UUID
    let isCatalogue: Bool
    let parentPath: [UUID]
    let name: String
    let file: FileShortcut?
}

/// Mũi tên xổ/thu catalogue — có hover riêng: nền sáng + mũi tên rõ hơn khi rê.
private struct DiscloseButton: View {
    let isOpen: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? (hovering ? 0.95 : 0.55) : 0.14))
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 18, height: 20)
                .background(Color.white.opacity(hovering && enabled ? 0.14 : 0),
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Hover cho ô favorite (tab nhỏ): phóng nhẹ + sáng lên.
private struct TileHoverStyle: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.06 : 1)
            .brightness(hovering ? 0.06 : 0)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Làm nổi hàng khi rê chuột — báo rõ chỗ nào bấm được.
private struct RowHoverStyle: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hovering ? 0.10 : 0)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Nhấn nhẹ co lại + mờ đi rồi bật về — cảm giác vật lý kiểu Apple.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
