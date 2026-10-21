import Charts
import SwiftUI

/// 主界面：频率、强度、频谱、判断
struct HuntView: View {
    @Environment(NoiseHunter.self) private var hunter
    @State private var showTips = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = hunter.errorMessage {
                        StickerCard(title: "麦克风不可用", systemImage: "mic.slash.fill", color: Theme.coral) {
                            Text(error)
                                .font(Theme.font(.subheadline, .medium))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    FrequencyCard()
                    StrengthCard()
                    SpectrumCard()
                    AnalysisCard()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .topBar("找噪音") {
                RoundStickerButton(systemImage: "lightbulb.fill", color: Theme.yellow, foreground: Theme.ink, label: "使用技巧") {
                    showTips = true
                }
                RoundStickerButton(
                    systemImage: hunter.hapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                    color: hunter.hapticsEnabled ? Theme.mint : Theme.slate,
                    label: hunter.hapticsEnabled ? "关闭震动提示" : "打开震动提示"
                ) {
                    hunter.hapticsEnabled.toggle()
                }
            }
            .sheet(isPresented: $showTips) { TipsView() }
        }
    }
}

private struct FrequencyCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "噪音频率", systemImage: "tuningfork", color: Theme.sky) {
            status
        } content: {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hunter.peak.map { $0.frequency.formatted(decimals: 1) } ?? "--")
                        .font(Theme.number(48))
                        .foregroundStyle(hunter.peak == nil ? Theme.disabledFill : Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Hz")
                        .font(Theme.font(.title3, .heavy))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if hunter.lockedFrequency != nil {
                    Button(action: hunter.unlock) {
                        Label("解锁", systemImage: "lock.open.fill")
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                    }
                    .buttonStyle(.sticker(Theme.slate))
                } else {
                    Button(action: hunter.lockCurrentPeak) {
                        Label("锁定", systemImage: "lock.fill")
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                    }
                    .buttonStyle(.sticker(Theme.primary))
                    .disabled(hunter.peak == nil)
                }
            }
            Text(hint)
                .font(Theme.font(.footnote, .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if !hunter.isRunning {
            Pill(text: "未在测量", color: Theme.slate)
        } else if hunter.lockedFrequency != nil {
            Pill(text: "已锁定", color: Theme.primary)
        } else {
            Pill(text: hunter.peak == nil ? "寻找中" : "自动跟踪", color: Theme.mint)
        }
    }

    private var hint: String {
        if let locked = hunter.lockedFrequency {
            return "只看 \(locked.formatted(decimals: 1)) Hz 附近，其它声音不影响读数。"
        }
        return hunter.peak == nil
            ? "到噪音明显的地方，等几秒，这里会出现最明显的低频。"
            : "找到了！点「锁定」，或者在下面的频谱上点那个峰。"
    }
}

private struct StrengthCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "强度", systemImage: "flame.fill", color: Theme.coral) {
            Button("重新开始", action: hunter.resetMax)
                .font(Theme.font(.footnote, .heavy))
                .foregroundStyle(Theme.primary)
                .disabled(hunter.maxLevel == nil)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(level.map { $0.formatted(decimals: 0) } ?? "--")
                    .font(Theme.number(64))
                    .foregroundStyle(level == nil ? Theme.disabledFill : Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("dB")
                    .font(Theme.font(.title3, .heavy))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if let below, below < 0.5 {
                    Pill(text: "这里最强", color: Theme.coral)
                }
            }
            LevelBar(fraction: fraction)
            HStack(spacing: 10) {
                stat("这一轮最高", hunter.maxLevel.map { "\($0.formatted(decimals: 0)) dB" } ?? "--")
                stat("比最高处", below.map { $0 < 0.5 ? "持平" : "低 \($0.formatted(decimals: 1)) dB" } ?? "--")
            }
            Text("拿着手机慢慢走，越靠近声源数值越大、震动越快。")
                .font(Theme.font(.footnote, .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(.caption, .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(Theme.font(.headline, .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetBlock()
    }

    private var level: Double? { hunter.peak?.level }

    private var below: Double? {
        guard let level, let max = hunter.maxLevel else { return nil }
        return max - level
    }

    /// 以这一轮最高值为满格，往下 20 dB 为空
    private var fraction: Double {
        guard let below else { return 0 }
        return 1 - below / 20
    }
}

private struct SpectrumCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "频谱 20–400 Hz", systemImage: "waveform.path.ecg", color: Theme.primary) {
            Chart {
                ForEach(hunter.spectrum) { point in
                    LineMark(
                        x: .value("频率", point.frequency),
                        y: .value("强度", point.level)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.primary)
                }
                if let peak = hunter.peak {
                    RuleMark(x: .value("峰", peak.frequency))
                        .foregroundStyle(Theme.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .chartXScale(domain: NoiseHunter.chartRange)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: [50, 100, 150, 200, 250, 300, 350, 400]) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().font(Theme.font(.caption2, .semibold))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
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
                            if let frequency: Double = proxy.value(atX: x) {
                                hunter.lock(near: frequency)
                            }
                        }
                }
            }
            .frame(height: 200)
            Text("点一下图上的峰，就能锁定那个频率。")
                .font(Theme.font(.footnote, .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

private struct AnalysisCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "可能是什么", systemImage: "sparkle.magnifyingglass", color: Theme.lavender) {
            if let analysis = hunter.analysis {
                Text(analysis.title)
                    .font(Theme.font(.title3, .heavy))
                    .foregroundStyle(Theme.ink)
                Text(analysis.detail)
                    .font(Theme.font(.subheadline, .medium))
                    .foregroundStyle(Theme.ink)
                Text("频率波动 ±\(analysis.spread.formatted(decimals: 2)) Hz（最近 15 秒）")
                    .font(Theme.font(.footnote, .medium))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Text("把手机放在噪音明显的地方，保持不动几秒，就能判断频率稳不稳、像什么设备。")
                    .font(Theme.font(.subheadline, .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
