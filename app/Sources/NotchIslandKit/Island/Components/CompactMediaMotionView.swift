import SwiftUI

enum CompactMediaMotionModel {
    static let metadataStartOffset = CGSize(width: 30, height: -10)
    static let controlStartOffset = CGSize(width: -30, height: -12)
    static let metadataStartScale: CGFloat = 0.84
    static let controlStartScale: CGFloat = 0.68
    static let maximumBlur: CGFloat = 6
}

struct OrbitalWingModifier: ViewModifier {
    let offset: CGSize
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: min(blur, CompactMediaMotionModel.maximumBlur))
            .opacity(opacity)
    }
}

/// Width-measurement preference for the title marquee.
private struct CompactTitleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One unified near-black compact surface spanning both reveals and the empty
/// core, with no per-wing backgrounds or core separator. The camera core column
/// stays pure black (no sheen) so it merges with the hardware housing; the blue
/// violet sheen (≤ 8%) ramps in only across the wings. A direct play/pause
/// `Button` lives in the right wing and consumes its own tap so the parent
/// expansion gesture never fires from it.
struct CompactMediaMotionView: View {
    let track: MediaTrack
    let playbackState: PlaybackState
    let geometry: AsymmetricCompactGeometry
    let reading: Bool
    let phase: IslandMotionPhase
    let reduceMotion: Bool
    let activeMotion: Bool
    let height: CGFloat
    let cornerRadius: CGFloat
    let onPlayPause: () -> Void

    @State private var sweepProgress: CGFloat = 0
    @State private var traceProgress: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var measuredTitleWidth: CGFloat = 0
    @State private var animatedIdentity: String?

    private let titleViewport: CGFloat = 112
    private let sheen = Color(red: 0.55, green: 0.49, blue: 1)

    private var identity: String { track.sourceAppName + "|" + track.title }

    private var isPlaying: Bool { playbackState == .playing }

    private var marqueeDecision: CompactTitleMarqueePolicy.Decision {
        CompactTitleMarqueePolicy.decide(
            textWidth: measuredTitleWidth,
            viewportWidth: titleViewport,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            unifiedSurface

            HStack(spacing: 0) {
                leftWing
                    .frame(width: geometry.leftReveal, height: height, alignment: .leading)
                    .clipped()

                Color.clear
                    .frame(width: geometry.coreWidth, height: height)
                    .accessibilityHidden(true)

                rightWing
                    .frame(width: geometry.rightReveal, height: height, alignment: .trailing)
            }
        }
        .frame(width: geometry.totalWidth, height: height)
        // Single clip after the whole surface is composed — no join line.
        .clipShape(NotchShape(bottomRadius: cornerRadius))
        .onAppear { runOneShotEffectsIfNeeded() }
        .onChange(of: identity) { _ in
            runOneShotEffectsIfNeeded()
            restartMarquee()
        }
        .onChange(of: reading) { _ in restartMarquee() }
        .onChange(of: measuredTitleWidth) { _ in restartMarquee() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.sourceAppName)")
    }

    // MARK: Unified surface

