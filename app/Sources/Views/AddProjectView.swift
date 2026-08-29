import SwiftUI

// Browse every GitHub repo you can access and clone one onto the Mac.
//
// The daemon's repo list comes from `gh api --paginate`, which takes tens of
// seconds — so we fetch the whole list once (it is cached on the daemon too)
// and filter it locally while you type. Searching never waits on the network.
struct AddProjectView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var repos: [Repo] = []
    @State private var ghAuthed = true
    @State private var loading = true
    @State private var refreshing = false
    @State private var cloning: String?
    @State private var newFolder = ""
    @State private var creatingFolder = false

    private var matches: [Repo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        // Match on owner/name and description, and let a space-separated query
        // match all its terms ("score api" finds Score-Media/customer-api).
        let terms = q.split(separator: " ").map(String.init)
        return repos.filter { repo in
            let hay = "\(repo.fullName) \(repo.description ?? "")".lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
    }

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
                Section {
                    if !ghAuthed {
                        Text("GitHub not connected — run `gh auth login` on the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if loading {
                        HStack { ProgressView().controlSize(.small); Text("Loading repos from GitHub…") }
                    } else if matches.isEmpty {
                        Text(search.isEmpty ? "No repos found." : "No repo matches “\(search)”.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(matches) { repo in row(repo) }
                    }
                } header: {
                    HStack {
                        Text(search.isEmpty ? "Clone a repo" : "\(matches.count) of \(repos.count)")
                        Spacer()
                        Button {
                            Task { await load(refresh: true) }
                        } label: {
                            if refreshing { ProgressView().controlSize(.small) }
                            else { Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(refreshing || loading)
                    }
                }
            }
            .navigationTitle("Add project")
            .searchable(text: $search, prompt: "Search all your repos")
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

    // Always fetches the unfiltered list; `matches` does the filtering.
    private func load(refresh: Bool = false) async {
        if refresh { refreshing = true } else { loading = true }
        defer { refreshing = false; loading = false }
        if let res = try? await app.client.accessibleRepos(refresh: refresh) {
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
