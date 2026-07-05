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

    var body: some View {
        NavigationStack {
            Group {
                if !ghAuthed {
                    ContentUnavailableView("GitHub not connected", systemImage: "person.crop.circle.badge.xmark",
                        description: Text("Run `gh auth login` on the Mac to browse your repos."))
                } else {
                    List {
                        ForEach(repos) { repo in
                            row(repo)
                        }
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
