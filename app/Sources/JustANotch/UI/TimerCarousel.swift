import SwiftUI

// Tab Timer: carousel 3 trang (Đơn, Pomodoro, Chuỗi tự tạo) cuộn NGANG VÔ TẬN
// theo đúng cơ chế của sidebar `ThemeCarousel`: `offset` là vị trí cuộn liên tục
// (điểm ảnh), chỉ số trang wrap bằng modulo nên cuộn mãi cả hai chiều. Cuộn dọc
// (2 ngón/con lăn) → nhảy trang ngang. Nút ⚙️ nằm ở wing phải notch.
struct TimerCarousel: View {
    @ObservedObject var single: TimerService
    @ObservedObject var pomodoro: TimerService
    @ObservedObject var sequence: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var showingSettings: Bool
    // Panel cao 300px khi đang sửa chuỗi (tab 3). Do NotchViewModel sở hữu.
    @Binding var tall: Bool

    // Khoá cuộn khi đang ở một màn setting con của trang hiện tại.
    @State private var locked = false
    // Chỉ nhảy trang khi con trỏ thực sự ở trên vùng timer (không phải sidebar).
    @State private var hovering = false
    @State private var offset: CGFloat = 0    // vị trí cuộn liên tục (điểm ảnh)
    @State private var acc: CGFloat = 0       // delta tích luỹ tới bước kế
    @State private var stepping = false       // cooldown giữa các bước
    @State private var didInit = false

    private let stepThreshold: CGFloat = 4
    private let stepCooldown: Double = 0.18
    private let pageCount = 3

    private func wrap(_ i: Int) -> Int { ((i % pageCount) + pageCount) % pageCount }

    var body: some View {
        Group {
            if showingSettings {
                TimerGeneralSettings(settings: settings, onBack: { showingSettings = false })
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let mid = w > 0 ? Int((offset / w).rounded()) : 0   // trang gần tâm
                    HStack(spacing: 0) {
                        ForEach((mid - 1)...(mid + 1), id: \.self) { vi in
                            pageSlot(wrap(vi), w, h)
                        }
                    }
                    .frame(width: w, height: h, alignment: .leading)
                    // Cửa sổ 3 trang bắt đầu từ (mid-1); dịch để offset hiện đúng → vòng vô tận.
                    .offset(x: CGFloat(mid - 1) * w - offset)
                    .frame(width: w, height: h, alignment: .leading)
                    .compositingGroup()   // gộp layer để .clipped() ăn chắc trong notch
                    .clipped()
                    .onHover { hovering = $0 }
                    // Catcher ở nền (không xen ZStack để không phá clip). Khoá (màn
                    // config con) → gỡ catcher để scroll dọc lọt vào ScrollView trong.
                    .background {
                        if !locked {
                            ScrollWheelCatcher(onScroll: { handleScroll($0, w: w) }, onEnded: { acc = 0 })
                        }
                    }
                    .onAppear {
                        if !didInit, w > 0 {
                            // Nhảy THẲNG tới trang đã lưu, KHÔNG animate (nếu không sẽ
                            // bị "cuộn" 1→N mỗi lần quay lại tab Timer).
                            var t = Transaction(); t.disablesAnimations = true
                            withTransaction(t) {
                                offset = CGFloat(min(pageCount - 1, max(0, settings.timerPage))) * w
                            }
                            didInit = true
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // Mỗi trang bị kẹp CỨNG trong slot w của nó (compositingGroup + clip) → nội
    // dung có rộng hơn cũng không lòi sang slot/sidebar bên cạnh.
    private func pageSlot(_ i: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        page(i)
            .frame(width: w, height: h)
            .compositingGroup()
            .clipped()
    }

    @ViewBuilder
    private func page(_ i: Int) -> some View {
        switch i {
        case 0: TimerPanel(timer: single, settings: settings, locked: $locked)
        case 1: PomodoroPage(timer: pomodoro, settings: settings, locked: $locked)
        default: TimerSequenceBuilder(timer: sequence, settings: settings, locked: $locked, tall: $tall)
        }
    }

    // Scroll dọc → nhảy trang ngang (giới hạn 0…2). Một tick quá ngưỡng = một trang.
    private func handleScroll(_ dy: CGFloat, w: CGFloat) {
        guard w > 0, !locked, hovering else { return }
        if acc != 0, (dy > 0) != (acc > 0) { acc = 0 }
        acc += dy
        guard !stepping, abs(acc) >= stepThreshold else { return }
        let dir = acc > 0 ? 1 : -1
        acc = 0
        let current = Int((offset / w).rounded())
        let next = current + dir                 // không kẹp → vòng vô tận
        stepping = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { offset = CGFloat(next) * w }
        settings.timerPage = wrap(next)
        DispatchQueue.main.asyncAfter(deadline: .now() + stepCooldown) { stepping = false }
    }
}
