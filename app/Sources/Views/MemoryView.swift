import SwiftUI

// Browse and edit the shared memory MD files. These live on the Mac (in
// ~/.claude/memory + the root CLAUDE.md) and are loaded into every session;
// the app only views and edits them.
struct MemoryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var files: [MemoryFile] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Loaded into every Claude session on the Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(files) { f in
                    NavigationLink {
                        MemoryEditorView(name: f.name)
                    } label: {
                        HStack {
                            Image(systemName: f.root ? "star.fill" : "doc.text")
                                .foregroundStyle(f.root ? .yellow : .secondary)
                            Text(f.name)
                            Spacer()
                            Text("\(f.sizeBytes) B").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { files = (try? await app.client.memoryFiles()) ?? [] }
        }
    }
}

struct MemoryEditorView: View {
    @EnvironmentObject var app: AppState
    let name: String
    @State private var content = ""
    @State private var loading = true
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        VStack {
            TextEditor(text: $content)
                .font(.body.monospaced())
                .padding(4)
                .overlay(alignment: .top) { if loading { ProgressView().padding() } }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        saving = true
                        try? await app.client.saveMemory(name, content: content)
                        saving = false; saved = true
                    }
                } label: {
                    if saving { ProgressView().controlSize(.small) }
                    else { Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down") }
                }
            }
        }
        .task {
            content = (try? await app.client.memoryContent(name)) ?? ""
            loading = false
        }
        .onChange(of: content) { _, _ in saved = false }
    }
}
