import AVFoundation
import Observation
import UIKit

struct SpectrumPoint: Identifiable {
    let frequency: Double
    let level: Double
    var id: Double { frequency }
}

/// 整个 App 的核心：开麦克风、跟踪噪音频率、给出强度和震动反馈、测量各个位置。
@MainActor
@Observable
final class NoiseHunter {
    enum Mode: Equatable {
        /// 自动跟踪最明显的频率
        case auto
        /// 只看锁定频率附近 ±3 Hz
        case locked(Double)
    }

    static let searchRange = 30.0...400.0
    static let chartRange = 20.0...400.0
    static let spotDuration: TimeInterval = 10
    private static let lockWindow = 3.0
    private static let historyWindow: TimeInterval = 15

    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private(set) var spectrum: [SpectrumPoint] = []
    /// 当前跟踪到的峰；自动模式下没有明显频率时为 nil
    private(set) var peak: Peak?
    /// 这一轮走动中见过的最高强度
    private(set) var maxLevel: Double?
    private(set) var analysis: ToneAnalysis?
    private(set) var measurement: SpotMeasurement?
    var hapticsEnabled = true

    var mode: Mode = .auto {
        didSet {
            guard mode != oldValue else { return }
            maxLevel = nil
            history.removeAll()
            analysis = nil
        }
    }

    var lockedFrequency: Double? {
        if case .locked(let frequency) = mode { frequency } else { nil }
    }

    let spotStore: SpotStore

    struct SpotMeasurement {
        let name: String
        let start: Date
        var energy = 0.0
        var count = 0
        var progress = 0.0
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let analyzer = SpectrumAnalyzer()
    @ObservationIgnored private var smoothed: [Float] = []
    @ObservationIgnored private var history: [(time: Date, frequency: Double)] = []
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false

    init(spotStore: SpotStore) {
        self.spotStore = spotStore
        // 这个对象跟 App 同生命周期，直接强引用就行
        analyzer.onFrame = { frame in
            Task { @MainActor in self.process(frame) }
        }
    }

    // MARK: - 启停

    func start() async {
        guard !isStarting, !(isRunning && engine.isRunning) else { return }
        isStarting = true
        defer { isStarting = false }
        if isRunning { stop() }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "没有麦克风权限。请到「设置 > 隐私与安全性 > 麦克风」里打开。"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // measurement 模式会关掉系统的自动增益和降噪，否则低频会被处理掉
            try session.setCategory(.record, mode: .measurement)
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)

            let input = engine.inputNode
            guard input.outputFormat(forBus: 0).sampleRate > 0 else {
                errorMessage = "找不到可用的麦克风。"
                return
            }
            analyzer.install(on: input)
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            errorMessage = "麦克风启动失败：\(error.localizedDescription)"
            return
        }

        errorMessage = nil
        smoothed = []
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        startHaptics()
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        measurement = nil
        hapticTask?.cancel()
        hapticTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - 操作

    /// 锁定当前最明显的频率
    func lockCurrentPeak() {
        guard let peak else { return }
        mode = .locked(peak.frequency)
    }

    /// 在频谱图上点了某个位置：锁定附近最强的峰
    func lock(near frequency: Double) {
        guard let binWidth = currentBinWidth,
              let found = SpectrumMath.strongestPeak(in: smoothed, binWidth: binWidth, from: frequency - 5, to: frequency + 5)
        else { return }
        mode = .locked(found.frequency)
    }

    func unlock() {
        mode = .auto
    }

    func resetMax() {
        maxLevel = peak?.level
    }

    /// 在当前位置测 10 秒。还没锁定的话先锁定当前频率；连频率都没找到就返回 false。
    @discardableResult
    func measureSpot(named name: String) -> Bool {
        guard isRunning, measurement == nil else { return false }
        if lockedFrequency == nil {
            guard peak != nil else { return false }
            lockCurrentPeak()
        }
        measurement = SpotMeasurement(name: name, start: .now)
        return true
    }

