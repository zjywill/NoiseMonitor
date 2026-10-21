import Foundation
import Observation

struct Spot: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// 10 秒内锁定频率的平均强度（dB，相对值）
    var level: Double
    var frequency: Double
    var date: Date
}

/// 各个位置的测量结果，存在 App 的 Documents 里。
@MainActor
@Observable
final class SpotStore {
    private(set) var spots: [Spot] = []

    @ObservationIgnored private let fileURL = URL.documentsDirectory.appending(path: "spots.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Spot].self, from: data) {
            spots = saved
        }
    }

    /// 从强到弱排好的
    var ranked: [Spot] {
        spots.sorted { $0.level > $1.level }
    }

    func add(_ spot: Spot) {
        spots.append(spot)
        save()
    }

    func delete(ids: [Spot.ID]) {
        spots.removeAll { ids.contains($0.id) }
        save()
    }

    func removeAll() {
        spots.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(spots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
