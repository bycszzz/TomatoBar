import Foundation

private struct TrackingData: Codable {
    var projects: [TBProject] = []
    var areas: [TBArea] = []
    var sessions: [TBSession] = []
}

final class TrackingStore: ObservableObject {
    static let shared = TrackingStore()

    @Published private(set) var projects: [TBProject] = []
    @Published private(set) var areas: [TBArea] = []
    @Published private(set) var sessions: [TBSession] = []

    private let ioQueue = DispatchQueue(label: "com.tomatobar.trackingstore", qos: .utility)
    private let fileURL: URL
    private let bakURL: URL

    private init() {
        let storageDir = Self.resolveStorageDirectory()
        fileURL = storageDir.appendingPathComponent("tracking.json")
        bakURL = storageDir.appendingPathComponent("tracking.json.bak")
        Self.migrateLegacyDataIfNeeded(to: fileURL)
        load()
    }

    /// Prefer iCloud Drive (auto-syncs); fall back to ~/Documents if iCloud Drive unavailable.
    private static func resolveStorageDirectory() -> URL {
        let home = NSHomeDirectory()
        let iCloudDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/TomatoBar")
        if (try? FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)) != nil,
           FileManager.default.isWritableFile(atPath: iCloudDir.path) {
            return iCloudDir
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TomatoBar")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    /// One-time migration from the old sandbox container path.
    private static func migrateLegacyDataIfNeeded(to newURL: URL) {
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }
        let legacy = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/com.github.ivoronin.TomatoBar/Data/Documents/tracking.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.copyItem(at: legacy, to: newURL)
    }

    // MARK: - Persistence

    private func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: bakURL)
            try? FileManager.default.copyItem(at: fileURL, to: bakURL)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(TrackingData.self, from: data)
        else { return }
        projects = decoded.projects
        areas = decoded.areas
        sessions = decoded.sessions
    }

    private func save() {
        let snapshot = TrackingData(projects: projects, areas: areas, sessions: sessions)
        ioQueue.async { [snapshot, fileURL = self.fileURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func flush() {
        let snapshot = TrackingData(projects: projects, areas: areas, sessions: sessions)
        ioQueue.sync { [snapshot, fileURL = self.fileURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Session API

    func appendSession(_ session: TBSession) {
        sessions.append(session)
        save()
    }

    func updateSessionNotes(id: UUID, notes: String?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].notes = notes
        save()
    }

    func sessions(in range: ClosedRange<Date>? = nil, projectId: UUID? = nil) -> [TBSession] {
        sessions.filter { s in
            if let range, !range.contains(s.startedAt) { return false }
            if let projectId, s.projectId != projectId { return false }
            return true
        }
    }

    // MARK: - Project API

    @discardableResult
    func upsertProject(_ project: TBProject) -> TBProject {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
        save()
        return project
    }

    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        areas.removeAll { $0.projectId == id }
        save()
    }

    // MARK: - Area API

    @discardableResult
    func upsertArea(_ area: TBArea) -> TBArea {
        if let idx = areas.firstIndex(where: { $0.id == area.id }) {
            areas[idx] = area
        } else {
            areas.append(area)
        }
        save()
        return area
    }

    func deleteArea(id: UUID) {
        areas.removeAll { $0.id == id }
        save()
    }

    func areas(for projectId: UUID) -> [TBArea] {
        areas.filter { $0.projectId == projectId }
    }
}
