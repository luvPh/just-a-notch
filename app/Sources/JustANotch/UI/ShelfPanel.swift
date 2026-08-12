import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Bề mặt "Kệ tạm" khi notch bung: vùng thả để giữ file + lưới tile kéo được RA.
struct ShelfPanel: View {
    @ObservedObject var store: ShelfStore
    /// Đóng shelf ngay (nút ✕).
    var onClose: () -> Void

    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = Color(red: 0.98, green: 0.80, blue: 0.33)   // vàng glow
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(.top, 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { handleDrop($0) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.6), radius: 5)
            Text("Kệ tạm").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            if !store.isEmpty {
                Text("\(store.count)").font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 4)
            if !store.isEmpty {
                shelfButton("trash", tint: Color(red: 1, green: 0.42, blue: 0.42)) { store.clear() }
            }
            shelfButton("xmark", tint: .white.opacity(0.7)) { onClose() }
        }
    }

    @ViewBuilder private var content: some View {
        if store.isEmpty {
            emptyDropZone
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
                    ForEach(store.items) { tile($0) }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .center) {
                if dropTargeted { dropHint }
            }
            .animation(.easeOut(duration: 0.14), value: dropTargeted)
        }
    }

    private var emptyDropZone: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(accent.opacity(dropTargeted ? 0.65 : 0.22),
                          style: StrokeStyle(lineWidth: 1, dash: [2, 5], dashPhase: 0))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(dropTargeted ? 0.08 : 0.025)))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 24)).foregroundStyle(accent.opacity(0.92))
                        .shadow(color: accent.opacity(dropTargeted ? 0.7 : 0.4), radius: dropTargeted ? 10 : 6)
                    Text("Thả để giữ tạm")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text("Kéo file ra sau bằng cách kéo từ đây")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.16), value: dropTargeted)
    }

    private var dropHint: some View {
        Label("Thả để thêm", systemImage: "plus.circle.fill")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.6)))
            .allowsHitTesting(false)
    }

    private func tile(_ item: ShelfItem) -> some View {
        VStack(spacing: 5) {
            Image(nsImage: fileIcon(item))
                .resizable().interpolation(.high)
                .frame(width: 44, height: 44)
            Text(item.name).font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            Button { store.remove(id: item.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrag { store.dragProvider(for: item) }
    }

    private func fileIcon(_ item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.url.path)
    }

    private func shelfButton(_ symbol: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26, height: 23)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        let add: (URL?) -> Void = { url in
            guard let url, url.isFileURL else { return }
            DispatchQueue.main.async { store.add(url: url) }
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
}
