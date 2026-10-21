import SwiftUI

struct TipsView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(title: String, icon: String, color: Color, text: String)] = [
        ("先排除自己家", "power", Theme.coral,
         "关掉家里的总闸再听。噪音还在，就是外面来的（邻居、楼里的变压器房、水泵房、电梯）；没了，就逐个合上分闸找是哪件电器。"),
        ("先找频率，再走动", "waveform", Theme.primary,
         "在噪音最明显的地方锁定频率，然后只看这个频率的强度。整体音量被说话、车声占满，对低频没参考价值。"),
        ("用 10 秒平均做对比", "mappin.and.ellipse", Theme.orange,
         "100 Hz 的波长约 3.4 米，房间里每隔 1 米多就会强弱交替。边走边看容易被骗，在每个位置停下测 10 秒更可靠。"),
        ("同类位置比同类位置", "square.dashed", Theme.sky,
         "低频在墙角会被放大。墙角和墙角比、墙中间和墙中间比，结论才靠谱。"),
        ("贴着墙、地板、管道测", "hand.raised.fill", Theme.mint,
         "这类噪音常常是从楼体结构传进来的。把手机贴在不同的墙面和地面上，传进来的那一面会明显更强。"),
        ("留意时间规律", "clock.fill", Theme.lavender,
         "一直在响的多半是变压器；一阵一阵的多半是水泵、压缩机。记下最响的时间段，也能帮你判断来源。"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(tips, id: \.title) { tip in
                        StickerCard(title: tip.title, systemImage: tip.icon, color: tip.color) {
                            Text(tip.text)
                                .font(Theme.font(.subheadline, .medium))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    Text("强度是相对值（手机麦克风没有校准），但同一部手机前后对比是准的，找声源够用。iPhone 麦克风对 30 Hz 以下不灵敏，20 Hz 以下基本测不到。")
                        .font(Theme.font(.footnote, .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .topBar("使用技巧") {
                RoundStickerButton(systemImage: "xmark", color: Theme.slate, label: "关闭") { dismiss() }
            }
        }
    }
}
