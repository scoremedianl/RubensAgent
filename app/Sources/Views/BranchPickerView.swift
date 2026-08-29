import SwiftUI

// Pick a branch to check out. A repo can easily have a hundred branches, which
// is unusable as a menu — so this is a searchable list, filtered locally on the
// branch names the daemon already sent us.
struct BranchPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let info: BranchInfo
    /// Called after a successful checkout so the caller can refresh its state.
    var onSwitched: (String) -> Void

    @State private var query = ""
    @State private var force = false
    @State private var busy: String?
    @State private var error: String?

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return info.branches }
        return info.branches.filter { $0.lowercased().contains(q) }
    }

    // main/develop/master first when they exist — that is what you reach for.
    private var pinned: [String] {
        ["main", "master", "develop"].filter { info.branches.contains($0) && $0 != info.current }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                    Text(info.current).font(.body.monospaced())
                    Spacer()
                    Text("current").font(.caption).foregroundStyle(.secondary)
                }
            }

            if !pinned.isEmpty && query.isEmpty {
                Section("Base branches") {
                    ForEach(pinned, id: \.self) { row($0) }
                }
            }

            Section(query.isEmpty ? "All branches (\(info.branches.count))" : "\(matches.count) match\(matches.count == 1 ? "" : "es")") {
                if matches.isEmpty {
                    Text("No branch matches “\(query)”")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(matches, id: \.self) { row($0) }
            }

            Section {
                Toggle(isOn: $force) {
                    Label("Force switch (discard local changes)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .tint(.orange)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(4)
                }
            }
        }
        .searchable(text: $query, prompt: "Search branches")
        .navigationTitle("Branches")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private func row(_ branch: String) -> some View {
        Button {
            Task { await switchTo(branch) }
        } label: {
            HStack {
                Text(branch).font(.body.monospaced()).lineLimit(1)
                Spacer()
                if busy == branch { ProgressView().controlSize(.small) }
                else if branch == info.current { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
        }
        .disabled(busy != nil || branch == info.current)
    }

    private func switchTo(_ branch: String) async {
        busy = branch
        error = nil
        defer { busy = nil }
        do {
            try await app.client.gitCheckout(cwd: project.path, branch: branch, hard: force)
            onSwitched(branch)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
