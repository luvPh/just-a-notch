// File: Sources/NotchIsland/Island/Components/FeaturePanels.swift
import SwiftUI

// MARK: - Media

struct MediaPanel: View {
    @ObservedObject var vm: MediaPanelViewModel

    var body: some View {
        Group {
            if vm.state == .unsupported || vm.track == nil {
                unsupported
            } else {
                player
            }
        }
        .onAppear { vm.appear() }
        .onDisappear { vm.disappear() }
    }

    private var unsupported: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(IslandTheme.cobalt)
            VStack(alignment: .leading, spacing: 4) {
                Text("No accessible media playing")
                    .font(.system(size: 12, weight: .semibold))
                Text("Open Music, Spotify, or a YouTube video. Allow Automation when macOS asks.")
                    .font(.system(size: 11)).foregroundStyle(IslandTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { vm.refresh() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandTheme.cobalt)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No accessible media playing")
    }

    private var player: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.track?.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let artist = vm.track?.artist {
                        Text(artist).font(.system(size: 11)).foregroundStyle(IslandTheme.mutedInk).lineLimit(1)
                    }
                    Text(vm.track?.sourceAppName ?? "").font(.system(size: 9)).foregroundStyle(IslandTheme.mutedInk)
                }
                Spacer(minLength: 0)
            }
            if let progress = vm.track?.progress {
                ProgressView(value: progress).tint(IslandTheme.cobalt)
            }
            HStack(spacing: 28) {
                controlButton("backward.fill", "Previous") { vm.previous() }
                controlButton(vm.state.isPlaying ? "pause.fill" : "play.fill",
                              vm.state.isPlaying ? "Pause" : "Play") { vm.playPause() }
                    .font(.system(size: 20))
                controlButton("forward.fill", "Next") { vm.next() }
            }
        }
    }

    private func controlButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)) }
            .buttonStyle(.plain).foregroundStyle(IslandTheme.cobalt)
            .accessibilityLabel(label)
    }
}

// MARK: - System status

struct SystemPanel: View {
    @ObservedObject var vm: SystemPanelViewModel

    var body: some View {
        VStack(spacing: 8) {
            row(icon: batteryIcon, label: "Battery", value: batteryText)
            metric("Memory", vm.snapshot.memoryUsedFraction,
                   "\(ByteFormat.string(vm.snapshot.memoryUsed)) / \(ByteFormat.string(vm.snapshot.memoryTotal))")
            metric("CPU", vm.snapshot.cpuUsage, String(format: "%.0f%%", vm.snapshot.cpuUsage * 100))
            metric("Disk", vm.snapshot.diskUsedFraction,
                   "\(ByteFormat.string(vm.snapshot.diskUsed)) / \(ByteFormat.string(vm.snapshot.diskTotal))")
        }
        .onAppear { vm.appear() }
        .onDisappear { vm.disappear() }
    }

    private var batteryIcon: String {
        guard let p = vm.snapshot.batteryPercentage else { return "bolt.slash" }
        if vm.snapshot.isCharging { return "battery.100.bolt" }
        switch p {
        case ..<0.15: return "battery.25"
        case ..<0.5: return "battery.50"
        default: return "battery.100"
        }
    }
    private var batteryText: String {
        guard let p = vm.snapshot.batteryPercentage else { return "N/A" }
        return String(format: "%.0f%%", p * 100)
    }

    private func row(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandTheme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
        .padding(10)
        .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, _ fraction: Double, _ value: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(value).font(.system(size: 11)).foregroundStyle(IslandTheme.mutedInk)
            }
            ProgressView(value: min(max(fraction, 0), 1)).tint(IslandTheme.cobalt)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
        .padding(10)
        .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Finder shelf

struct FinderShelfPanel: View {
    @ObservedObject var vm: FinderPanelViewModel
    let onSearchFocusChanged: (Bool) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(IslandTheme.mutedInk)
                TextField("Search pinned", text: $vm.query)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(IslandTheme.ink)
                    .focused($searchFocused)
                Button { vm.addViaPanel() } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain).foregroundStyle(IslandTheme.cobalt)
                    .accessibilityLabel("Add location")
            }
            .padding(6)
            .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 12))

            if vm.filtered.isEmpty {
                Text("Drag files here or press +").font(.system(size: 11)).foregroundStyle(IslandTheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ForEach(vm.filtered) { item in row(item) }
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { vm.add(url: url) } }
                }
            }
            return true
        }
        .onChange(of: searchFocused) { onSearchFocusChanged($0) }
        .onDisappear { onSearchFocusChanged(false) }
    }

    private func row(_ item: FinderShelfItem) -> some View {
        let available = vm.isAvailable(item)
        return HStack(spacing: 8) {
            Image(systemName: symbol(item.kind))
                .foregroundStyle(available ? IslandTheme.cobalt : .red.opacity(0.7))
            Text(item.displayName).font(.system(size: 12)).lineLimit(1)
                .foregroundStyle(available ? IslandTheme.ink : IslandTheme.mutedInk.opacity(0.6))
            if !available { Text("(missing)").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7)) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(IslandTheme.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if available { vm.open(item) } }
        .contextMenu {
            Button("Open") { vm.open(item) }
            Button("Reveal in Finder") { vm.reveal(item) }
            Button("Copy Path") { vm.copyPath(item) }
            Divider()
            Button("Remove from Shelf", role: .destructive) { vm.remove(item) }
        }
        .accessibilityLabel("\(item.displayName)\(available ? "" : ", missing")")
    }

    private func symbol(_ kind: FinderShelfItemKind) -> String {
        switch kind {
        case .folder: return "folder"
        case .file: return "doc"
        case .application: return "app"
        }
    }
}
