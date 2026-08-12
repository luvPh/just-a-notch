import Foundation
import Combine
import AppKit

@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var phase: TimerPhase = .work
    @Published private(set) var mode: TimerMode = .pomodoro
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var completedWorkRounds = 0
    @Published private(set) var phaseLength: TimeInterval = 0   // để UI vẽ vòng %
    /// Nhãn/thông điệp do người dùng đặt cho hẹn giờ tuỳ chỉnh (mode .plain).
    @Published private(set) var label: String = ""
    /// True trong khoảnh khắc hẹn giờ tuỳ chỉnh vừa kết thúc (để panel hiện message).
    @Published private(set) var justFinished = false

    private var endDate: Date?
    private var ticker: Timer?

    // Injectable cho test; production dùng AppSettings + Date().
    private let configProvider: () -> PomodoroConfig
    private let now: () -> Date
    private let autoStartNextProvider: () -> Bool
    private let chime: () -> Void

    init(config: @escaping () -> PomodoroConfig,
         now: @escaping () -> Date = { Date() },
         autoStartNext: @escaping () -> Bool,
         chime: @escaping () -> Void) {
        self.configProvider = config
        self.now = now
        self.autoStartNextProvider = autoStartNext
        self.chime = chime
    }

    // MARK: Controls
    func startPomodoro() {
        mode = .pomodoro
        label = ""
        justFinished = false
        beginPhase(.work, resetRounds: true)
    }

    func startPlain(minutes: Int, label: String = "") {
        mode = .plain
        phase = .work
        justFinished = false
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        phaseLength = TimeInterval(max(1, minutes) * 60)
        arm(phaseLength)
    }

    func pause() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        isRunning = false
        endDate = nil
        stopTicker()
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        justFinished = false
        arm(remaining)
    }

    func reset() {
        isRunning = false; endDate = nil; stopTicker()
        remaining = 0; phaseLength = 0; completedWorkRounds = 0
        label = ""; justFinished = false
    }

    /// Người dùng đã xem xong thông điệp kết thúc → dọn trạng thái finished.
    func dismissFinished() {
        justFinished = false
        label = ""
    }

    func skip() { advancePhase() }

    // MARK: Phase lifecycle
    private func beginPhase(_ p: TimerPhase, resetRounds: Bool) {
        if resetRounds { completedWorkRounds = 0 }
        phase = p
        phaseLength = configProvider().duration(for: p)
        arm(phaseLength)
    }

    private func arm(_ seconds: TimeInterval) {
        remaining = seconds
        endDate = now().addingTimeInterval(seconds)
        isRunning = true
        startTicker()
    }

    private func advancePhase() {
        chime()
        if mode == .plain {
            // Giữ lại nhãn để panel hiện thông điệp kết thúc; dừng đồng hồ.
            isRunning = false; endDate = nil; stopTicker()
            remaining = 0
            justFinished = true
            return
        }
        let (next, rounds) = nextPhase(after: phase,
                                       completedWorkRounds: completedWorkRounds,
                                       cfg: configProvider())
        completedWorkRounds = rounds
        phase = next
        phaseLength = configProvider().duration(for: next)
        if autoStartNextProvider() {
            arm(phaseLength)
        } else {
            remaining = phaseLength
            isRunning = false
            endDate = nil
            stopTicker()
        }
    }

    // MARK: Ticking
    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    /// Test seam — chạy đúng logic của tick mà không cần chờ Timer thật.
    func tickForTest() { tick() }

    private func tick() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        if remaining <= 0 { advancePhase() }
    }

    deinit { ticker?.invalidate() }
}
