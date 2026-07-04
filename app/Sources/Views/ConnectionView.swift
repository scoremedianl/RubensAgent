import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var portText = ""
    @State private var token = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac bridge") {
                    LabeledContent("Host") {
                        TextField("100.x.x.x (Tailscale)", text: $host)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    LabeledContent("Port") {
                        TextField("8787", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    LabeledContent("Token") {
                        TextField("bridge token", text: $token)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                    }
                }
                Section {
                    Button {
                        save()
                        Task { testing = true; await app.checkHealth(); testing = false }
                    } label: {
                        HStack {
                            Text("Save & test")
                            if testing { ProgressView().controlSize(.small) }
                        }
                    }
                    Label(app.statusMessage, systemImage: app.reachable ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(app.reachable ? .green : .secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear {
                host = app.host; portText = String(app.port); token = app.token
            }
        }
    }

    private func save() {
        app.host = host.trimmingCharacters(in: .whitespaces)
        app.port = Int(portText) ?? 8787
        app.token = token.trimmingCharacters(in: .whitespaces)
    }
}
