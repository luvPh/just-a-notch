import SwiftUI

private let alcoveRed = Color(red: 0.96, green: 0.36, blue: 0.33)

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.8)
    }
    private var revealSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)
    }

    var body: some View {
        VStack(spacing: 0) {
            surface
                .frame(width: vm.surfaceWidth, height: vm.surfaceHeight, alignment: .top)
                .scaleEffect(vm.hovering && !vm.expanded ? 1.05 : 1.0, anchor: .top)
                .offset(x: vm.centerXOffset)
                .onHover { vm.hovering = $0 }
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: vm.hovering)
                .animation(revealSpring, value: vm.compactState)
                .animation(openSpring, value: vm.expanded)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var surface: some View {
        let shape = NotchShape(bottom: vm.bottomRadius, inverse: vm.topRadius)
        return ZStack(alignment: .top) {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.5), radius: vm.expanded ? 26 : 10, y: vm.expanded ? 14 : 5)

            if vm.expanded {
                player.transition(.blurFade)
            } else if vm.hasMedia {
                compact.transition(.blurFade)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if !vm.expanded { withAnimation(openSpring) { vm.expanded = true } } }
    }

    // MARK: Compact (content in the wings; camera core stays empty)

    private var compact: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                SourceIcon(sourceApp: vm.track?.sourceAppName ?? "", size: 18)
                if vm.compactState == .reading, let track = vm.track {
                    MarqueeText(text: track.title, viewport: vm.titleViewport)
                }
            }
            .padding(.leading, 13)
            .frame(width: vm.leftReveal, alignment: .leading)
            .clipped()

            Color.clear.frame(width: vm.coreWidth)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion, bars: 6)
                    .frame(width: 18, height: 11)
            }
            .padding(.trailing, 15)
            .frame(width: vm.rightReveal, alignment: .trailing)
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
    }

    // MARK: Expanded Alcove player

    private var player: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar
            HStack(spacing: 10) {
                Artwork(data: vm.track?.artworkData, corner: 7).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.track?.title ?? "Not playing").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(vm.track?.artist ?? vm.track?.sourceAppName ?? "—")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 4)
                OrganicWaveform(active: vm.isPlaying, reduceMotion: reduceMotion, bars: 6)
                    .frame(width: 18, height: 11)
            }
            scrubber
            HStack(spacing: 0) {
                ctlButton("backward.fill", 14) { vm.previous() }; Spacer()
                ctlButton(vm.isPlaying ? "pause.fill" : "play.fill", 18) { vm.playPause() }; Spacer()
                ctlButton("forward.fill", 14) { vm.next() }; Spacer()
                ctlButton("headphones", 13) {}
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 18)
        .padding(.top, vm.notchHeight - 2)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Tab bar placeholder — Media active now; other tabs are inert placeholders.
    private var tabBar: some View {
        HStack(spacing: 8) {
            tabChip("Media", active: true)
            tabChip("Lyrics", active: false)
            tabChip("Queue", active: false)
            Spacer()
        }
    }

    private func tabChip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(active ? .black : .white.opacity(0.55))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.10)),
                        in: Capsule())
    }

    private var scrubber: some View {
        let progress = CGFloat(vm.track?.progress ?? 0)
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(.white).frame(width: max(3, w * progress), height: 3)
                Circle().fill(.white).frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: w * progress - 4.5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    private func ctlButton(_ name: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size)).foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
    }
}
