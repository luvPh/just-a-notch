import SwiftUI

// Trang "Chuỗi tự tạo": danh sách chuỗi đã lưu + trình dựng (≤4 đoạn, vùng lặp,
// âm/đoạn, lưu ≤5).
struct TimerSequenceBuilder: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings
    @Binding var locked: Bool
    @Binding var tall: Bool
    @StateObject private var store = SequenceStore()

    @State private var editing: TimerSequence?
    private let accent = Color(red: 0.36, green: 0.80, blue: 0.65)

    var body: some View {
        Group {
            if let seq = editing {
                SequenceEditor(seq: seq, accent: accent,
                               onSave: { store.save($0); editing = nil },
                               onCancel: { editing = nil })
            } else {
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Đang sửa chuỗi → khoá cuộn + nới panel cao lên.
        .onChange(of: editing != nil) { _, v in locked = v; tall = v }
        .onDisappear { locked = false; tall = false }
    }

    private var listView: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    if store.all.isEmpty {
                        Text("Chưa có chuỗi nào. Tạo chuỗi mới bên dưới.")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                    }
                    ForEach(store.all) { seq in
                        HStack(spacing: 8) {
                            Button { timer.startSequence(flatten(seq), label: seq.name) } label: {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.black).frame(width: 22, height: 22)
                                    .background(Circle().fill(accent))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(seq.name).font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text(summary(seq)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                            Button { editing = seq } label: {
                                Image(systemName: "pencil").font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                            }.buttonStyle(.plain)
                            Button { store.delete(seq.id) } label: {
                                Image(systemName: "trash").font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.42))
                                    .frame(width: 22, height: 22)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)

            Button { editing = newSequence() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(store.isFull ? "Đã đủ 5 chuỗi" : "Chuỗi mới")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.isFull ? .white.opacity(0.3) : accent)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .disabled(store.isFull)
        }
    }

    private func summary(_ s: TimerSequence) -> String {
        let names = s.segments.map { "\($0.name) \($0.minutes)′" }.joined(separator: " · ")
        if let a = s.loopStart, let b = s.loopEnd, s.loopCount > 1 {
            return names + "  ↻ đoạn \(a + 1)–\(b + 1) ×\(s.loopCount)"
        }
        return names.isEmpty ? "trống" : names
    }

    private func newSequence() -> TimerSequence {
        TimerSequence(id: UUID(), name: "Chuỗi \(store.all.count + 1)",
                      segments: [TimerSegment(id: UUID(), name: "Đoạn 1", minutes: 25,
                                              soundName: settings.timerSoundName, colorHex: "#5DCAA5")],
                      loopStart: nil, loopEnd: nil, loopCount: 1)
    }
}

// Trình sửa một chuỗi.
private struct SequenceEditor: View {
    @State var seq: TimerSequence
    let accent: Color
    let onSave: (TimerSequence) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                backButton(onCancel)
                TextField("Tên chuỗi", text: $seq.name)
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { onSave(normalized()) } label: {
                    Text("Lưu").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
                }.buttonStyle(.plain)
            }

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    ForEach(Array(seq.segments.enumerated()), id: \.element.id) { idx, _ in
                        segmentRow(idx)
                    }
                    if seq.segments.count < 4 {
                        Button { addSegment() } label: {
                            HStack(spacing: 6) { Image(systemName: "plus"); Text("Thêm đoạn") }
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(accent)
                                .frame(maxWidth: .infinity).frame(height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.05)))
                        }.buttonStyle(.plain)
                    }
                    loopRow
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func segmentRow(_ idx: Int) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("\(idx + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                    .frame(width: 12)
                TextField("Tên", text: $seq.segments[idx].name)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("\(seq.segments[idx].minutes)′").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).frame(width: 30, alignment: .trailing)
                Stepper("", value: $seq.segments[idx].minutes, in: 1...180)
                    .labelsHidden().fixedSize()
                if seq.segments.count > 1 {
                    Button { seq.segments.remove(at: idx) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5)).frame(width: 12)
                StyledSoundPicker(selection: $seq.segments[idx].soundName)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private var loopRow: some View {
        let hasLoop = Binding(
            get: { seq.loopStart != nil },
            set: { on in
                if on { seq.loopStart = 0; seq.loopEnd = max(0, seq.segments.count - 1); seq.loopCount = 2 }
                else { seq.loopStart = nil; seq.loopEnd = nil; seq.loopCount = 1 }
            })
        return VStack(spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: "repeat").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7)).frame(width: 18)
                Text("Vùng lặp").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Toggle("", isOn: hasLoop).labelsHidden().toggleStyle(GlowToggleStyle())
            }
            if seq.loopStart != nil {
                HStack(spacing: 6) {
                    stepField("Từ", Binding(get: { (seq.loopStart ?? 0) + 1 },
                                            set: { seq.loopStart = $0 - 1 }), 1...seq.segments.count)
                    stepField("Đến", Binding(get: { (seq.loopEnd ?? 0) + 1 },
                                             set: { seq.loopEnd = $0 - 1 }), 1...seq.segments.count)
                    stepField("×", Binding(get: { seq.loopCount }, set: { seq.loopCount = $0 }), 2...10)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func stepField(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Text("\(value.wrappedValue)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white).frame(minWidth: 14)
            Stepper("", value: value, in: range).labelsHidden().fixedSize()
        }
    }

    private func addSegment() {
        let n = seq.segments.count + 1
        seq.segments.append(TimerSegment(id: UUID(), name: "Đoạn \(n)", minutes: 5,
                                         soundName: seq.segments.first?.soundName ?? "Glass", colorHex: "#5DCAA5"))
    }

    // Kẹp vùng lặp về phạm vi hợp lệ trước khi lưu.
    private func normalized() -> TimerSequence {
        var s = seq
        if let a = s.loopStart, let b = s.loopEnd {
            let lo = min(max(0, a), s.segments.count - 1)
            let hi = min(max(lo, b), s.segments.count - 1)
            s.loopStart = lo; s.loopEnd = hi
        }
        return s
    }
}
