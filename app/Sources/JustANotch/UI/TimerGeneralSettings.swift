import SwiftUI

// Panel cài đặt tổng của Timer (mở từ nút ⚙️ luôn hiện trong tab).
struct TimerGeneralSettings: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void

    @State private var soundNames = SoundLibrary.shared.names

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                backButton(onBack)
                Text("Cài đặt Timer").font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    row {
                        Image(systemName: "bell.badge").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Chuông báo").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Toggle("", isOn: $settings.timerSoundEnabled).labelsHidden().toggleStyle(GlowToggleStyle())
                    }
                    row {
                        Image(systemName: "music.note").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Text("Âm mặc định").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        StyledSoundPicker(selection: $settings.timerSoundName, options: soundNames)
                    }
                    row {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                        Slider(value: $settings.timerVolume, in: 0...1)
                        Button {
                            SoundLibrary.shared.play(settings.timerSoundName, volume: Float(settings.timerVolume))
                        } label: {
                            Text("Nghe thử").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)))
                        }.buttonStyle(.plain)
                    }
                    Button {
                        SoundLibrary.shared.reload()
                        soundNames = SoundLibrary.shared.names
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text("Nạp lại thư viện âm") }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
                    }.buttonStyle(.plain)
                    Text("Bỏ file âm (.caf/.m4a/.aiff/.wav/.mp3) vào Resources/Sounds rồi build lại để thêm âm dài/êm hơn.")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.top, 1)
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 9) { content() }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }
}
