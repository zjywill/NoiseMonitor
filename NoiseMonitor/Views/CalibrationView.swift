import SwiftUI

/// 校准：和一个已经校准过的声级计在同一位置同时测，把读数调成一样
struct CalibrationView: View {
    @Environment(NoiseHunter.self) private var hunter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    StickerCard(title: "现在的读数", systemImage: "speaker.wave.2.fill", color: Theme.coral) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(hunter.currentLevel.map { $0.formatted(decimals: 1) } ?? "--")
                                .font(Theme.number(48))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("dB(A)")
                                .font(Theme.font(.title3, .heavy))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }

                    StickerCard(title: "校准偏移", systemImage: "slider.horizontal.3", color: Theme.lavender) {
                        HStack(spacing: 12) {
                            step(-1, "−1")
                            step(-0.1, "−0.1")
                            Text("\(hunter.calibration >= 0 ? "+" : "")\(hunter.calibration.formatted(decimals: 1)) dB")
                                .font(Theme.font(.title3, .heavy))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                            step(0.1, "+0.1")
                            step(1, "+1")
                        }
                        Button("恢复默认（0）") { hunter.calibration = 0 }
                            .font(Theme.font(.subheadline, .heavy))
                            .foregroundStyle(Theme.primary)
                            .disabled(hunter.calibration == 0)
                    }

                    StickerCard(title: "怎么校准", systemImage: "questionmark", color: Theme.sky) {
                        Text("手机麦克风的灵敏度每台都不一样，没校准时读数可能差几 dB。\n\n找一个已经校准过的声级计，或者 NIOSH SLM 这类按机型校准过的测量 App，在同一个位置、同一时间测同一个稳定的声音（比如空调、风扇），把这里的读数调到和它一样。\n\n改了校准之后，平均值和最高值会重新统计。")
                            .font(Theme.font(.subheadline, .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .topBar("校准") {
                RoundStickerButton(systemImage: "xmark", color: Theme.slate, label: "关闭") { dismiss() }
            }
        }
    }

    private func step(_ delta: Double, _ label: String) -> some View {
        Button {
            hunter.calibration = ((hunter.calibration + delta) * 10).rounded() / 10
        } label: {
            Text(label)
                .font(Theme.font(.subheadline, .heavy))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.sticker(Theme.slate, cornerRadius: 10))
    }
}
