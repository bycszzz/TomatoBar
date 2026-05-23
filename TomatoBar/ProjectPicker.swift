import SwiftUI

// MARK: - Popover row

struct ProjectPicker: View {
    @EnvironmentObject private var timer: TBTimer
    @ObservedObject private var store = TrackingStore.shared
    @State private var showManager = false

    private var activeProjects: [TBProject] {
        store.projects.filter { $0.status == .active }
    }

    private var projectAreas: [TBArea] {
        guard let id = timer.currentProjectId else { return [] }
        return store.areas(for: id)
    }

    var body: some View {
        HStack(spacing: 4) {
            Picker(selection: Binding(
                get: { timer.currentProjectIdStr },
                set: {
                    if $0 != timer.currentProjectIdStr { timer.currentAreaIdStr = "" }
                    timer.currentProjectIdStr = $0
                }
            ), label: EmptyView()) {
                Text("Unassigned").tag("")
                if !activeProjects.isEmpty {
                    Divider()
                    ForEach(activeProjects) { p in
                        Text(p.name).tag(p.id.uuidString)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if !projectAreas.isEmpty {
                Picker(selection: Binding(
                    get: { timer.currentAreaIdStr },
                    set: { timer.currentAreaIdStr = $0 }
                ), label: EmptyView()) {
                    Text("All areas").tag("")
                    Divider()
                    ForEach(projectAreas) { a in
                        Text(a.name).tag(a.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Button { showManager = true } label: {
                Image(systemName: "folder.badge.gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Manage projects")
        }
        .sheet(isPresented: $showManager) {
            ProjectManagerSheet()
        }
    }
}

// MARK: - Manager sheet

struct ProjectManagerSheet: View {
    @ObservedObject private var store = TrackingStore.shared
    @State private var newProjectName = ""
    @Environment(\.dismiss) private var dismiss

    private var activeProjects: [TBProject] {
        store.projects.filter { $0.status == .active }
    }

    private var inactiveProjects: [TBProject] {
        store.projects.filter { $0.status != .active }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if activeProjects.isEmpty && inactiveProjects.isEmpty {
                        Text("No projects yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }

                    ForEach(activeProjects) { project in
                        ProjectRowView(project: project)
                        Divider().padding(.leading, 28)
                    }

                    // New project input
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        TextField("New project…", text: $newProjectName)
                            .textFieldStyle(.plain)
                            .onSubmit(createProject)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if !inactiveProjects.isEmpty {
                        Divider()
                        Text("Completed / Archived")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        ForEach(inactiveProjects) { project in
                            ProjectRowView(project: project)
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300, height: 380)
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.upsertProject(TBProject(name: name))
        newProjectName = ""
    }
}

// MARK: - Project row

private struct ProjectRowView: View {
    let project: TBProject
    @ObservedObject private var store = TrackingStore.shared
    @State private var expanded = false
    @State private var newAreaName = ""
    @State private var showDeleteAlert = false
    @State private var showRetro = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: "folder.fill")
                    .foregroundColor(project.status == .active ? .accentColor : .secondary)

                Text(project.name)
                    .strikethrough(project.status == .archived)
                    .foregroundColor(project.status == .archived ? .secondary : .primary)

                Spacer()

                let count = store.areas(for: project.id).count
                if count > 0 {
                    Text("\(count) area\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if project.status != .active {
                    Button {
                        showRetro = true
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("View retrospective")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .contextMenu { projectContextMenu }

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.areas(for: project.id)) { area in
                        AreaRowView(area: area)
                    }
                    if project.status == .active {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            TextField("New area…", text: $newAreaName)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .onSubmit(createArea)
                        }
                        .padding(.leading, 32)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color.secondary.opacity(0.05))
            }
        }
        .sheet(isPresented: $showRetro) {
            ProjectRetroView(project: project)
        }
        .alert("Delete \"\(project.name)\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { store.deleteProject(id: project.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past sessions will be kept but no longer linked to this project.")
        }
    }

    @ViewBuilder
    private var projectContextMenu: some View {
        if project.status == .active {
            Button("Mark Completed") {
                var p = project
                p.status = .completed
                p.completedAt = Date()
                store.upsertProject(p)
            }
            Button("Archive") {
                var p = project
                p.status = .archived
                store.upsertProject(p)
            }
        } else {
            Button("Restore to Active") {
                var p = project
                p.status = .active
                p.completedAt = nil
                store.upsertProject(p)
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { showDeleteAlert = true }
    }

    private func createArea() {
        let name = newAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.upsertArea(TBArea(projectId: project.id, name: name))
        newAreaName = ""
    }
}

// MARK: - Area row

private struct AreaRowView: View {
    let area: TBArea
    @ObservedObject private var store = TrackingStore.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(area.name)
                .font(.callout)
            Spacer()
            Button {
                store.deleteArea(id: area.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }
}