    func cancelMeasurement() {
        measurement = nil
    }

    // MARK: - 处理每一帧

    @ObservationIgnored private var currentBinWidth: Double?

    private func process(_ frame: SpectrumFrame) {
        guard isRunning else { return }

        // 轻微平滑一下，读数不至于乱跳
        if smoothed.count == frame.power.count {
            for i in smoothed.indices {
                smoothed[i] = 0.5 * smoothed[i] + 0.5 * frame.power[i]
            }
        } else {
            smoothed = frame.power
        }
        currentBinWidth = frame.binWidth
        let binWidth = frame.binWidth

        let lo = Int(Self.chartRange.lowerBound / binWidth)
        let hi = min(Int(Self.chartRange.upperBound / binWidth), smoothed.count - 1)
        spectrum = (lo...hi).map { SpectrumPoint(frequency: Double($0) * binWidth, level: SpectrumMath.decibels(smoothed[$0])) }

        switch mode {
        case .auto:
            peak = SpectrumMath.mostProminentPeak(
                in: smoothed, binWidth: binWidth,
                from: Self.searchRange.lowerBound, to: Self.searchRange.upperBound,
                previous: peak?.frequency
            )
        case .locked(let center):
            peak = SpectrumMath.strongestPeak(
                in: smoothed, binWidth: binWidth,
                from: center - Self.lockWindow, to: center + Self.lockWindow
            )
        }

        guard let peak else { return }
        maxLevel = max(maxLevel ?? peak.level, peak.level)
        updateAnalysis(with: peak, binWidth: binWidth)
        updateMeasurement(with: peak)
    }

    private func updateAnalysis(with peak: Peak, binWidth: Double) {
        let now = Date()
        if peak.prominence >= SpectrumMath.minProminence {
            history.append((now, peak.frequency))
        }
        history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }

        guard history.count >= 20, let first = history.first, now.timeIntervalSince(first.time) >= 4 else {
            analysis = nil
            return
        }
        let frequencies = history.map(\.frequency)
        let mean = frequencies.reduce(0, +) / Double(frequencies.count)
        let harmonics = [2.0, 3.0].compactMap { multiple -> Double? in
            let target = mean * multiple
            guard let found = SpectrumMath.strongestPeak(in: smoothed, binWidth: binWidth, from: target - 1.5 * multiple, to: target + 1.5 * multiple),
                  found.prominence >= SpectrumMath.minHarmonicProminence
            else { return nil }
            return found.frequency
        }
        analysis = ToneAnalysis(frequencies: frequencies, harmonics: harmonics)
    }

    private func updateMeasurement(with peak: Peak) {
        guard var current = measurement else { return }
        current.energy += pow(10, peak.level / 10)
        current.count += 1
        current.progress = min(Date().timeIntervalSince(current.start) / Self.spotDuration, 1)

        if current.progress >= 1 {
            spotStore.add(Spot(
                name: current.name,
                level: 10 * log10(current.energy / Double(current.count)),
                frequency: lockedFrequency ?? peak.frequency,
                date: .now
            ))
            measurement = nil
        } else {
            measurement = current
        }
    }

    // MARK: - 震动反馈

    /// 离这一轮最高值越近，震得越快：最高处 0.08 秒一下，低 15 dB 以上 1 秒一下
    private var hapticInterval: Double? {
        guard let level = peak?.level, let maxLevel else { return nil }
        let below = min(max((maxLevel - level) / 15, 0), 1)
        return 0.08 + below * 0.92
    }

    private func startHaptics() {
        hapticTask?.cancel()
        hapticTask = Task {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            while !Task.isCancelled {
                if hapticsEnabled, measurement == nil, let interval = hapticInterval {
                    generator.impactOccurred(intensity: interval < 0.3 ? 1 : 0.6)
                    try? await Task.sleep(for: .seconds(interval))
                } else {
                    try? await Task.sleep(for: .seconds(0.3))
                }
            }
        }
    }
}
