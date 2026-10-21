import Foundation

struct Peak: Equatable, Sendable {
    /// 插值后的精确频率
    let frequency: Double
    /// 峰附近窄带的强度（dB，相对值）
    let level: Double
    /// 比周围底噪高出多少 dB，越大说明越像一个明确的单频音
    let prominence: Double
}

/// 频谱上的纯计算，不依赖任何状态。
enum SpectrumMath {
    /// 把功率换算成好读的 dB。手机麦克风没校准，这只是相对值，用来比较不同位置足够了。
    static let levelOffset = 100.0
    /// 至少比底噪高这么多，才算「有一个明显的频率」。纯白噪声里随机冒出的峰能到 9 dB 左右
    static let minProminence = 12.0
    /// 谐波的门槛可以低一点，但也要高过随机起伏
    static let minHarmonicProminence = 10.0

    static func decibels(_ power: Float) -> Double {
        decibels(Double(power))
    }

    static func decibels(_ power: Double) -> Double {
        10 * log10(max(power, 1e-14)) + levelOffset
    }

    /// 在 [low, high] Hz 里找功率最大的 bin，不管它是否明显。用于锁定频率之后。
    static func strongestPeak(in power: [Float], binWidth: Double, from low: Double, to high: Double) -> Peak? {
        guard let range = binRange(power, binWidth, low, high) else { return nil }
        var best = range.lowerBound
        for k in range where power[k] > power[best] {
            best = k
        }
        return makePeak(at: best, power, binWidth)
    }

    /// 在 [low, high] Hz 里找最突出的峰；如果 previous 附近的峰和最佳的差不多，就继续用它，避免跳来跳去。
    static func mostProminentPeak(in power: [Float], binWidth: Double, from low: Double, to high: Double, previous: Double?) -> Peak? {
        guard let range = binRange(power, binWidth, low, high) else { return nil }
        var bestBin: Int?
        var bestProminence = minProminence
        for k in range where power[k] > power[k - 1] && power[k] >= power[k + 1] {
            let prominence = prominence(at: k, power)
            if prominence >= bestProminence {
                bestBin = k
                bestProminence = prominence
            }
        }
        guard let bestBin else { return nil }

        if let previous,
           let stay = strongestPeak(in: power, binWidth: binWidth, from: previous - 2, to: previous + 2),
           stay.prominence >= max(minProminence, bestProminence - 3) {
            return stay
        }
        return makePeak(at: bestBin, power, binWidth)
    }

    private static func binRange(_ power: [Float], _ binWidth: Double, _ low: Double, _ high: Double) -> ClosedRange<Int>? {
        let lo = max(Int((low / binWidth).rounded(.down)), 1)
        let hi = min(Int((high / binWidth).rounded(.up)), power.count - 2)
        return lo <= hi ? lo...hi : nil
    }

    private static func makePeak(at k: Int, _ power: [Float], _ binWidth: Double) -> Peak {
        Peak(
            frequency: interpolatedBin(k, power) * binWidth,
            level: bandLevel(at: k, power),
            prominence: prominence(at: k, power)
        )
    }

    /// 对数幅度上做抛物线插值，得到 bin 之间的精确位置
    private static func interpolatedBin(_ k: Int, _ power: [Float]) -> Double {
        let a = log(Double(max(power[k - 1], 1e-20)))
        let b = log(Double(max(power[k], 1e-20)))
        let c = log(Double(max(power[k + 1], 1e-20)))
        let denominator = a - 2 * b + c
        guard denominator < 0 else { return Double(k) }
        let delta = 0.5 * (a - c) / denominator
        return Double(k) + min(max(delta, -0.5), 0.5)
    }

    /// Hann 窗会把一个单频音摊到几个相邻 bin 上，把它们加回来，再除以窗的等效噪声带宽 1.5
    private static func bandLevel(at k: Int, _ power: [Float]) -> Double {
        let lo = max(k - 2, 0)
        let hi = min(k + 2, power.count - 1)
        return decibels(power[lo...hi].reduce(0, +) / 1.5)
    }

    /// 峰值比两侧（避开峰本身）的中位数高出多少 dB
    private static func prominence(at k: Int, _ power: [Float]) -> Double {
        var neighbors: [Float] = []
        for offset in 4...15 {
            if k - offset >= 1 { neighbors.append(power[k - offset]) }
            if k + offset < power.count { neighbors.append(power[k + offset]) }
        }
        guard !neighbors.isEmpty else { return 0 }
        neighbors.sort()
        return decibels(power[k]) - decibels(neighbors[neighbors.count / 2])
    }
}
