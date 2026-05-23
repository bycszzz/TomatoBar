import Foundation

enum TBProjectStatus: String, Codable {
    case active, completed, archived
}

enum TBSessionType: String, Codable {
    case work, rest
}

struct TBProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var status: TBProjectStatus
    var createdAt: Date
    var completedAt: Date?

    init(name: String) {
        id = UUID()
        self.name = name
        status = .active
        createdAt = Date()
        completedAt = nil
    }
}

struct TBArea: Codable, Identifiable {
    var id: UUID
    var projectId: UUID
    var name: String

    init(projectId: UUID, name: String) {
        id = UUID()
        self.projectId = projectId
        self.name = name
    }
}

struct TBSession: Codable, Identifiable {
    var id: UUID
    var projectId: UUID?
    var areaId: UUID?
    var startedAt: Date
    var endedAt: Date
    var plannedDuration: TimeInterval
    var actualDuration: TimeInterval
    var type: TBSessionType
    var completed: Bool
    var notes: String?
}
