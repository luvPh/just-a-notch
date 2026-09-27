import SwiftUI

/// Phần thân launcher dưới hàng wing: hàng icon, hoặc màn của tính năng đang mở.
struct LauncherBody: View {
    @ObservedObject var vm: NotchViewModel
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if let f = vm.launcherFeature {
                feature(f)
                    .transition(.blurFade)
            } else {
                LauncherStrip(onPick: { vm.openLauncherFeature($0) }, reduceMotion: reduceMotion)
                    .frame(height: vm.launcherStripHeight)
                    .transition(.blurFade)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private func feature(_ f: LauncherFeature) -> some View {
        switch f {
        case .calculator:
            CalculatorView(onBack: { vm.launcherBack() },
                           onInteract: { vm.noteLauncherInteraction() })
        case .gold:
            GoldView(onBack: { vm.launcherBack() })
        case .claude:
            ClaudeSessionsView(vm: vm, onBack: { vm.launcherBack() }, reduceMotion: reduceMotion)
        }
    }
}

/// Hàng icon tính năng + dòng tên tool đang hover ở BÊN DƯỚI (không chen vào hàng
/// icon, nên icon không bị đẩy đi khi rê chuột qua). Icon bật lên lần lượt khi thả xuống.
struct LauncherStrip: View {
    let onPick: (LauncherFeature) -> Void
    let reduceMotion: Bool
    @State private var appeared = false
    @State private var hovered: LauncherFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ForEach(Array(LauncherFeature.allCases.enumerated()), id: \.element) { i, f in
                    LauncherIconButton(feature: f, reduceMotion: reduceMotion,
                                       onHover: { h in
                                           withAnimation(.easeOut(duration: 0.14)) {
                                               if h { hovered = f } else if hovered == f { hovered = nil }
                                           }
                                       },
                                       action: { onPick(f) })
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.55)
                        .blur(radius: appeared ? 0 : 4)
                        .animation(reduceMotion ? .easeOut(duration: 0.15)
                                   : .spring(response: 0.42, dampingFraction: 0.62).delay(0.05 + Double(i) * 0.05),
                                   value: appeared)
                }
            }
            // Tên tool đang hover; giữ chỗ cố định để dải không nhảy chiều cao.
            ZStack(alignment: .leading) {
                if let f = hovered {
                    Text(f.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .id(f)
                        .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
            .frame(height: 13, alignment: .leading)
            .padding(.leading, 4)
        }
        // Thân NotchShape thụt 12pt vì tai ngược ở mép trên.
        .padding(.leading, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 2)
        .onAppear { appeared = true }
    }
}

/// Icon tính năng: ô vuông bo góc với gradient màu nhấn. Hover → phóng nhẹ + sáng quầng
/// màu phía sau (tên hiện ở dòng dưới dải, không nằm trong nút); nhấn → lún xuống.
struct LauncherIconButton: View {
    let feature: LauncherFeature
    let reduceMotion: Bool
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: feature.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.45 : 0.18), lineWidth: 0.7))
                Image(systemName: feature.icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .scaleEffect(hovering ? 1.15 : 1)
            .shadow(color: (feature.tint.last ?? .white).opacity(hovering ? 0.75 : 0.2),
                    radius: hovering ? 7 : 3)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(LauncherPressStyle())
        .onHover { h in
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.72)) {
                hovering = h
            }
            onHover(h)
        }
        .help(feature.title)
    }
}

private struct LauncherPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
