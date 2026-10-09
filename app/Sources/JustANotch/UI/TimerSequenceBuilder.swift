import SwiftUI

// Trình sửa một chuỗi.
struct SequenceEditor: View {
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
                    .foregroundStyle(.ink)
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
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ink.opacity(0.05)))
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
                Text("\(idx + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.ink.opacity(0.4))
                    .frame(width: 12)
                TextField("Tên", text: $seq.segments[idx].name)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.ink)
                Spacer(minLength: 0)
                Text("\(seq.segments[idx].minutes)′").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.ink.opacity(0.8)).frame(width: 30, alignment: .trailing)
                Stepper("", value: $seq.segments[idx].minutes, in: 1...180)
                    .labelsHidden().fixedSize()
                if seq.segments.count > 1 {
                    Button { seq.segments.remove(at: idx) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 13))
                            .foregroundStyle(.ink.opacity(0.35))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 10))
                    .foregroundStyle(.ink.opacity(0.5)).frame(width: 12)
                StyledSoundPicker(selection: $seq.segments[idx].soundName)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.05)))
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
                    .foregroundStyle(.ink.opacity(0.7)).frame(width: 18)
                Text("Vùng lặp").font(.system(size: 11.5)).foregroundStyle(.ink.opacity(0.9))
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.05)))
    }

    private func stepField(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.ink.opacity(0.6))
            Text("\(value.wrappedValue)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.ink).frame(minWidth: 14)
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
