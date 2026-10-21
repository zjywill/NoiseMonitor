import Charts
import SwiftUI

/// 主界面：频率和强度并排一行，下面是频谱和判断，第一屏就能看到频谱
struct HuntView: View {
    @Environment(NoiseHunter.self) private var hunter
    @State private var showTips = false

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
                        FrequencyCard()
                        StrengthCard()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Text(hint)
                        .font(Theme.font(.footnote, .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        // 提示文字长短不一，固定占两行，下面的卡片才不会跟着上下跳
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
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

    private var hint: String {
        if let locked = hunter.lockedFrequency {
            guard let lockIn = hunter.lockIn else {
                return "已锁定 \(locked.formatted(decimals: 1)) Hz，锁相检测启动中…"
            }
            let snr = max(lockIn.snr, 0).formatted(decimals: 0)
            return hunter.isWeakSignal
                ? "信号太弱，只比底噪高 \(snr) dB，读数会跳。停下来多等几秒再看。"
                : "锁相检测中，比底噪高 \(snr) dB。拿着手机慢慢走，越靠近声源强度越大、震动越快。"
        }
        return hunter.peak == nil
            ? "到噪音明显的地方等几秒，这里会出现最明显的低频。"
            : "找到了！点「锁定」或在频谱上点那个峰，然后拿着手机慢慢走。"
    }
}

/// 并排卡片里的大读数
private struct Reading: View {
    let value: String?
    let unit: String
    /// 信号太弱、读数不可靠时变灰
    var dimmed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value ?? "--")
                .font(Theme.number(36))
                .foregroundStyle(value == nil ? Theme.disabledFill : dimmed ? Theme.inkSecondary : Theme.ink)
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

private struct FrequencyCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "频率", systemImage: "tuningfork", color: Theme.sky) {
            Reading(value: hunter.displayFrequency.map { $0.formatted(decimals: 1) }, unit: "Hz")
            Spacer(minLength: 0)
            if hunter.lockedFrequency != nil {
                Button(action: hunter.unlock) {
                    Label("解锁", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.sticker(Theme.slate, cornerRadius: 12))
            } else {
                Button(action: hunter.lockCurrentPeak) {
                    Label("锁定", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.sticker(Theme.primary, cornerRadius: 12))
                .disabled(hunter.peak == nil)
            }
        }
    }
}

private struct StrengthCard: View {
    @Environment(NoiseHunter.self) private var hunter

    var body: some View {
        StickerCard(title: "强度", systemImage: "flame.fill", color: Theme.coral) {
            Button("重新开始最高值", systemImage: "arrow.counterclockwise", action: hunter.resetMax)
                .labelStyle(.iconOnly)
                .font(Theme.font(.subheadline, .heavy))
                .foregroundStyle(Theme.primary)
                .disabled(hunter.maxLevel == nil)
        } content: {
            Reading(value: level.map { $0.formatted(decimals: 0) }, unit: "dB", dimmed: hunter.isWeakSignal)
            Spacer(minLength: 0)
            LevelBar(fraction: fraction)
            Text(summary)
                .font(Theme.font(.caption, .semibold))
                .foregroundStyle(below.map { $0 < 0.5 } == true ? Theme.coral : Theme.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var level: Double? { hunter.strength }

    private var below: Double? {
        guard let level, let max = hunter.maxLevel else { return nil }
        return max - level
    }

    private var summary: String {
        guard let below, let max = hunter.maxLevel else { return "最高 --" }
        let top = max.formatted(decimals: 0)
        return below < 0.5 ? "最高 \(top) · 这里最强" : "最高 \(top) · 低 \(below.formatted(decimals: 1))"
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
            // 固定纵轴：自动缩放会让刻度和图一直跳
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [50, 100, 150, 200, 250, 300, 350, 400]) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().font(Theme.font(.caption2, .semibold))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
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
            .frame(height: 190)
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
            VStack(alignment: .leading, spacing: 8) {
                if let analysis = hunter.analysis {
                    Text(analysis.title)
                        .font(Theme.font(.title3, .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(analysis.detail)
                        .font(Theme.font(.subheadline, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(5, reservesSpace: true)
                    Text("频率波动 ±\(analysis.spread.formatted(decimals: 2)) Hz（最近 15 秒）")
                        .font(Theme.font(.footnote, .medium))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("把手机放在噪音明显的地方，保持不动几秒，就能判断频率稳不稳、像什么设备。")
                        .font(Theme.font(.subheadline, .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            // 有没有结论都占同样的高度
            .frame(minHeight: 170, alignment: .topLeading)
        }
    }
}
