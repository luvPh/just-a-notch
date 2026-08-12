import SwiftUI

// Tab Timer: carousel 3 trang (Đơn, Pomodoro, Chuỗi tự tạo) cuộn ngang có phân
// trang, chấm chỉ trang, và nút ⚙️ luôn hiện mở cài đặt tổng.
struct TimerCarousel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    @State private var showingSettings = false
    @State private var scrolledPage: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showingSettings {
                TimerGeneralSettings(settings: settings, onBack: { showingSettings = false })
            } else {
                VStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            TimerPanel(timer: timer, settings: settings)
                                .containerRelativeFrame(.horizontal).id(0)
                            PomodoroPage(timer: timer, settings: settings)
                                .containerRelativeFrame(.horizontal).id(1)
                            TimerSequenceBuilder(timer: timer, settings: settings)
                                .containerRelativeFrame(.horizontal).id(2)
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.never)
                    .scrollPosition(id: $scrolledPage)

                    dots
                }
                .onAppear { scrolledPage = settings.timerPage }
                .onChange(of: scrolledPage) { _, new in
                    if let new { settings.timerPage = new }
                }

                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(6)
                        .background(Circle().fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(.top, 2).padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity((scrolledPage ?? 0) == i ? 0.9 : 0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.easeOut(duration: 0.15), value: scrolledPage)
    }
}
