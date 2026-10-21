import Foundation

struct LockInReading: Sendable, Equatable {
    /// 锁定时的中心频率，用来丢掉切换锁定之前的旧结果
    let center: Double
    /// 跟踪到的精确频率
    let frequency: Double
    /// 单频音本身的强度（已扣掉同带宽的底噪），dB 相对值，和频谱同一刻度
    let level: Double
    /// 单频音比同带宽底噪高多少 dB
    let snr: Double
}

/// 锁相检测（lock-in）：只盯一个频率，把它从噪声里拎出来。
///
/// 按锁相放大器的标准做法（参考 Zurich Instruments 的 signal processing basics）：
/// 用这个频率的正弦、余弦分别乘上原始采样（正交解调），先按 20 ms 一块求平均降采样，
/// 再过 n 阶级联一阶低通，得到这个频率分量的复振幅。
/// - 2 阶、时间常数 TC 时，噪声等效带宽 0.125/TC，99% 建立时间 6.6·TC。
///   TC = 0.4 s 时带宽约 0.31 Hz，而频谱一个 bin（Hann 窗）约 2.2 Hz，混进来的噪声少 8 dB 左右；
///   走动停下后约 2.6 秒读数到位。
/// - 两侧各放两个参考通道（±5、±9 Hz）量同样带宽的底噪，取中间两个的平均，从单频的功率里扣掉，
///   和 ECMA-418-1 附录 A 算纯音-噪声比时先扣掉单频两侧底噪的思路一样。
///   离声源远、单频音已经埋进噪声时，读数仍然跟着单频音本身变，而不是停在底噪上。
///
/// 实际频率会有一点漂（电网 ±0.05 Hz，水泵转速也会变），所以参考频率跟着实测相位慢慢修正，
/// 但不离开锁定中心 ±1 Hz。只在音频线程上用。
final class LockInDetector {
    /// 每 20 ms 出一个基带样本
    private static let stepSeconds = 0.02
    /// 低通时间常数 TC：越长越稳、越灵敏，但走动时反应越慢
    private static let timeConstant = 0.4
    private static let noiseOffsets = [-9.0, -5.0, 5.0, 9.0]
    private static let maxDrift = 1.0
    /// 每 5 个基带样本（100 ms）报一次
    private static let reportEvery = 5

    /// 一个混频 + 低通通道
    private struct Channel {
        private(set) var frequency = 0.0
        // 参考振荡器用复数旋转代替逐点算三角函数
        private var re = 1.0
        private var im = 0.0
        private var stepRe = 1.0
        private var stepIm = 0.0
        private var accI = 0.0
        private var accQ = 0.0
        // 两级一阶低通串起来就是 2 阶
        private var stage1I = 0.0
        private var stage1Q = 0.0
        private var lpI = 0.0
        private var lpQ = 0.0

        init(frequency: Double, sampleRate: Double) {
            retune(frequency, sampleRate: sampleRate)
        }

        mutating func retune(_ frequency: Double, sampleRate: Double) {
            self.frequency = frequency
            let delta = 2 * Double.pi * frequency / sampleRate
            stepRe = cos(delta)
            stepIm = sin(delta)
        }

        @inline(__always)
        mutating func mix(_ x: Double) {
            accI += x * re
            accQ += x * im
            let nextRe = re * stepRe - im * stepIm
            im = im * stepRe + re * stepIm
            re = nextRe
        }

        /// 块平均后过 2 阶低通。乘 2 是为了让幅度为 A 的正弦对应功率 A²，和频谱一致
        mutating func step(samples: Int, alpha: Double) {
            let zI = 2 * accI / Double(samples)
            let zQ = 2 * accQ / Double(samples)
            accI = 0
            accQ = 0
            stage1I += alpha * (zI - stage1I)
            stage1Q += alpha * (zQ - stage1Q)
            lpI += alpha * (stage1I - lpI)
            lpQ += alpha * (stage1Q - lpQ)
            // 旋转累积的舍入误差会让振荡器幅度慢慢变，顺手归一化
            let magnitude = (re * re + im * im).squareRoot()
            re /= magnitude
            im /= magnitude
        }

        var power: Double { lpI * lpI + lpQ * lpQ }
        var phase: Double { atan2(lpQ, lpI) }
    }

    let center: Double
    private let sampleRate: Double
    private let samplesPerStep: Int
    private var tone: Channel
    private var references: [Channel]
    private var counter = 0
    private var steps = 0
    private var lastPhase: Double?
    /// 平滑后的频率偏差估计（Hz）
    private var drift = 0.0

    init(frequency: Double, sampleRate: Double) {
        center = frequency
        self.sampleRate = sampleRate
        samplesPerStep = max(Int(sampleRate * Self.stepSeconds), 1)
        tone = Channel(frequency: frequency, sampleRate: sampleRate)
        references = Self.noiseOffsets.map { Channel(frequency: frequency + $0, sampleRate: sampleRate) }
    }

    /// 处理一段采样，返回其中最新的一个读数（没有到报告时间就是 nil）
    func process(_ samples: UnsafePointer<Float>, count: Int) -> LockInReading? {
        var latest: LockInReading?
        for i in 0..<count {
            let x = Double(samples[i])
            tone.mix(x)
            for r in references.indices {
                references[r].mix(x)
            }
            counter += 1
            if counter == samplesPerStep {
                counter = 0
                if let reading = step() {
                    latest = reading
                }
            }
        }
        return latest
    }

    private func step() -> LockInReading? {
        steps += 1
        // 刚开始用逐步变小的系数（等于前 n 个的平均），不用干等低通慢慢爬上来
        let alpha = max(1 / Double(steps), Self.stepSeconds / Self.timeConstant)
        tone.step(samples: samplesPerStep, alpha: alpha)
        for r in references.indices {
            references[r].step(samples: samplesPerStep, alpha: alpha)
        }

        // 去掉最大、最小，中间两个取平均：比单个通道稳，万一某个通道碰上别的单频音也不受影响
        let sorted = references.map(\.power).sorted()
        let noise = max((sorted[1] + sorted[2]) / 2, 1e-16)
        trackFrequency(noise: noise)

        guard steps >= 10, steps % Self.reportEvery == 0 else { return nil }
        // 扣掉底噪；单频音比底噪还弱时给个下限，免得 dB 掉到负无穷
        let tonePower = max(tone.power - noise, noise * 0.1)
        return LockInReading(
            center: center,
            frequency: tone.frequency,
            level: SpectrumMath.decibels(tonePower),
            snr: 10 * log10(tonePower / noise)
        )
    }

    /// 参考频率和实际频率差 Δf 时，低通输出的相位每秒转 -Δf 圈，据此把参考频率慢慢拉过去
    private func trackFrequency(noise: Double) {
        let phase = tone.phase
        defer { lastPhase = phase }
        guard let lastPhase else { return }
        var delta = phase - lastPhase
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        let offset = -delta / (2 * .pi * Self.stepSeconds)
        drift += 0.05 * (offset - drift)
        // 信噪比不到 10 dB 时相位基本是噪声，不跟，免得被带跑
        guard tone.power > noise * 10 else { return }
        let target = min(max(tone.frequency + 0.02 * drift, center - Self.maxDrift), center + Self.maxDrift)
        tone.retune(target, sampleRate: sampleRate)
    }
}
