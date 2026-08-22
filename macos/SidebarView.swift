import SwiftUI
import AppKit

// MARK: - 侧栏：作品切换 + 章节 / 设定库 / 搜索 / 多会话

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(app.novels.first { $0.id == app.currentNovelID }?.title ?? "未选择书籍")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(panelTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(height: 38)
            .layoutPriority(2)
            Divider()
            Group {
                switch app.sidebarTab {
                case .books: BookList()
                case .chapters: ChapterList()
                case .lore: LoreList()
                case .search: SearchList()
                case .vectors: VectorLibraryList()
                case .conversations: ConversationList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelTitle: String {
        switch app.sidebarTab {
        case .books: return "\(app.novels.count) 本"
        case .chapters: return "\(app.chapters.count) 章"
        case .lore: return "\(app.entries.count) 条设定"
        case .search: return ""
        case .vectors: return "\(app.vectorLibraries.count) 个向量库"
        case .conversations: return "\(app.conversations.count) 个对话"
        }
    }
}

// MARK: - 书籍管理

struct BookList: View {
    @EnvironmentObject var app: AppState
    @State private var showNewBook = false
    @State private var showBookWorkspace = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showNewBook = true } label: {
                    Label("新建", systemImage: "plus")
                }
                Button { app.importBook() } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if app.currentNovelID != nil {
                    Button { showBookWorkspace = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("编辑书籍架构与创作上下文")
                    Button { app.exportCurrentBook() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("导出当前书籍")
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if app.novels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("还没有书籍")
                        .font(.system(size: 13, weight: .medium))
                    Text("新建一本，或导入 .zhinovel.json")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button("新建书籍") { showNewBook = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Button {
                        app.selectNoNovel()
                        app.sidebarTab = .conversations
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: app.currentNovelID == nil ? "lightbulb.fill" : "lightbulb")
                                .foregroundStyle(app.currentNovelID == nil ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("公共会话 · 不选择书籍")
                                    .font(.system(size: 12.5, weight: app.currentNovelID == nil ? .semibold : .regular))
                                Text("找灵感、策划或让 Agent 创建新书")
                                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            if app.currentNovelID == nil {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(app.novels) { novel in
                        Button {
                            app.selectNovel(novel.id)
                            app.sidebarTab = .chapters
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: novel.id == app.currentNovelID ? "book.closed.fill" : "book.closed")
                                    .foregroundStyle(novel.id == app.currentNovelID ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(novel.title)
                                        .font(.system(size: 12.5, weight: novel.id == app.currentNovelID ? .semibold : .regular))
                                        .lineLimit(1)
                                    Text(novel.desc.isEmpty ? "暂无简介" : novel.desc)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if novel.id == app.currentNovelID {
                                    Image(systemName: "checkmark")
                                        .font(.caption).foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("打开") {
                                app.selectNovel(novel.id)
                                app.sidebarTab = .chapters
                            }
                            Button("重命名…") { rename(novel) }
                            Button("编辑书籍架构…") {
                                app.selectNovel(novel.id)
                                showBookWorkspace = true
                            }
                            Button("导出…") {
                                app.selectNovel(novel.id)
                                app.exportCurrentBook()
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                app.selectNovel(novel.id)
                                app.confirmDeleteNovel = true
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: app.currentConversationID) { id in
                    if let id { app.selectConversation(id) }
                }
            }
        }
        .sheet(isPresented: $showNewBook) {
            NewBookSheet()
                .environmentObject(app)
        }
        .sheet(isPresented: $showBookWorkspace) {
            BookWorkspaceSheet()
                .environmentObject(app)
        }
    }

    private func rename(_ novel: Novel) {
        let alert = NSAlert()
        alert.messageText = "重命名书籍"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = novel.title
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { app.renameNovel(novel.id, title: title) }
        }
    }
}

private struct BookWorkspaceSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var desc = ""
    @State private var outline = ""
    @State private var metadata = BookMetadata()
    @State private var authors = ""
    @State private var tags = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("书籍架构").font(.title2.bold())
                    Text("书籍配置与长期创作上下文彼此独立，写作时共同提供给助手")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            TabView {
                Form {
                    Section("身份") {
                        TextField("书名", text: $title)
                        TextField("副标题", text: $metadata.subtitle)
                        TextField("作者（逗号分隔）", text: $authors)
                        TextField("笔名", text: $metadata.penName)
                        TextField("简介", text: $desc, axis: .vertical).lineLimit(2...5)
                    }
                    Section("创作配置") {
                        TextField("题材", text: Binding(
                            get: { metadata.genres.first ?? "" },
                            set: { metadata.genres = $0.isEmpty ? [] : [$0] }
                        ))
                        Picker("目标平台", selection: $metadata.platform) {
                            Text("番茄").tag("tomato")
                            Text("起点").tag("qidian")
                            Text("飞卢").tag("feilu")
                            Text("其他 / 未定").tag("other")
                        }
                        Picker("状态", selection: $metadata.status) {
                            Text("孵化中").tag("incubating")
                            Text("大纲中").tag("outlining")
                            Text("连载中").tag("active")
                            Text("暂停").tag("paused")
                            Text("已完结").tag("completed")
                            Text("已放弃").tag("dropped")
                        }
                        Picker("语言", selection: $metadata.language) {
                            Text("中文").tag("zh")
                            Text("英文").tag("en")
                            Text("简体中文（兼容）").tag("zh-CN")
                        }
                        TextField("目标章节数", value: $metadata.targetChapters, format: .number)
                        TextField("每章目标字数", value: $metadata.chapterWordCount, format: .number)
                        Picker("章节审核", selection: $metadata.reviewMode) {
                            Text("人工确认").tag("manual")
                            Text("自动通过").tag("auto")
                        }
                        TextField("标签（逗号分隔）", text: $tags)
                    }
                    Section("写法学习") {
                        Picker("写法向量库", selection: $metadata.styleLibraryID) {
                            Text("不使用写法库").tag("")
                            ForEach(app.vectorLibraries) { library in
                                Text(library.title).tag(library.id.uuidString)
                            }
                        }
                        HStack {
                            Text("学习强度")
                            Slider(value: $metadata.styleStrength, in: 0.2...1.0, step: 0.1)
                            Text("\(Int(metadata.styleStrength * 100))%")
                                .monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                        Text("只提取句长、节奏、段落、对话比例等匿名化技法；不会把参考原文交给模型照抄。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("书籍配置", systemImage: "book.closed") }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contextEditor(
                            "作者意图",
                            help: "这本书长期想成为什么；每次规划都应尊重它。",
                            text: $metadata.authorIntent,
                            height: 110
                        )
                        contextEditor(
                            "当前聚焦",
                            help: "接下来 1–3 章最需要推进或避免偏离的内容。",
                            text: $metadata.currentFocus,
                            height: 90
                        )
                        contextEditor(
                            "故事框架 / Story Frame",
                            help: "核心前提、主线冲突、世界底色和关键角色关系。",
                            text: $metadata.storyFrame,
                            height: 150
                        )
                        contextEditor(
                            "卷纲 / Volume Map",
                            help: "分卷目标与阶段性故事走向。",
                            text: $outline,
                            height: 150
                        )
                        contextEditor(
                            "本书规则",
                            help: "必须遵守的硬规则、数值上限、禁用桥段与文风约束。",
                            text: $metadata.bookRules,
                            height: 130
                        )
                    }
                    .padding(20)
                }
                .tabItem { Label("创作控制", systemImage: "scope") }

                Form {
                    Section("出版元数据（可选）") {
                        TextField("系列名", text: $metadata.seriesName)
                        TextField("系列序号", text: $metadata.seriesNumber)
                        TextField("目标读者", text: $metadata.targetAudience)
                        TextField("内容分级", text: $metadata.contentRating)
                        TextField("ISBN / 标识符", text: $metadata.isbn)
                        TextField("出版社", text: $metadata.publisher)
                        TextField("发布日期（YYYY-MM-DD）", text: $metadata.publicationDate)
                        TextField("版权声明", text: $metadata.rights)
                        TextField("来源 / 原作链接", text: $metadata.source)
                    }
                    Section("叙事标记") {
                        TextField("一句话梗概", text: $metadata.logline)
                        TextField("叙事视角", text: $metadata.pointOfView)
                        TextField("叙事时态", text: $metadata.tense)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("出版信息", systemImage: "info.circle") }
            }
            .padding(.horizontal, 6)

            Divider()
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 690, height: 720)
        .onAppear { load() }
    }

    private func contextEditor(_ label: String, help: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold))
            Text(help).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 13))
                .frame(height: height)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        }
    }

    private func split(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func load() {
        guard let novel = app.novels.first(where: { $0.id == app.currentNovelID }) else { return }
        title = novel.title
        desc = novel.desc
        outline = novel.outline
        metadata = novel.metadata
        if metadata.status == "planning" { metadata.status = "incubating" }
        authors = metadata.authors.joined(separator: ", ")
        tags = metadata.tags.joined(separator: ", ")
    }

    private func save() {
        metadata.authors = split(authors)
        metadata.tags = split(tags)
        app.updateCurrentBook(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            desc: desc,
            outline: outline,
            metadata: metadata
        )
        dismiss()
    }
}

private struct NewBookSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var author = ""
    @State private var genre = ""
    @State private var metadata = BookMetadata()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建书籍").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("书名").font(.caption).foregroundStyle(.secondary)
                TextField("例如：雾城来信", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("简介（可选）").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .font(.system(size: 13))
                    .frame(height: 78)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("作者").foregroundStyle(.secondary)
                    TextField("可选", text: $author)
                }
                GridRow {
                    Text("题材").foregroundStyle(.secondary)
                    TextField("例如：玄幻、悬疑、科幻", text: $genre)
                }
                GridRow {
                    Text("目标平台").foregroundStyle(.secondary)
                    Picker("", selection: $metadata.platform) {
                        Text("番茄").tag("tomato")
                        Text("起点").tag("qidian")
                        Text("飞卢").tag("feilu")
                        Text("其他 / 未定").tag("other")
                    }.labelsHidden()
                }
                GridRow {
                    Text("创作目标").foregroundStyle(.secondary)
                    HStack {
                        TextField("章节", value: $metadata.targetChapters, format: .number).frame(width: 70)
                        Text("章，每章")
                        TextField("字数", value: $metadata.chapterWordCount, format: .number).frame(width: 80)
                        Text("字")
                    }
                }
            }
            .font(.system(size: 12.5))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") {
                    metadata.authors = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [author]
                    metadata.genres = genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [genre]
                    app.createNovel(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    desc: description, metadata: metadata)
                    app.sidebarTab = .chapters
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
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
            .frame(height: 40)
            .layoutPriority(2)
            Divider()

            if app.conversations.isEmpty {
                Text("暂无对话")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $app.currentConversationID) {
                    ForEach(app.conversations) { c in
                        HStack(spacing: 7) {
                            runIndicator(app.conversationRunStates[c.id]?.status)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title.isEmpty ? "新对话" : c.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(statusText(app.conversationRunStates[c.id]?.status, date: c.updatedAt))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
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
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder private func runIndicator(_ status: String?) -> some View {
        switch status {
        case "queued", "running": ProgressView().controlSize(.mini).frame(width: 11)
        case "completed": Circle().fill(.green).frame(width: 7, height: 7)
        case "needs_attention": Circle().fill(.orange).frame(width: 7, height: 7)
        case "failed": Circle().fill(.red).frame(width: 7, height: 7)
        case "cancelled": Circle().fill(.gray).frame(width: 7, height: 7)
        default: Circle().fill(.clear).frame(width: 7, height: 7)
        }
    }

    private func statusText(_ status: String?, date: Date) -> String {
        switch status {
        case "queued": return "等待运行"
        case "running": return "后台运行中"
        case "completed": return "已完成 · \(relativeTime(date))"
        case "needs_attention": return "需要处理"
        case "failed": return "运行失败"
        case "cancelled": return "已取消"
        default: return relativeTime(date)
        }
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

    private var chapterSelection: Binding<UUID?> {
        Binding(get: { app.selectedChapterID }, set: { app.selectChapter($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                app.showBookWorkspace()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.grid.2x2")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("书籍工作台").font(.system(size: 12.5, weight: .semibold))
                        Text("大纲 · 卷纲 · 人物 · 剧情卡片").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(app.contentEditingMode == .book ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            if app.chapters.isEmpty {
                Spacer()
                Text("暂无章节")
                    .font(.caption).foregroundStyle(.secondary)
                Text("点击下方「＋」或 ⌘⇧N 新建")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.top, 2)
                Spacer()
            } else {
                List(selection: chapterSelection) {
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
                .scrollContentBackground(.hidden)
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
            .frame(height: 40)
            .layoutPriority(2)
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
                .scrollContentBackground(.hidden)
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
                .frame(height: 40)
                .layoutPriority(2)
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
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - 本地向量库

struct VectorLibraryList: View {
    @EnvironmentObject var app: AppState
    @State private var librarySearchText = ""
    @State private var librarySearchResults: [VectorLibrary] = []
    @State private var editingLibrary: VectorLibrary?

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

                Button { app.refreshVectorLibraries() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新本地数据库，无需重启 App")
                .disabled(app.vectorImporting)
                Spacer()
                if app.vectorImporting { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(height: 40)
            .layoutPriority(2)

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
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("按书名、作者、分类、ID 或简介搜索", text: $librarySearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                    if !librarySearchText.isEmpty {
                        Button { librarySearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 10).padding(.vertical, 8)

                List(selection: $app.selectedVectorLibraryID) {
                    Section("向量库") {
                        ForEach(visibleLibraries) { library in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(library.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text([library.author.isEmpty ? nil : library.author,
                                      library.category.isEmpty ? nil : library.category,
                                      library.wordCount > 0 ? formattedWordCount(library.wordCount) : nil,
                                      "\(library.chapterCount) 章 · \(library.chunkCount) 个片段"]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                if !library.summary.isEmpty {
                                    Text(library.summary)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            .tag(library.id)
                            .contextMenu {
                                Button("编辑书籍信息…") { editingLibrary = library }
                                Button("从 TXT 刷新书籍信息") { app.refreshVectorLibraryMetadata(library) }
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
                .scrollContentBackground(.hidden)

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
        .onChange(of: librarySearchText) { _ in refreshLibrarySearch() }
        .onChange(of: app.vectorLibraries) { _ in refreshLibrarySearch() }
        .sheet(item: $editingLibrary) { library in
            VectorLibraryInfoSheet(library: library) { title, author, category, summary in
                if app.updateVectorLibrary(library, title: title, author: author,
                                           category: category, summary: summary) {
                    editingLibrary = nil
                    refreshLibrarySearch()
                }
            }
        }
    }

    private var visibleLibraries: [VectorLibrary] {
        librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? app.vectorLibraries : librarySearchResults
    }

    private func refreshLibrarySearch() {
        librarySearchResults = VectorStore().searchLibraries(librarySearchText)
    }

    private func formattedWordCount(_ count: Int) -> String {
        count >= 10_000 ? String(format: "%.1f 万字", Double(count) / 10_000) : "\(count) 字"
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

private struct VectorLibraryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let library: VectorLibrary
    let onSave: (String, String, String, String) -> Void
    @State private var title: String
    @State private var author: String
    @State private var category: String
    @State private var summary: String

    init(library: VectorLibrary, onSave: @escaping (String, String, String, String) -> Void) {
        self.library = library
        self.onSave = onSave
        _title = State(initialValue: library.title)
        _author = State(initialValue: library.author)
        _category = State(initialValue: library.category)
        _summary = State(initialValue: library.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("写法库书籍信息").font(.headline)
            Text("下载文件缺失的分类可在这里补充；这些内容只用于本地目录与定向搜索。")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                TextField("书名", text: $title)
                TextField("作者", text: $author)
                TextField("分类，如：都市 / 玄幻 / 悬疑", text: $category)
                if !library.externalID.isEmpty || library.wordCount > 0 {
                    HStack {
                        if !library.externalID.isEmpty { Text("书籍 ID：\(library.externalID)") }
                        Spacer()
                        if library.wordCount > 0 {
                            Text(library.wordCount >= 10_000
                                 ? String(format: "%.1f 万字", Double(library.wordCount) / 10_000)
                                 : "\(library.wordCount) 字")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("简介（建议 200–500 字）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $summary)
                        .font(.system(size: 12.5))
                        .frame(minHeight: 135)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    Text("\(summary.count) / 800 字")
                        .font(.caption2)
                        .foregroundStyle(summary.count > 800 ? Color.orange : Color.gray)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            HStack {
                Text(library.sourcePath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { onSave(title, author, category, String(summary.prefix(800))) }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}

func entryTypeIcon(_ id: String) -> String {
    ENTRY_TYPES.first { $0.id == id }?.icon ?? "square.grid.2x2"
}
