import SwiftUI

// Pick the model for a new session.
//
// Claude has six presets, but OpenCode reports whatever its provider offers —
// with OpenRouter connected that is several hundred. A menu is useless at that
// size, so this is a searchable list grouped by provider, with each model
// coloured by family so you can spot the one you want without reading every row.
struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind
    let options: [ModelOption]
    @Binding var selection: String

    @State private var query = ""

    private var matches: [ModelOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        let terms = q.split(separator: " ").map(String.init)
        return options.filter { opt in
            let hay = "\(opt.id) \(opt.label)".lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
    }

    /// "Default" stays pinned; the rest group under their provider prefix.
    private var groups: [(name: String, models: [ModelOption])] {
        var byProvider: [String: [ModelOption]] = [:]
        for m in matches where !m.id.isEmpty {
            byProvider[m.provider ?? "Models", default: []].append(m)
        }
        return byProvider
            .map { (name: $0.key, models: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var showsDefault: Bool { matches.contains { $0.id.isEmpty } }

    var body: some View {
        List {
            if showsDefault {
                Section {
                    row(ModelOption(id: "", label: "Default"),
                        subtitle: "Whatever \(agent.label) is configured to use")
                }
            }
            if matches.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                }
            }
            ForEach(groups, id: \.name) { group in
                Section {
                    ForEach(group.models) { row($0) }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.models.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search \(options.count) models")
        .navigationTitle("Model")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(_ option: ModelOption, subtitle: String? = nil) -> some View {
        let family = ModelFamily.of(option.id)
        let chosen = option.id == selection
        return Button {
            selection = option.id
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: family.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(family.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.id.isEmpty ? option.label : ModelChip.prettyName(option.id))
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if option.id.contains("/") {
                        Text(option.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(agent.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
