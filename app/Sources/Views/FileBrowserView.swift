import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

// Browse a project's files (what the AI creates), open them, and drop files in.
struct FileBrowserView: View {
    @EnvironmentObject var app: AppState
    let dirPath: String
    let title: String

    @State private var listing: FileListing?
    @State private var loading = true
    @State private var showImporter = false
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var uploading = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
        List {
            if let l = listing {
                if l.items.isEmpty && !loading {
                    Text("Empty folder").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(l.items) { item in
                    if item.isDir {
                        NavigationLink { FileBrowserView(dirPath: item.path, title: item.name) } label: { row(item) }
                    } else {
                        NavigationLink { FileViewer(path: item.path, name: item.name) } label: { row(item) }
                    }
                }
            }
            if loading { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if uploading { ProgressView().controlSize(.small) }
                Button { showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                #if os(iOS)
                PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo") }
                #endif
                Button { showImporter = true } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importFile(url) }
        }
        #if os(iOS)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await upload(data: data, name: "photo.jpg")
                }
            }
        }
        #endif
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    private func row(_ item: FileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(item))
                .foregroundStyle(item.isDir ? Theme.accent : .secondary)
                .frame(width: 22)
            Text(item.name).lineLimit(1)
            Spacer()
            if !item.isDir {
                Text(byteText(item.size)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ item: FileEntry) -> String {
        if item.isDir { return "folder.fill" }
        switch (item.name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp": return "photo"
        case "swift", "js", "ts", "py", "php", "rb", "go", "java", "kt", "c", "cpp", "h", "sh": return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml", "xml", "plist": return "curlybraces"
        case "md", "txt", "log": return "doc.text"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz": return "doc.zipper"
        default: return "doc"
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        listing = try? await app.client.listFiles(path: dirPath)
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        Task { await upload(data: data, name: url.lastPathComponent) }
    }

    private func upload(data: Data, name: String) async {
        uploading = true
        defer { uploading = false }
        try? await app.client.uploadIntoFolder(dirPath: dirPath, filename: name, dataBase64: data.base64EncodedString())
        await load()
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        newFolderName = ""
        guard !name.isEmpty else { return }
        try? await app.client.makeFolder(dirPath: dirPath, name: name)
        await load()
    }

    private func byteText(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}

struct FileViewer: View {
    @EnvironmentObject var app: AppState
    let path: String
    let name: String
    @State private var content: FileContent?
    @State private var loading = true

    var body: some View {
        Group {
            if let c = content {
                if c.kind == "image" {
                    if let data = Data(base64Encoded: c.dataBase64 ?? ""), let img = platformImage(data) {
                        ScrollView([.horizontal, .vertical]) {
                            img.resizable().scaledToFit().frame(maxWidth: .infinity)
                        }
                    } else {
                        ContentUnavailableView("Can't preview image", systemImage: "photo")
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(c.content ?? "")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            } else if loading {
                ProgressView()
            } else {
                ContentUnavailableView("Can't open file", systemImage: "doc")
            }
        }
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            content = try? await app.client.readFileContent(path: path)
            loading = false
        }
    }

    private func platformImage(_ data: Data) -> Image? {
        #if os(iOS)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #elseif os(macOS)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }
}
