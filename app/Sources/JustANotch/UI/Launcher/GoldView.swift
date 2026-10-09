import SwiftUI

/// Giá vàng nhanh: XAU/USD + Bảo Tín Mạnh Hải (nhẫn Kim Gia Bảo, SJC). Tự làm
/// mới mỗi phút khi đang mở.
struct GoldView: View {
    let onBack: () -> Void
    var embedded = false

    @ObservedObject private var gold = GoldPrices.shared
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let goldTint = Color(red: 1.0, green: 0.8, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            worldRow
            Rectangle().fill(.ink.opacity(0.07)).frame(height: 0.5)
            localTable
        }
        .padding(.horizontal, 28)   // thân NotchShape thụt 12pt mỗi bên
        .padding(.top, 2)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { gold.refresh() }
        .onReceive(tick) { _ in gold.refresh() }
        .onExitCommand(perform: onBack)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if !embedded { LauncherBackButton(action: onBack) }
            Text("GIÁ VÀNG")
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(.ink.opacity(0.4))
            Spacer(minLength: 0)
            if gold.loading {
                ProgressView().controlSize(.mini).tint(.ink.opacity(0.5))
            } else if gold.failed {
                Text("mất kết nối · dùng dữ liệu cũ").font(.system(size: 9)).foregroundStyle(.ink.opacity(0.35))
            } else if let at = gold.world?.at {
                Text("cập nhật \(Self.hm(at))").font(.system(size: 9)).foregroundStyle(.ink.opacity(0.35))
            }
        }
    }

    private var worldRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("XAU/USD")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Self.goldTint)
                .frame(width: 58, alignment: .leading)
            if let w = gold.world {
                Text("$" + QuickCalc.formatNumber(w.price, maxFraction: 2))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: w.price)
                if let pct = w.changePct {
                    change(pct, text: String(format: "%@%.2f%%", pct >= 0 ? "+" : "", pct)
                                        .replacingOccurrences(of: ".", with: ","))
                }
                Spacer(minLength: 0)
                Text("/oz").font(.system(size: 9)).foregroundStyle(.ink.opacity(0.35))
            } else {
                Text("—").font(.system(size: 16, weight: .bold)).foregroundStyle(.ink.opacity(0.3))
                Spacer(minLength: 0)
            }
        }
    }

    private var localTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("BẢO TÍN MẠNH HẢI · đ/chỉ")
                    .font(.system(size: 8.5, weight: .bold)).tracking(0.5)
                    .foregroundStyle(.ink.opacity(0.32))
                Spacer(minLength: 0)
                Text("MUA").frame(width: 76, alignment: .trailing)
                Text("BÁN").frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.ink.opacity(0.32))

            if gold.local.isEmpty {
                Text(gold.loading ? "Đang tải…" : "Chưa lấy được bảng giá")
                    .font(.system(size: 10.5)).foregroundStyle(.ink.opacity(0.35))
            }
            ForEach(gold.local) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.ink.opacity(0.88))
                        .lineLimit(1)
                    if let t = item.trend {
                        Image(systemName: t > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 6.5))
                            .foregroundStyle(t > 0 ? Self.up : Self.down)
                            .help((t > 0 ? "+" : "") + QuickCalc.formatNumber(t, maxFraction: 0) + " đ")
                    }
                    Spacer(minLength: 0)
                    price(item.buy)
                    price(item.sell)
                }
            }
        }
    }

    private static let up = Color(red: 0.36, green: 0.86, blue: 0.55)
    private static let down = Color(red: 1.0, green: 0.42, blue: 0.42)

    private func change(_ pct: Double, text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(pct >= 0 ? Self.up : Self.down)
    }

    private func price(_ v: Double?) -> some View {
        Text(v.map { QuickCalc.formatNumber($0, maxFraction: 0) } ?? "—")
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.ink.opacity(v == nil ? 0.3 : 0.95))
            .frame(width: 76, alignment: .trailing)
    }

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

/// Nút ← dùng chung cho các màn trong launcher.
struct LauncherBackButton: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.ink.opacity(hovering ? 0.95 : 0.75))
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.ink.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
