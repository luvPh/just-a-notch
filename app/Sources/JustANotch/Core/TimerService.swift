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
    /// Tên đoạn đang chạy (chế độ chuỗi tự tạo).
    @Published private(set) var currentSegmentName: String = ""
    /// Thời gian đã trôi (chế độ stopwatch, đếm lên).
    @Published private(set) var elapsed: TimeInterval = 0

    private var endDate: Date?
    private var ticker: Timer?

    // Trạng thái chạy chuỗi đoạn (mode .plain, runSegments không rỗng).
    private var runSegments: [TimerSegment] = []
    private var segIndex = 0
    private var countingUp = false

    // Injectable cho test; production dùng AppSettings + Date().
    private let configProvider: () -> PomodoroConfig
    private let now: () -> Date
    private let autoStartNextProvider: () -> Bool
    /// Tên âm mặc định cho Pomodoro/plain (chuỗi tự tạo dùng âm của từng đoạn).
    private let defaultSound: () -> String
    /// Phát âm theo tên (SoundLibrary tra cứu hệ thống/bundle).
    private let chime: (String) -> Void

    init(config: @escaping () -> PomodoroConfig,
         now: @escaping () -> Date = { Date() },
         autoStartNext: @escaping () -> Bool,
         defaultSound: @escaping () -> String = { "Glass" },
         chime: @escaping (String) -> Void) {
        self.configProvider = config
        self.now = now
        self.autoStartNextProvider = autoStartNext
        self.defaultSound = defaultSound
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
        countingUp = false
        runSegments = []
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        phaseLength = TimeInterval(max(1, minutes) * 60)
        arm(phaseLength)
    }

    /// Chạy một chuỗi đoạn đã trải phẳng; mỗi đoạn phát âm riêng khi kết thúc.
    func startSequence(_ segments: [TimerSegment], label: String = "") {
        mode = .plain
        phase = .work
        justFinished = false
        countingUp = false
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        runSegments = segments
        segIndex = 0
        guard let first = segments.first else { runSegments = []; return }
        currentSegmentName = first.name
        phaseLength = TimeInterval(max(1, first.minutes) * 60)
        arm(phaseLength)
    }

    /// Đồng hồ đếm lên không giới hạn (dùng endDate làm mốc bắt đầu).
    func startStopwatch() {
        mode = .plain
        justFinished = false
        countingUp = true
        runSegments = []
        label = ""
        elapsed = 0
        endDate = now()
        remaining = 0
        isRunning = true
        startTicker()
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
        runSegments = []; segIndex = 0; countingUp = false; elapsed = 0
        currentSegmentName = ""
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
        // Chế độ chuỗi tự tạo: chime theo âm của đoạn vừa kết thúc, rồi sang đoạn kế.
        if !runSegments.isEmpty {
            chime(runSegments[segIndex].soundName)
            segIndex += 1
            if segIndex >= runSegments.count {
                isRunning = false; endDate = nil; stopTicker()
                remaining = 0
                justFinished = true
                return
            }
            let next = runSegments[segIndex]
            currentSegmentName = next.name
            phaseLength = TimeInterval(max(1, next.minutes) * 60)
            arm(phaseLength)
            return
        }
        chime(defaultSound())
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
        if countingUp {
            elapsed = max(0, now().timeIntervalSince(end))
            return
        }
        remaining = max(0, end.timeIntervalSince(now()))
        if remaining <= 0 { advancePhase() }
    }

    deinit { ticker?.invalidate() }
}
