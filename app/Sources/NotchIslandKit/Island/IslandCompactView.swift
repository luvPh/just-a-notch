import SwiftUI

enum CompactIslandPresentation: Equatable {
    case quiet
    case media(MediaTrack)

    static func select(track: MediaTrack?) -> CompactIslandPresentation {
        track.map(Self.media) ?? .quiet
    }

    func accessibilityLabel(eventTitle: String?) -> String {
        switch self {
        case .media(let track):
            return "\(track.title), \(track.sourceAppName)"
        case .quiet:
            return eventTitle ?? "Notch Island"
        }
    }
}

/// Deterministic three-bar waveform. Heights are a pure function of the 30 fps
/// frame index (not wall-clock), so playback is identical run to run and unit
/// testable. When paused or under Reduce Motion the bars hold a single static
/// frame. The one-shot 180 ms settle accent hands off to the play loop without
/// overlapping it.
enum CompactWaveformModel {
    static let barCount = 3
    static let fps: Double = 30
    static let restingHeight: CGFloat = 8
    static let maxBarHeight: CGFloat = 12
    static let settleDuration: TimeInterval = 0.18

    static func height(frame: Int, index: Int, playing: Bool, reduceMotion: Bool) -> CGFloat {
        guard playing, !reduceMotion else { return restingHeight }
        let t = Double(frame) / fps
        let value = 8 + sin(t * 5.5 + Double(index) * 0.7) * 4
        return CGFloat(min(12, max(4, value)))
    }

    static func scale(frame: Int, index: Int, playing: Bool, reduceMotion: Bool) -> CGFloat {
        height(frame: frame, index: index, playing: playing, reduceMotion: reduceMotion) / maxBarHeight
    }

    /// True while the one-shot settle accent owns the waveform; the 30 fps play
    /// loop begins only once this returns false.
    static func isSettling(sinceStart: TimeInterval) -> Bool {
        sinceStart < settleDuration
    }
}

/// Minimal compact state: a black bar that blends with the physical notch,
/// with live media motion or an optional transient event.
struct IslandCompactView: View {
    let height: CGFloat
    let geometry: AsymmetricCompactGeometry
    let reading: Bool
    let cornerRadius: CGFloat
    let event: IslandEvent?
    let track: MediaTrack?
    let playbackState: PlaybackState
    let phase: IslandMotionPhase
    let reduceMotion: Bool
    let activeMotion: Bool
    let onPlayPause: () -> Void

    private var presentation: CompactIslandPresentation {
        CompactIslandPresentation.select(track: track)
    }

    var body: some View {
        Group {
            if case .media(let track) = presentation {
                CompactMediaMotionView(
                    track: track,
                    playbackState: playbackState,
                    geometry: geometry,
                    reading: reading,
                    phase: phase,
                    reduceMotion: reduceMotion,
                    activeMotion: activeMotion,
                    height: height,
                    cornerRadius: cornerRadius,
                    onPlayPause: onPlayPause
                )
            } else {
                // Quiet: one unified black surface merging with the notch.
                Rectangle()
                    .fill(Color.black)
                    .frame(width: geometry.totalWidth, height: height)
                    .clipShape(NotchShape(bottomRadius: cornerRadius, topRadius: 8))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel(eventTitle: event?.payload.title))
    }
}
