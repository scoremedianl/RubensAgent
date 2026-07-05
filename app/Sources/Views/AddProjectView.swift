import SwiftUI

// Browse every GitHub repo you can access and clone one onto the Mac.
struct AddProjectView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var repos: [Repo] = []
    @State private var ghAuthed = true
    @State private var loading = true
    @State private var cloning: String?
    @State private var newFolder = ""
    @State private var creatingFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section("New empty folder") {
                    HStack {
                        TextField("Folder name (no git)", text: $newFolder)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await createFolder() }
                        } label: {
                            if creatingFolder { ProgressView().controlSize(.small) }
                            else { Text("Create") }
                        }
                        .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty || creatingFolder)
                    }
                }
                Section("Clone a repo") {
                    if !ghAuthed {
                        Text("GitHub not connected — run `gh auth login` on the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(repos) { repo in row(repo) }
                        if loading { HStack { ProgressView(); Text("Loading repos…") } }
                    }
                }
            }
            .navigationTitle("Add project")
            .searchable(text: $search, prompt: "Search all your repos")
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func createFolder() async {
        creatingFolder = true
        defer { creatingFolder = false }
        try? await app.client.createFolder(name: newFolder.trimmingCharacters(in: .whitespaces))
        newFolder = ""
        await app.loadProjects()
        dismiss()
    }

    private func row(_ repo: Repo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.fullName).font(.body).lineLimit(1)
                if let d = repo.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if repo.cloned {
                Label("On Mac", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(.green)
            } else if cloning == repo.fullName {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await clone(repo) }
                } label: { Image(systemName: "arrow.down.circle") }
                .buttonStyle(.borderless)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let res = try? await app.client.accessibleRepos(search: search) {
            repos = res.repos
            ghAuthed = res.ghAuthenticated
        }
    }

    private func clone(_ repo: Repo) async {
        cloning = repo.fullName
        defer { cloning = nil }
        try? await app.client.cloneAccessible(fullName: repo.fullName)
        await app.loadProjects()
        await load()
    }
}
