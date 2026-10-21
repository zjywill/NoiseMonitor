import Foundation

/// 根据最近十几秒的频率走势，猜一下声源是什么类型。
struct ToneAnalysis: Equatable {
    enum Kind {
        /// 稳定在 50 Hz 的整数倍：电磁嗡声
        case electrical
        /// 稳定，但不是 50 的整数倍：匀速转动的机械
        case mechanical
        /// 频率在漂移
        case drifting
    }

    let kind: Kind
    let frequency: Double
    /// 频率的标准差（Hz）
    let spread: Double
    /// 检测到的谐波频率
    let harmonics: [Double]

    init(frequencies: [Double], harmonics: [Double]) {
        let mean = frequencies.reduce(0, +) / Double(frequencies.count)
        let variance = frequencies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(frequencies.count)
        let spread = variance.squareRoot()
        let nearestMultiple = (mean / 50).rounded() * 50

        // 电网频率本身会有 ±0.2 Hz 左右的波动，100 Hz 嗡声就是 ±0.4 Hz
        if spread < 0.3, nearestMultiple >= 50, abs(mean - nearestMultiple) < 0.6 {
            kind = .electrical
        } else if spread < 0.6 {
            kind = .mechanical
        } else {
            kind = .drifting
        }
        frequency = mean
        self.spread = spread
        self.harmonics = harmonics
    }

    var title: String {
        switch kind {
        case .electrical: "像是电器的电磁嗡声"
        case .mechanical: "像是匀速转动的机械"
        case .drifting: "频率在漂移"
        }
    }

    var detail: String {
        let hz = String(format: "%.1f", frequency)
        var text = switch kind {
        case .electrical:
            "频率稳定在 \(hz) Hz，正好是电网 50 Hz 的整数倍。常见来源：变压器、配电箱、电源适配器、电机线圈。"
        case .mechanical:
            "频率稳定在 \(hz) Hz，但不是 50 Hz 的整数倍，更像匀速转动的设备：水泵、风机、冰箱或空调压缩机。"
        case .drifting:
            "频率在 \(hz) Hz 附近来回变，可能是变频设备（变频空调、变频水泵），或者有几个声源叠在一起。"
        }
        if !harmonics.isEmpty {
            let list = harmonics.map { "\(Int($0.rounded())) Hz" }.joined(separator: "、")
            text += "\n同时检测到 \(list) 谐波"
            if kind == .electrical {
                text += "，更像变压器一类的设备。"
            } else {
                text += "。"
            }
        }
        return text
    }
}
