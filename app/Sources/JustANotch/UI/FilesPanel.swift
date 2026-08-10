import SwiftUI

/// Tab Files: duyệt catalogue lồng nhau + mở file. Điều hướng drill-down.
struct FilesPanel: View {
    @ObservedObject var store: FileShortcutStore
    @Binding var expanded: Bool

    /// Đường dẫn id từ root xuống catalogue đang mở (rỗng = Home).
    @State private var path: [UUID] = []
    @State private var hoveringAdd = false

    private var current: Catalogue { store.root.node(atPath: path) ?? store.root }
    private var atHome: Bool { path.isEmpty }
    private var title: String { atHome ? "Shortcuts" : current.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topBar
            list
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            navButton("house", enabled: !atHome) { path.removeAll() }
            navButton("chevron.left", enabled: !atHome) { if !path.isEmpty { path.removeLast() } }
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            addControls
            iconButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                expanded.toggle()
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(current.children) { cat in
                    row(icon: "folder.fill", name: cat.name, trailingCount: cat.children.count + cat.files.count, isFolder: true)
                        .onTapGesture { path.append(cat.id) }
                        .contextMenu {
                            Button("Xoá", role: .destructive) { store.deleteCatalogue(id: cat.id, atParentPath: path) }
                        }
                }
                ForEach(current.files) { file in
                    fileRow(file)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func row(icon: String, name: String, trailingCount: Int?, isFolder: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(isFolder ? .white : .white.opacity(0.85))
            Text(name).font(.system(size: 12.5, weight: isFolder ? .semibold : .regular))
                .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let c = trailingCount { Text("\(c)").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)) }
            if isFolder { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)) }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func fileRow(_ file: FileShortcut) -> some View {
        let missing = store.resolveURL(for: file).isMissing
        HStack(spacing: 9) {
            Image(systemName: missing ? "exclamationmark.triangle.fill" : "doc")
                .font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(missing ? .yellow.opacity(0.8) : .white.opacity(0.85))
            Text(file.name).font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(missing ? 0.45 : 1)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { store.open(file) }
        .contextMenu {
            Button("Xoá", role: .destructive) { store.deleteFile(id: file.id, atParentPath: path) }
        }
    }

    // Placeholder — hoàn thiện ở Task 8.
    private var addControls: some View {
        iconButton("plus") { }
    }

    private func navButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        iconButton(symbol, action: action).opacity(enabled ? 1 : 0.3).disabled(!enabled)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
}
