import SwiftUI

// Persistent tmux-backed Claude runs: survive daemon restarts, attachable from
// any terminal. List, create, watch output, and kill them.
struct RunsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var runs: [Run] = []
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each run is a `claude` process in its own tmux session on the Mac. It keeps running even if the app or daemon restarts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if runs.isEmpty {
                    Text("No runs yet").foregroundStyle(.secondary).font(.caption)
                }
                ForEach(runs) { run in
                    NavigationLink {
                        RunDetailView(run: run) { await load() }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(run.running ? .green : .secondary).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.name).font(.body.monospaced()).lineLimit(1)
                                Text(run.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Persistent runs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showNew) {
                NewRunSheet(projects: app.projects) { await load() }
            }
        }
    }

    private func load() async { runs = (try? await app.client.runs()) ?? [] }
}

struct NewRunSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let projects: [Project]
    let onCreated: () async -> Void

    @State private var selected: Project?
    @State private var prompt = ""
    @AppStorage("session.model") private var model = ""
    @State private var starting = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Project", selection: $selected) {
                    Text("Select…").tag(Project?.none)
                    ForEach(projects) { p in Text(p.name).tag(Project?.some(p)) }
                }
                VStack(alignment: .leading) {
                    Text("Task").font(.caption).foregroundStyle(.secondary)
                    TextField("What should Claude do? (runs autonomously)", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(3...8)
                }
                Picker("Model", selection: $model) {
                    ForEach(modelOptions) { m in Text(m.label).tag(m.id) }
                }
                Label("Runs full auto", systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("New run")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }
                        .disabled(selected == nil || prompt.isEmpty || starting)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func start() {
        guard let p = selected else { return }
        starting = true
        Task {
            _ = try? await app.client.startRun(cwd: p.path, prompt: prompt,
                                               model: model, permissionMode: "bypassPermissions")
            await onCreated()
            starting = false
            dismiss()
        }
    }
}
