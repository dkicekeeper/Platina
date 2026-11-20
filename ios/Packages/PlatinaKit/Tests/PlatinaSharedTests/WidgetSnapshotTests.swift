import Foundation
import Testing
@testable import PlatinaShared

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test("Written and read back through a file")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = WidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            games: [.init(id: "NPWR1", name: "Cult of the Lamb", progress: 64, hasPlatinum: true, detail: "Осталось 21")],
            latestTrophy: .init(name: "Улыбка фортуны", gameName: "Cult of the Lamb", type: "silver", earnedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            level: 412, platinums: 41, titles: ["chase": "Иду на платину"]
        )
        WidgetSnapshotStore.write(snapshot, to: url)
        #expect(WidgetSnapshotStore.read(from: url) == snapshot)
        #expect(snapshot.title("chase") == "Иду на платину")
        #expect(snapshot.title("missing") == "missing")
    }

    @Test("Nothing to read without a file")
    func missing() {
        #expect(WidgetSnapshotStore.read(from: nil) == nil)
        #expect(WidgetSnapshotStore.read(from: URL(fileURLWithPath: "/nonexistent/snapshot.json")) == nil)
    }
}
