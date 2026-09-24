import SwiftUI

// Manage the Macs running the bridge daemon, and pick which one the app drives.
//
// Each Mac has its own token — the daemon generates one per machine on first
// run — so an entry is host + port + token together.
struct ConnectionView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var editing: MacServer?
    @State private var reachability: [String: Bool] = [:]
    @State private var testing: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.servers.isEmpty {
                        Text("No Macs yet — add the one running the bridge daemon.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(app.servers) { server in
                        row(server)
                    }
                    .onDelete { offsets in
                        offsets.map { app.servers[$0].id }.forEach(app.removeServer)
                    }
                } header: {
                    Text("Macs")
                } footer: {
                    Text("Find a Mac's token with `cat ~/.claude-bridge/token` on that machine.")
                        .font(.caption)
                }

                Section {
                    Button {
                        editing = MacServer(name: "", host: "", token: "")
                    } label: {
                        Label("Add a Mac", systemImage: "plus.circle")
                    }
                }

                Section {
                    Label(app.statusMessage, systemImage: app.reachable ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(app.reachable ? .green : .secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Macs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { server in
                ServerEditor(server: server) { saved in
                    if app.servers.contains(where: { $0.id == saved.id }) {
                        app.updateServer(saved)
                    } else {
                        app.addServer(saved)
                    }
                    Task { await test(saved) }
                }
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 320)
                #endif
            }
            .task { await testAll() }
        }
    }

    @ViewBuilder private func row(_ server: MacServer) -> some View {
        let isActive = server.id == app.server?.id
        Button {
            switchTo(server)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isActive ? Theme.accentSoft : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName).font(.body.weight(isActive ? .semibold : .regular))
                    Text("\(server.host):\(server.port)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                statusIcon(server)
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { app.removeServer(server.id) } label: {
                Label("Remove", systemImage: "trash")
            }
            Button { editing = server } label: { Label("Edit", systemImage: "pencil") }
                .tint(.gray)
        }
        .contextMenu {
            Button { editing = server } label: { Label("Edit", systemImage: "pencil") }
            Button { Task { await test(server) } } label: { Label("Test", systemImage: "bolt") }
            Button(role: .destructive) { app.removeServer(server.id) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private func statusIcon(_ server: MacServer) -> some View {
        if testing.contains(server.id) {
            ProgressView().controlSize(.small)
        } else if let ok = reachability[server.id] {
            Circle().fill(ok ? .green : .red).frame(width: 7, height: 7)
        }
    }

    private func switchTo(_ server: MacServer) {
        guard server.id != app.server?.id else { return }
        // Order matters: clear the old Mac's sessions before anything re-polls.
        manager.resetForServerSwitch()
        app.select(server.id)
        Task {
            await app.checkHealth()
            if app.reachable {
                app.startSystemPolling()
                await app.loadProjects()
                await manager.refreshTerminals()
                await app.loadAgents(force: true)
            }
        }
        dismiss()
    }

    private func test(_ server: MacServer) async {
        testing.insert(server.id)
        defer { testing.remove(server.id) }
        let client = BridgeClient(host: server.host, port: server.port, token: server.token)
        reachability[server.id] = (try? await client.health()) != nil
    }

    private func testAll() async {
        await withTaskGroup(of: Void.self) { group in
            for server in app.servers {
                group.addTask { await test(server) }
            }
        }
    }
}

// Add or edit one Mac.
private struct ServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var server: MacServer
    var onSave: (MacServer) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    LabeledContent("Name") {
                        TextField("Mac mini (kantoor)", text: $server.name)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .autocapitalization(.words)
                            #endif
                    }
                    LabeledContent("Host") {
                        TextField("100.x.x.x (Tailscale)", text: $server.host)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    LabeledContent("Port") {
                        TextField("8787", value: $server.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    LabeledContent("Token") {
                        TextField("bridge token", text: $server.token)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                    }
                }
                Section {
                    Text("Each Mac generates its own token on first run — read it with `cat ~/.claude-bridge/token` on that machine.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(server.name.isEmpty ? "Add a Mac" : server.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        server.name = server.name.trimmingCharacters(in: .whitespaces)
                        server.host = server.host.trimmingCharacters(in: .whitespaces)
                        server.token = server.token.trimmingCharacters(in: .whitespaces)
                        onSave(server)
                        dismiss()
                    }
                    .disabled(!server.isConfigured)
                }
            }
        }
    }
}