    private var unifiedSurface: some View {
        let total = max(geometry.totalWidth, 1)
        let coreStart = geometry.leftReveal / total
        let coreEnd = (geometry.leftReveal + geometry.coreWidth) / total
        return Rectangle()
            .fill(Color.black)
            .overlay {
                if !reduceMotion {
                    LinearGradient(
                        stops: [
                            .init(color: sheen.opacity(0.08), location: 0),
                            .init(color: .clear, location: max(0, coreStart - 0.02)),
                            .init(color: .clear, location: min(1, coreEnd + 0.02)),
                            .init(color: sheen.opacity(0.08), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay { if !reduceMotion { sweepOverlay(total: total) } }
    }

    private func sweepOverlay(total: CGFloat) -> some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, .white.opacity(0.16), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(24, proxy.size.width * 0.4))
            .offset(x: -proxy.size.width * 0.6 + sweepProgress * proxy.size.width * 1.6)
        }
        .allowsHitTesting(false)
    }

    // MARK: Left wing (thumbnail + reading metadata)

    private var leftWing: some View {
        HStack(spacing: 8) {
            thumbnail

            if reading {
                VStack(alignment: .leading, spacing: 1) {
                    titleMarquee
                    Text(track.sourceAppName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(width: titleViewport, alignment: .leading)
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, reading ? 7 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: reading)
    }

    private var thumbnail: some View {
        Image(systemName: Self.symbolName(for: track.sourceAppName))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    private var titleMarquee: some View {
        Text(track.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .fixedSize()
            .lineLimit(1)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CompactTitleWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(CompactTitleWidthKey.self) { measuredTitleWidth = $0 }
            .offset(x: titleOffset)
            .frame(width: titleViewport, alignment: .leading)
            .clipped()
    }

    // MARK: Right wing (waveform + direct control)

    private var rightWing: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            waveform
            playButton
        }
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var waveform: some View {
        if reduceMotion {
            CompactWaveformBars(frame: 0, playing: false, reduceMotion: true)
        } else {
            AnimatedCompactWaveform(playbackState: playbackState, activeMotion: activeMotion)
        }
    }

    private var playButton: some View {
        let diameter = min(28, height - 4)
        return Button(action: onPlayPause) {
            ZStack {
                Circle().fill(.white.opacity(0.92))
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: max(7, diameter * 0.42), weight: .bold))
                    .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.09))
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .contentShape(Circle())
        .accessibilityLabel(isPlaying ? "Pause \(track.title)" : "Play \(track.title)")
    }

    // MARK: Effects

    private func runOneShotEffectsIfNeeded() {
        guard !reduceMotion, animatedIdentity != identity else { return }
        animatedIdentity = identity

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            sweepProgress = 0
            traceProgress = 0
        }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)) { sweepProgress = 1 }
        withAnimation(.linear(duration: IslandMotion.traceDuration)) { traceProgress = 1 }
    }

    /// Drives the one-pass marquee per `CompactTitleMarqueePolicy`. Static titles
    /// (fit or Reduce Motion) hold at offset 0; overflowing titles scroll once.
    private func restartMarquee() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { titleOffset = 0 }

        guard reading, !reduceMotion else { return }
        if case let .scroll(delay, distance, duration, _) = marqueeDecision {
            withAnimation(.linear(duration: duration).delay(delay)) {
                titleOffset = -distance
            }
        }
    }

    static func symbolName(for sourceApp: String) -> String {
        let name = sourceApp.lowercased()
        if name.contains("music") || name.contains("spotify") || name.contains("podcast") {
            return "music.note"
        }
        if name.contains("safari") || name.contains("chrome") || name.contains("youtube")
            || name.contains("tv") || name.contains("video") || name.contains("quicktime") {
            return "play.rectangle.fill"
        }
        return "waveform"
    }
}

private struct AnimatedCompactWaveform: View {
    let playbackState: PlaybackState
    let activeMotion: Bool

    private var animated: Bool {
        activeMotion && playbackState == .playing
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * CompactWaveformModel.fps)
            CompactWaveformBars(
                frame: frame,
                playing: animated,
                reduceMotion: false
            )
        }
        .accessibilityHidden(true)
    }
}

private struct CompactWaveformBars: View {
    let frame: Int
    let playing: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<CompactWaveformModel.barCount, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity([0.92, 0.72, 0.52][index]))
                    .frame(width: 2, height: 12)
                    .scaleEffect(
                        x: 1,
                        y: CompactWaveformModel.scale(
                            frame: frame,
                            index: index,
                            playing: playing,
                            reduceMotion: reduceMotion
                        ),
                        anchor: .center
                    )
            }
        }
        .frame(width: 10, height: 12)
        .animation(
            playing ? nil : .easeOut(duration: IslandMotion.pauseSettleDuration),
            value: playing
        )
        .accessibilityHidden(true)
    }
}
