import AVFoundation
import Accelerate

/// 一帧频谱。power[i] 是第 i 个 bin（频率 i * binWidth）的线性功率，
/// 已归一化成「正弦波峰值幅度的平方」，方便换算成 dB。
struct SpectrumFrame: Sendable {
    let binWidth: Double
    let power: [Float]
}

/// 在音频线程上攒采样、做 FFT，只把低频部分交给主线程。
///
/// 32768 点 FFT 在 48 kHz 下每个 bin 约 1.46 Hz，窗口约 0.68 秒；
/// 再配合峰值插值，稳定的单频音可以读到 0.1 Hz 左右的精度。
final class SpectrumAnalyzer: @unchecked Sendable {
    static let fftSize = 32_768
    /// 只输出到这个频率为止，够看 400 Hz 以内的基频和它的 2、3 次谐波
    static let maxFrequency = 1_300.0
    private static let hopSeconds = 0.15

    var onFrame: (@Sendable (SpectrumFrame) -> Void)?

    private let log2n = vDSP_Length(log2(Double(fftSize)))
    private let setup: FFTSetup
    private let window: [Float]
    private var ring = [Float](repeating: 0, count: fftSize)
    private var writeIndex = 0
    private var filled = 0
    private var samplesSinceLastFrame = 0
    private var sampleRate = 48_000.0

    private var ordered = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imag = [Float](repeating: 0, count: fftSize / 2)
    private var power: [Float] = []

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.fftSize, isHalfWindow: false)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// 在引擎启动前调用。
    func install(on input: AVAudioInputNode) {
        let format = input.outputFormat(forBus: 0)
        configure(sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let samples = buffer.floatChannelData?[0] else { return }
            self.append(samples, count: Int(buffer.frameLength))
        }
    }

    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        writeIndex = 0
        filled = 0
        samplesSinceLastFrame = 0
        let binWidth = sampleRate / Double(Self.fftSize)
        power = [Float](repeating: 0, count: Int(Self.maxFrequency / binWidth) + 1)
    }

    func append(_ samples: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            ring[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) & (Self.fftSize - 1)
        }
        filled = min(filled + count, Self.fftSize)
        samplesSinceLastFrame += count

        guard filled == Self.fftSize, Double(samplesSinceLastFrame) >= Self.hopSeconds * sampleRate else { return }
        samplesSinceLastFrame = 0
        analyze()
    }

    private func analyze() {
        let n = Self.fftSize
        let start = writeIndex

        // 把环形缓冲按时间顺序展开，同时加 Hann 窗
        ring.withUnsafeBufferPointer { ringPtr in
            ordered.withUnsafeMutableBufferPointer { out in
                let tail = n - start
                out.baseAddress!.update(from: ringPtr.baseAddress! + start, count: tail)
                (out.baseAddress! + tail).update(from: ringPtr.baseAddress!, count: start)
                vDSP_vmul(out.baseAddress!, 1, window, 1, out.baseAddress!, 1, vDSP_Length(n))
            }
        }

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                ordered.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(power.count))
            }
        }

        // zrip 的结果是 DFT 的 2 倍，Hann 窗的增益是 1/2，
        // 乘上 4/N² 后，幅度为 A 的正弦波对应功率 A²
        var normalized = vDSP.multiply(4 / (Float(n) * Float(n)), power)
        normalized[0] = 0 // bin 0 里混着直流和奈奎斯特分量，不要

        onFrame?(SpectrumFrame(binWidth: sampleRate / Double(n), power: normalized))
    }
}
