import SwiftUI
import AppKit

/// Máy tính nhanh + đổi tiền trong launcher. Gõ là ra kết quả; Enter copy,
/// Esc / ← quay về hàng icon.
struct CalculatorView: View {
    let onBack: () -> Void
    let onInteract: () -> Void

    @ObservedObject private var rates = CurrencyRates.shared
    @AppStorage("calc.lastInput") private var input = ""
    @FocusState private var focused: Bool
    @State private var copied = false
    @State private var copyWork: DispatchWorkItem?
    /// Kết quả hợp lệ gần nhất — hiện mờ trong lúc đang gõ dở ("100usd +").
    @State private var lastGood: QuickCalc.Result?

    private var outcome: Result<QuickCalc.Result, QuickCalc.CalcError> {
        QuickCalc.evaluate(input, rates: rates.rates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            field
            resultArea
        }
        // NotchShape có "tai" ngược 12pt ở hai mép trên → thân thật hẹp hơn bề mặt 2×12.
        .padding(.horizontal, 28)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            rates.refreshIfStale()
            // Panel vừa được làm key ở controller — đợi một nhịp rồi mới focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
        .onChange(of: input) { _, _ in
            onInteract()
            if case .success(let r) = outcome { lastGood = r }
            if input.isEmpty { lastGood = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 20, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.08)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("MÁY TÍNH & TỶ GIÁ")
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 0)
            ratesStatus
        }
    }

    @ViewBuilder private var ratesStatus: some View {
        if rates.loading && rates.rates == nil {
            Text("đang tải tỷ giá…").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
        } else if let at = rates.updatedAt {
            Text("tỷ giá \(Self.stamp(at))")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                .help("Nguồn: open.er-api.com (tỷ giá tham khảo, cập nhật hằng ngày)")
        } else {
            Text("chưa có tỷ giá").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "function")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("", text: $input, prompt: Text("100usd · 2.5tr × 3 · 50eur to usd")
                .foregroundStyle(.white.opacity(0.28)))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(copyResult)
                .onExitCommand(perform: onBack)
            if !input.isEmpty {
                Button { input = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(.white.opacity(focused ? 0.16 : 0.05), lineWidth: 0.8))
    }

    @ViewBuilder private var resultArea: some View {
        switch outcome {
        case .success(let r):
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("= " + QuickCalc.format(r.value))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: QuickCalc.format(r.value))
                    Spacer(minLength: 0)
                    Text(copied ? "Đã copy ✓" : "⏎ copy")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(copied ? Color(red: 0.45, green: 0.9, blue: 0.6) : .white.opacity(0.3))
                        .animation(.easeOut(duration: 0.15), value: copied)
                }
                if let src = r.source, let rateLine = rateLine(src, r.value) {
                    Text(rateLine)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        case .failure(.syntax) where lastGood != nil:
            Text("= " + QuickCalc.format(lastGood!.value))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1).minimumScaleFactor(0.6)
        case .failure(let e):
            Text(message(e))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
                .padding(.top, 3)
        }
    }

    /// "100 USD · 1 USD = 26.340 ₫"
    private func rateLine(_ src: QuickCalc.Value, _ dst: QuickCalc.Value) -> String? {
        guard let from = src.currency, let to = dst.currency,
              let unit = try? QuickCalc.convert(1, from: from, to: to, rates: rates.rates) else { return nil }
        // Tiền đích "nhỏ" (VND→USD) thì ghi 1 USD = x VND cho dễ đọc.
        if unit < 0.01, let inv = try? QuickCalc.convert(1, from: to, to: from, rates: rates.rates) {
            return "\(QuickCalc.format(src)) · 1 \(to) = \(QuickCalc.format(.init(amount: inv, currency: from)))"
        }
        return "\(QuickCalc.format(src)) · 1 \(from) = \(QuickCalc.format(.init(amount: unit, currency: to)))"
    }

    private func message(_ e: QuickCalc.CalcError) -> String {
        switch e {
        case .empty: return "Gõ phép tính hoặc số tiền — k · tr · tỷ, usd · eur · jpy…"
        case .syntax: return "…"
        case .noRates: return "Chưa có tỷ giá (cần mạng lần đầu)"
        case .unknownCurrency(let c): return "Không biết loại tiền “\(c)”"
        case .divideByZero: return "Không chia được cho 0"
        }
    }

    private func copyResult() {
        guard case .success(let r) = outcome else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(QuickCalc.copyString(r.value), forType: .string)
        copied = true
        copyWork?.cancel()
        let w = DispatchWorkItem { copied = false }
        copyWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "HH:mm dd/MM"
        return f.string(from: d)
    }
}
