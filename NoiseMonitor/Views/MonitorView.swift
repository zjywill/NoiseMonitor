import Charts
import SwiftUI

/// 主界面：只做监测——当前声级、统计、最近两分钟的曲线、频谱
struct MonitorView: View {
    @Environment(NoiseHunter.self) private var hunter
    @State private var showCalibration = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let error = hunter.errorMessage {
                        StickerCard(title: "麦克风不可用", systemImage: "mic.slash.fill", color: Theme.coral) {
                            Text(error)
                                .font(Theme.font(.subheadline, .medium))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    HStack(spacing: 12) {
                        LevelCard()
                        StatsCard()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HistoryCard()
                    SpectrumCard()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .topBar("低频猎手") {
                RoundStickerButton(systemImage: "slider.horizontal.3", color: Theme.lavender, label: "校准") {
                    showCalibration = true
                }
            }
            .sheet(isPresented: $showCalibration) { CalibrationView() }
        }
    }
}

/// 并排卡片里的大读数
private struct Reading: View {
    let value: Double?
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value.map { $0.formatted(decimals: 0) } ?? "--")
                .font(Theme.number(40))
                .foregroundStyle(value == nil ? Theme.disabledFill : Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(Theme.font(.subheadline, .heavy))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

private struct LevelCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "当前", systemImage: "speaker.wave.2.fill", color: Theme.coral) {
            Reading(value: hunter.currentLevel, unit: "dB(A)")
            Spacer(minLength: 0)
            // 满格对应 30–90 dB(A)：安静的卧室到很吵的街边
            LevelBar(fraction: ((hunter.currentLevel ?? 30) - 30) / 60)
            Text("不计权 \(hunter.currentLevelZ.map { $0.formatted(decimals: 0) } ?? "--") dB")
                .font(Theme.font(.caption, .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct StatsCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "统计", systemImage: "chart.bar.fill", color: Theme.primary) {
            Button("重新统计", systemImage: "arrow.counterclockwise", action: hunter.resetStats)
                .labelStyle(.iconOnly)
                .font(Theme.font(.subheadline, .heavy))
                .foregroundStyle(Theme.primary)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                row("平均", hunter.averageLevel.map { "\($0.formatted(decimals: 1)) dB" })
                row("最高", hunter.maxCurrentLevel.map { "\($0.formatted(decimals: 1)) dB" })
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    row("时长", hunter.monitorStart.map { duration(from: $0, to: context.date) })
                }
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(.subheadline, .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 4)
            Text(value ?? "--")
                .font(Theme.font(.headline, .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func duration(from start: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct HistoryCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "最近 2 分钟", systemImage: "waveform.path", color: Theme.sky) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Chart(hunter.levelHistory) { point in
                    LineMark(
                        x: .value("时间", point.time),
                        y: .value("dB(A)", point.level)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.sky)
                }
                .chartXScale(domain: context.date.addingTimeInterval(-NoiseHunter.historyDuration)...context.date)
                .chartYScale(domain: 20...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .second, count: 30)) { _ in
                        AxisGridLine().foregroundStyle(Theme.track)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [20, 40, 60, 80, 100]) { _ in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel().font(Theme.font(.caption2, .semibold))
                    }
                }
            }
            .frame(height: 130)
        }
    }
}

private struct SpectrumCard: View {
    @Environment(NoiseHunter.self) private var hunter
    /// 用户点选的频率；不自动找峰
    @State private var selected: Double?

    var body: some View {
        StickerCard(title: "频谱 20–400 Hz", systemImage: "waveform.path.ecg", color: Theme.primary) {
            if let point = selectedPoint {
                Text("\(point.frequency.formatted(decimals: 1)) Hz · \(point.level.formatted(decimals: 0)) dB")
                    .font(Theme.font(.caption, .heavy))
                    .foregroundStyle(Theme.orange)
                    .monospacedDigit()
            }
        } content: {
            Chart {
                ForEach(hunter.spectrum) { point in
                    LineMark(
                        x: .value("频率", point.frequency),
                        y: .value("强度", point.level)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.primary)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("选中", point.frequency))
                        .foregroundStyle(Theme.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .chartXScale(domain: NoiseHunter.chartRange)
            // 每个点只有约 1.5 Hz 宽，读数比总声级低几十 dB 是正常的
            .chartYScale(domain: 0...80)
            .chartXAxis {
                AxisMarks(values: [50, 100, 150, 200, 250, 300, 350, 400]) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().font(Theme.font(.caption2, .semibold))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 20, 40, 60, 80]) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().font(Theme.font(.caption2, .semibold))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].origin.x
                            guard let frequency: Double = proxy.value(atX: x) else { return }
                            // 再点一下同一个地方取消
                            if let selected, abs(selected - frequency) < 3 {
                                self.selected = nil
                            } else {
                                selected = frequency
                            }
                        }
                }
            }
            .frame(height: 190)
        }
    }

    /// 选中位置附近 ±3 Hz 里最高的那个点，读数跟着实时更新
    private var selectedPoint: SpectrumPoint? {
        guard let selected else { return nil }
        return hunter.spectrum
            .filter { abs($0.frequency - selected) <= 3 }
            .max { $0.level < $1.level }
    }
}
