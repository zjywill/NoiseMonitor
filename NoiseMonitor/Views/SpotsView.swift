import SwiftUI

/// 在各个位置测 10 秒，排出强弱
struct SpotsView: View {
    @Environment(NoiseHunter.self) private var hunter
    @State private var askingName = false
    @State private var name = ""
    @State private var showNoPeak = false
    @State private var confirmClear = false

    private var store: SpotStore { hunter.spotStore }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    measureCard
                    rankingCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .topBar("位置对比") {
                if !store.spots.isEmpty {
                    RoundStickerButton(systemImage: "trash.fill", color: Theme.slate, label: "清空") {
                        confirmClear = true
                    }
                }
            }
            .confirmationDialog("清空所有位置记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.removeAll() }
            }
            .alert("这是哪里？", isPresented: $askingName) {
                TextField("例如：卧室床头", text: $name)
                Button("开始测量") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !hunter.measureSpot(named: trimmed.isEmpty ? "位置 \(store.spots.count + 1)" : trimmed) {
                        showNoPeak = true
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("还没找到明显的频率", isPresented: $showNoPeak) {
                Button("好") {}
            } message: {
                Text("先到噪音明显的地方，在「测量」页锁定频率，再来这里对比各个位置。")
            }
        }
    }

    private var measureCard: some View {
        StickerCard(title: "测一个位置", systemImage: "scope", color: Theme.orange) {
            if let measurement = hunter.measurement {
                VStack(alignment: .leading, spacing: 10) {
                    Text("正在测「\(measurement.name)」，手机放稳，别说话…")
                        .font(Theme.font(.subheadline, .bold))
                        .foregroundStyle(Theme.ink)
                    ProgressBar(fraction: measurement.progress)
                    Button(action: hunter.cancelMeasurement) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.sticker(Theme.slate))
                }
            } else {
                Button {
                    name = ""
                    askingName = true
                } label: {
                    Label("在这里测 10 秒", systemImage: "mappin.and.ellipse")
                        .font(Theme.font(.headline, .heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.sticker(Theme.orange, cornerRadius: 16))
                .disabled(!hunter.isRunning)
            }
            Text(hunter.lockedFrequency.map { "对比的频率：\($0.formatted(decimals: 1)) Hz" }
                 ?? "还没锁定频率，开始测量时会自动锁定当前最明显的频率。")
                .font(Theme.font(.footnote, .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var rankingCard: some View {
        let ranked = store.ranked
        StickerCard(title: "从强到弱", systemImage: "chart.bar.fill", color: Theme.coral) {
            if ranked.isEmpty {
                Text("在家里不同的位置各测一次，最强的地方就离声源最近。比如：各个房间的墙角、床头、靠近管道和配电箱的墙面。")
                    .font(Theme.font(.subheadline, .medium))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                let strongest = ranked[0].level
                VStack(spacing: 10) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, spot in
                        SpotRow(spot: spot, rank: index + 1, strongest: strongest)
                            .contextMenu {
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    store.delete(ids: [spot.id])
                                }
                            }
                    }
                }
                Text("长按某一行可以删除。")
                    .font(Theme.font(.footnote, .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: max(geo.size.width * fraction, 12))
            }
        }
        .frame(height: 12)
        .animation(.linear(duration: 0.15), value: fraction)
    }
}

private struct SpotRow: View {
    let spot: Spot
    let rank: Int
    let strongest: Double

    var body: some View {
        let below = strongest - spot.level
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if rank == 1 {
                    IconBadge(systemName: "flame.fill", color: Theme.coral, size: 26)
                } else {
                    Text("\(rank)")
                        .font(Theme.font(.subheadline, .black))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.track, in: Circle())
                }
                Text(spot.name)
                    .font(Theme.font(.headline, .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(spot.level.formatted(decimals: 1)) dB")
                    .font(Theme.font(.headline, .black))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            LevelBar(fraction: 1 - below / 20)
            HStack {
                Text(rank == 1 ? "最强" : "比最强处低 \(below.formatted(decimals: 1)) dB")
                Spacer()
                Text("\(spot.frequency.formatted(decimals: 1)) Hz · \(spot.date.formatted(date: .omitted, time: .shortened))")
            }
            .font(Theme.font(.caption, .semibold))
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(12)
        .insetBlock()
    }
}
