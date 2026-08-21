import SwiftUI
import AppKit

// MARK: - 侧栏：作品切换 + 章节 / 设定库 / 搜索 / 多会话

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(app.novels.first { $0.id == app.currentNovelID }?.title ?? "未选择作品")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(panelTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            switch app.sidebarTab {
            case .chapters: ChapterList()
            case .lore: LoreList()
            case .search: SearchList()
            case .vectors: VectorLibraryList()
            case .conversations: ConversationList()
            }
        }
    }

    private var panelTitle: String {
        switch app.sidebarTab {
        case .chapters: return "\(app.chapters.count) 章"
        case .lore: return "\(app.entries.count) 条设定"
        case .search: return ""
        case .vectors: return "\(app.vectorLibraries.count) 个向量库"
        case .conversations: return "\(app.conversations.count) 个对话"
        }
    }
}

// MARK: - 多会话（与搜索同级的侧栏入口）

struct ConversationList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    app.createConversation()
                } label: {
                    Label("新建对话", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("⌥⌘N")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if app.conversations.isEmpty {
                Text("暂无对话")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $app.currentConversationID) {
                    ForEach(app.conversations) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title.isEmpty ? "新对话" : c.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Text(relativeTime(c.updatedAt))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        .tag(c.id)
                        .contextMenu {
                            Button("重命名…") { rename(c) }
                            Divider()
                            Button("删除对话", role: .destructive) {
                                app.currentConversationID = c.id
                                app.deleteConversation()
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func rename(_ conversation: Conversation) {
        let alert = NSAlert()
        alert.messageText = "重命名对话"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = conversation.title
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            app.renameConversation(conversation.id, title: field.stringValue)
        }
    }
}

// MARK: - 章节树

struct ChapterList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            if app.chapters.isEmpty {
                Spacer()
                Text("暂无章节")
                    .font(.caption).foregroundStyle(.secondary)
                Text("点击下方「＋」或 ⌘⇧N 新建")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.top, 2)
                Spacer()
            } else {
                List(selection: $app.selectedChapterID) {
                    ForEach(app.chapters) { c in
                        HStack(spacing: 8) {
                            Text("\(c.no)")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(c.title.isEmpty ? "（无标题）" : c.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .tag(c.id)
                        .contextMenu {
                            Button("上移") { app.moveChapter(-1) }
                            Button("下移") { app.moveChapter(1) }
                            Divider()
                            Button("删除章节", role: .destructive) { app.deleteChapter() }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            HStack {
                Button {
                    app.createChapter()
                } label: {
                    Label("新章节", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(app.chapters.count) 章")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
    }
}

// MARK: - 设定库（世界书）

struct LoreList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("搜索设定…", text: $app.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { app.refreshSearch() }
                Button {
                    app.createEntry()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建设定")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            if app.entries.isEmpty {
                Spacer()
                Text("设定库是作品的「世界书」\n人物、地点、世界观…写作时自动注入")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                List {
                    ForEach(app.entries) { e in
                        Button {
                            app.editingEntry = e
                            app.showEntrySheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: entryTypeIcon(e.type))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 15)
                                Text(e.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer()
                                if e.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - 搜索

struct SearchList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索设定与章节…", text: $app.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .onChange(of: app.searchText) { _ in app.refreshSearch() }
            if app.searchText.isEmpty {
                Spacer()
                Text("输入关键词，全文搜索\n当前作品的设定库与章节")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                List {
                    Section("设定") {
                        ForEach(app.searchResults.entries) { e in
                            Button {
                                app.editingEntry = e
                                app.showEntrySheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: entryTypeIcon(e.type))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(e.title).font(.system(size: 12.5)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if app.searchResults.entries.isEmpty {
                            Text("无匹配").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Section("章节") {
                        ForEach(app.searchResults.chapters) { c in
                            Button {
                                app.selectedChapterID = c.id
                                app.sidebarTab = .chapters
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(c.no)")
                                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    Text(c.title.isEmpty ? "（无标题）" : c.title)
                                        .font(.system(size: 12.5)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if app.searchResults.chapters.isEmpty {
                            Text("无匹配").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - 本地向量库

struct VectorLibraryList: View {
    @EnvironmentObject var app: AppState

    private let bundledFanqieTXT = URL(fileURLWithPath: "/Users/Zhuanz/Downloads/FanqieNovels/什么叫我洗白后，她们全部黑化了 - 黑暗加鲁鲁兽.txt")

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    importDefaultTXT()
                } label: {
                    Label("导入 TXT", systemImage: "arrow.down.doc")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .disabled(app.vectorImporting)

                Button { chooseTXT() } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("选择其他 TXT 文件")
                .disabled(app.vectorImporting)
                Spacer()
                if app.vectorImporting { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !app.vectorImportMessage.isEmpty {
                Text(app.vectorImportMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(app.vectorImportMessage.hasPrefix("导入失败") ? .orange : .secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.bottom, 7)
            }

            Divider()

            if app.vectorLibraries.isEmpty {
                Spacer()
                Image(systemName: "cube.transparent")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("本地向量库")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.top, 8)
                Text("导入 TXT 后按章节分块并建立本地向量索引。\n正文不会上传到网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                Spacer()
            } else {
                List(selection: $app.selectedVectorLibraryID) {
                    Section("向量库") {
                        ForEach(app.vectorLibraries) { library in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(library.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text("\(library.chapterCount) 章 · \(library.chunkCount) 个片段")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(library.id)
                            .contextMenu {
                                Button("在 Finder 中显示源文件") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: library.sourcePath)])
                                }
                                Divider()
                                Button("删除向量库", role: .destructive) { app.deleteVectorLibrary(library) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()
                VStack(spacing: 7) {
                    TextField("语义检索当前向量库…", text: $app.vectorSearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .onSubmit { app.searchVectors() }
                    if !app.vectorSearchResults.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(app.vectorSearchResults) { result in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("第\(result.chapterNo)章 · \(result.chapterTitle)")
                                            .font(.system(size: 10.5, weight: .semibold))
                                        Text(result.content)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                }
                            }
                        }
                        .frame(maxHeight: 190)
                    }
                }
                .padding(10)
            }
        }
        .onChange(of: app.selectedVectorLibraryID) { id in
            app.selectVectorLibrary(id)
            if !app.vectorSearchText.isEmpty { app.searchVectors() }
        }
    }

    private func importDefaultTXT() {
        guard FileManager.default.fileExists(atPath: bundledFanqieTXT.path) else {
            app.vectorImportMessage = "未找到默认 TXT 文件，请手动选择文件"
            return
        }
        app.importVectorTXT(bundledFanqieTXT, expectedChapterCount: 346)
    }

    private func chooseTXT() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = bundledFanqieTXT.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            app.importVectorTXT(url)
        }
    }
}

func entryTypeIcon(_ id: String) -> String {
    ENTRY_TYPES.first { $0.id == id }?.icon ?? "square.grid.2x2"
}
