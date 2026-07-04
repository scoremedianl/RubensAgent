import SwiftUI

struct LoopsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var loops: [Loop] = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if loops.isEmpty {
                    Text("No loops yet").foregroundStyle(.secondary).font(.caption)
                }
                ForEach(loops) { loop in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(loop.project ?? loop.cwd).font(.body).lineLimit(1)
                            Spacer()
                            Text(loop.schedule).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Text(loop.prompt).font(.caption).lineLimit(2)
                        HStack {
                            Circle().fill(loop.enabled ? .green : .gray).frame(width: 8, height: 8)
                            if let last = loop.lastRun {
                                Text("last: \(last) · \(loop.lastStatus ?? "")").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Run") { Task { try? await app.client.runLoop(loop.id); await load() } }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { try? await app.client.deleteLoop(loop.id); await load() }
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            Task { try? await app.client.setLoopEnabled(loop.id, !loop.enabled); await load() }
                        } label: { Label("Toggle", systemImage: "power") }
                    }
                }
            }
            .navigationTitle("Loops")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                AddLoopSheet(projects: app.projects) { cwd, project, schedule, prompt, auto in
                    Task {
                        try? await app.client.addLoop(cwd: cwd, schedule: schedule, prompt: prompt,
                                                      project: project, autoApprove: auto)
                        await load()
                    }
                }
            }
        }
    }

    private func load() async { loops = (try? await app.client.loops()) ?? [] }
}

struct AddLoopSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projects: [Project]
    let onAdd: (String, String?, String, String, Bool) -> Void

    @State private var selected: Project?
    @State private var schedule = "0 8 * * *"
    @State private var prompt = ""
    @State private var auto = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("Project", selection: $selected) {
                    Text("Select…").tag(Project?.none)
                    ForEach(projects) { p in Text(p.name).tag(Project?.some(p)) }
                }
                LabeledContent("Schedule (cron)") {
                    TextField("0 8 * * *", text: $schedule).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Prompt").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Run the tests and summarise failures", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...6)
                }
                Toggle("Full auto", isOn: $auto)
            }
            .navigationTitle("New loop")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let p = selected, !prompt.isEmpty {
                            onAdd(p.path, p.name, schedule, prompt, auto)
                            dismiss()
                        }
                    }.disabled(selected == nil || prompt.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
