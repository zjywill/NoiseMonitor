import Accelerate
import Foundation

/// 一块采样（约 0.34 秒）的均方值，A 计权和不计权各一个
struct LevelReading: Sendable {
    /// A 计权后的均方值（满幅正弦的均方是 0.5）
    let meanSquareA: Double
    /// 不计权（Z）的均方值
    let meanSquareZ: Double
    /// 这块采样的时长（秒），算时间平均用
    let duration: Double
}

/// 总声级：每 16384 个采样做一次 FFT，按 IEC 61672-1 的 A 计权公式给每个频点加权，
/// 再用 Parseval 定理把加权后的功率加起来，得到 A 计权的均方值。
/// 在频域加权和时域滤波器等价，好处是计权曲线就是标准公式本身，不受滤波器设计误差影响。
/// 只在音频线程上用。
final class LevelMeter {
    // 16384 点（48 kHz 下每块约 0.34 秒、频点间隔约 2.9 Hz）：块太小时低频会泄漏到权重不同的相邻频点，31.5 Hz 处误差到 1.4 dB
    static let blockSize = 16_384

    private let log2n = vDSP_Length(14)
    private let setup: FFTSetup
    private let window: [Float]
    /// 窗函数平方和，用来把加窗后的能量换回原信号的均方
    private let windowEnergy: Float
    private let sampleRate: Double
    /// 每个频点 A 计权的功率增益 |A(f)|²
    private let weightsA: [Float]

    private var block = [Float](repeating: 0, count: blockSize)
    private var filled = 0
    private var windowed = [Float](repeating: 0, count: blockSize)
    private var real = [Float](repeating: 0, count: blockSize / 2)
    private var imag = [Float](repeating: 0, count: blockSize / 2)
    private var power = [Float](repeating: 0, count: blockSize / 2)

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.blockSize, isHalfWindow: false)
        windowEnergy = vDSP.sumOfSquares(window)
        let binWidth = sampleRate / Double(Self.blockSize)
        weightsA = (0..<Self.blockSize / 2).map { k in
            let gain = Self.aWeighting(Double(k) * binWidth)
            return Float(gain * gain)
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// IEC 61672-1 的 A 计权幅度响应（线性，1 kHz 处为 1）
    static func aWeighting(_ f: Double) -> Double {
        guard f > 0 else { return 0 }
        let f2 = f * f
        let ra = (12_194.0 * 12_194.0 * f2 * f2)
            / ((f2 + 20.6 * 20.6) * ((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9)).squareRoot() * (f2 + 12_194.0 * 12_194.0))
        // +2.00 dB 是标准里的归一化常数，让 1 kHz 处正好 0 dB
        return ra * pow(10, 2.0 / 20)
    }

    /// 喂一段采样，攒够一块就返回这块的读数
    func process(_ samples: UnsafePointer<Float>, count: Int) -> [LevelReading] {
        var readings: [LevelReading] = []
        var offset = 0
        while offset < count {
            let take = min(Self.blockSize - filled, count - offset)
            block.withUnsafeMutableBufferPointer { dst in
                (dst.baseAddress! + filled).update(from: samples + offset, count: take)
            }
            filled += take
            offset += take
            if filled == Self.blockSize {
                filled = 0
                readings.append(measure())
            }
        }
        return readings
    }

    private func measure() -> LevelReading {
        let n = Self.blockSize
        vDSP.multiply(block, window, result: &windowed)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        power[0] = 0 // 直流和奈奎斯特混在一起，不要

        // Parseval：Σ(x·w)² = (2/N)·Σ|X_k|²（单边），zrip 的结果是 DFT 的 2 倍所以 |X|² 多了 4 倍；
        // 再除以 Σw² 换回原信号的均方
        let scale = 1 / (2 * Double(n) * Double(windowEnergy))
        let sumZ = Double(vDSP.sum(power))
        let sumA = Double(vDSP.dot(power, weightsA))
        return LevelReading(
            meanSquareA: sumA * scale,
            meanSquareZ: sumZ * scale,
            duration: Double(n) / sampleRate
        )
    }
}
