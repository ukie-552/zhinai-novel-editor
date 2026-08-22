import SwiftUI

// MARK: - 书籍编辑模式

private enum BookCoreSection: String, Identifiable {
    case overview, outline, direction, rules, publishing
    var id: String { rawValue }
}

struct BookCardsView: View {
    @EnvironmentObject var app: AppState
    @State private var searchText = ""
    @State private var category = "全部"
    @State private var editingNode: StoryNode?
    @State private var coreSection: BookCoreSection?

    private var novel: Novel? { app.novels.first { $0.id == app.currentNovelID } }
    private var categories: [String] { ["全部", "整书", "设定"] + Array(Set(STORY_NODE_KINDS.map(\.category))).sorted() }
    private var visibleNodes: [StoryNode] {
        app.storyNodes.filter { node in
            let kind = storyNodeKind(node.kind)
            let categoryMatches = category == "全部" || kind.category == category
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return categoryMatches && (query.isEmpty || node.title.localizedCaseInsensitiveContains(query)
                || node.content.localizedCaseInsensitiveContains(query) || kind.label.localizedCaseInsensitiveContains(query))
        }
    }
    private var visibleEntries: [Entry] {
        guard category == "全部" || category == "设定" else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.entries.filter { entry in
            query.isEmpty || entry.title.localizedCaseInsensitiveContains(query)
                || entry.content.localizedCaseInsensitiveContains(query)
                || entryTypeLabel(entry.type).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let novel {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 14)], spacing: 14) {
                        if category == "全部" || category == "整书" {
                            coreCard("故事总览", icon: "book.closed", category: "整书",
                                     preview: novel.metadata.logline.isEmpty ? novel.desc : novel.metadata.logline, section: .overview)
                            coreCard("全书大纲", icon: "map", category: "整书",
                                     preview: novel.outline, section: .outline)
                            coreCard("创作方向", icon: "scope", category: "整书",
                                     preview: novel.metadata.currentFocus.isEmpty ? novel.metadata.authorIntent : novel.metadata.currentFocus, section: .direction)
                            coreCard("本书规则", icon: "checklist.checked", category: "整书",
                                     preview: novel.metadata.bookRules, section: .rules)
                            coreCard("出版与目标", icon: "target", category: "整书",
                                     preview: publishingPreview(novel), section: .publishing)
                        }
                        ForEach(visibleEntries) { entry in
                            LoreReferenceCard(entry: entry) {
                                app.editingEntry = entry
                                app.showEntrySheet = true
                            } onDelete: {
                                app.deleteEntry(entry.id)
                            }
                        }
                        ForEach(visibleNodes) { node in
                            StoryNodeCard(node: node, parentTitle: parentTitle(node)) {
                                editingNode = node
                            } onDelete: {
                                app.deleteStoryNode(node)
                            }
                        }
                    }
                    .padding(18)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            }
        }
        .sheet(item: $editingNode) { node in
            StoryNodeEditorSheet(node: node)
                .environmentObject(app)
        }
        .sheet(item: $coreSection) { section in
            if let novel {
                BookCoreEditorSheet(novel: novel, initialSection: section)
                    .environmentObject(app)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("书籍工作台").font(.system(size: 14, weight: .semibold))
                Text("整书规划 \(app.storyNodes.count) 张 · 设定引用 \(app.entries.count) 张")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("搜索卡片…", text: $searchText)
                .textFieldStyle(.roundedBorder).frame(width: 170)
            Picker("分类", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 96)
            Menu {
                Menu("规划卡") {
                    ForEach(Array(Dictionary(grouping: STORY_NODE_KINDS, by: \.category).keys).sorted(), id: \.self) { group in
                        Menu(group) {
                            ForEach(STORY_NODE_KINDS.filter { $0.category == group }) { kind in
                                Button {
                                    if let node = app.createStoryNode(kind: kind.id) { editingNode = node }
                                } label: { Label(kind.label, systemImage: kind.icon) }
                            }
                        }
                    }
                }
                Menu("设定卡（与设定库同步）") {
                    ForEach(ENTRY_TYPES) { type in
                        Button { app.createEntry(type: type.id) } label: {
                            Label(type.label, systemImage: type.icon)
                        }
                    }
                }
            } label: {
                Label("新建卡片", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private func coreCard(_ title: String, icon: String, category: String, preview: String,
                          section: BookCoreSection) -> some View {
        Button { coreSection = section } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(category).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "点击补充内容" : preview)
                    .font(.system(size: 12)).foregroundStyle(preview.isEmpty ? .tertiary : .secondary)
                    .lineLimit(5).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack {
                    Text("整书资料").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func parentTitle(_ node: StoryNode) -> String? {
        guard let parentID = node.parentID else { return nil }
        return app.storyNodes.first { $0.id == parentID }?.title
    }

    private func publishingPreview(_ novel: Novel) -> String {
        let m = novel.metadata
        let values = [m.genres.joined(separator: " / "), m.targetAudience,
                      m.targetWordCount > 0 ? "目标 \(m.targetWordCount) 字" : "",
                      m.targetChapters > 0 ? "\(m.targetChapters) 章" : ""].filter { !$0.isEmpty }
        return values.joined(separator: " · ")
    }
}

private struct LoreReferenceCard: View {
    let entry: Entry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let definition = ENTRY_TYPES.first { $0.id == entry.type }
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(definition?.label ?? "设定", systemImage: definition?.icon ?? "books.vertical")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if entry.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                    Text("设定库").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.purple)
                }
                Text(entry.title.isEmpty ? "未命名设定" : entry.title)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(entry.content.isEmpty ? "点击填写设定内容" : entry.content)
                    .font(.system(size: 12)).foregroundStyle(entry.content.isEmpty ? .tertiary : .secondary)
                    .lineLimit(4).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack {
                    Text(entry.keywords.isEmpty ? "唯一数据源：设定库" : "触发词：\(entry.keywords)")
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer()
                    Menu {
                        Button("编辑", action: onEdit)
                        Divider()
                        Button("删除", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", action: onEdit)
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

private struct StoryNodeCard: View {
    let node: StoryNode
    let parentTitle: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let kind = storyNodeKind(node.kind)
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(kind.label, systemImage: kind.icon).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(statusLabel(node.status)).font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(statusColor(node.status))
                }
                Text(node.title.isEmpty ? "未命名卡片" : node.title)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(node.content.isEmpty ? "点击填写卡片内容" : node.content)
                    .font(.system(size: 12)).foregroundStyle(node.content.isEmpty ? .tertiary : .secondary)
                    .lineLimit(4).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack {
                    Text(parentTitle.map { "归属：\($0)" } ?? kind.category)
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer()
                    Menu {
                        Button("编辑", action: onEdit)
                        Divider()
                        Button("删除", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", action: onEdit)
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private func statusLabel(_ value: String) -> String {
        ["draft": "草稿", "active": "进行中", "resolved": "已完成", "archived": "已归档"][value] ?? value
    }
    private func statusColor(_ value: String) -> Color {
        switch value { case "active": return .blue; case "resolved": return .green; case "archived": return .secondary; default: return .orange }
    }
}

private struct StoryNodeEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let node: StoryNode
    @State private var kind: String
    @State private var title: String
    @State private var content: String
    @State private var status: String
    @State private var parentID: UUID?
    @State private var sortOrder: Int
    @State private var metadataJSON: String
    @State private var showDelete = false
    @State private var validationMessage = ""

    init(node: StoryNode) {
        self.node = node
        _kind = State(initialValue: node.kind); _title = State(initialValue: node.title)
        _content = State(initialValue: node.content); _status = State(initialValue: node.status)
        _parentID = State(initialValue: node.parentID); _sortOrder = State(initialValue: node.sortOrder)
        _metadataJSON = State(initialValue: node.metadataJSON)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("编辑创作卡片", systemImage: storyNodeKind(kind).icon).font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(title.trimmed.isEmpty)
            }.padding(16)
            Divider()
            Form {
                Picker("卡片类型", selection: $kind) {
                    ForEach(STORY_NODE_KINDS) { Text("\($0.category) · \($0.label)").tag($0.id) }
                }
                TextField("标题", text: $title)
                Picker("状态", selection: $status) {
                    Text("草稿").tag("draft"); Text("进行中").tag("active")
                    Text("已完成").tag("resolved"); Text("已归档").tag("archived")
                }
                Picker("父级卡片", selection: $parentID) {
                    Text("无").tag(UUID?.none)
                    ForEach(app.storyNodes.filter { $0.id != node.id }) { item in
                        Text("\(storyNodeKind(item.kind).label) · \(item.title)").tag(Optional(item.id))
                    }
                }
                Stepper("排序：\(sortOrder)", value: $sortOrder, in: -9999...9999)
                VStack(alignment: .leading) {
                    Text("内容").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $content).font(.system(size: 13)).frame(minHeight: 250)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                }
                DisclosureGroup("结构化附加信息（JSON）") {
                    TextEditor(text: $metadataJSON).font(.system(.caption, design: .monospaced)).frame(minHeight: 80)
                    if !validationMessage.isEmpty { Text(validationMessage).foregroundStyle(.red).font(.caption) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("删除卡片", role: .destructive) { showDelete = true }
                Spacer()
                Text("用户与 Agent 共用此卡片，保存前自动生成版本")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }
        .frame(minWidth: 620, minHeight: 620)
        .confirmationDialog("确定删除《\(node.title)》？", isPresented: $showDelete) {
            Button("删除", role: .destructive) { app.deleteStoryNode(node); dismiss() }
        }
    }

    private func save() {
        let raw = metadataJSON.trimmed.isEmpty ? "{}" : metadataJSON
        guard let data = raw.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else {
            validationMessage = "附加信息不是有效 JSON"; return
        }
        app.updateStoryNode(node, kind: kind, title: title.trimmed, content: content, status: status,
                            parentID: parentID, sortOrder: sortOrder, metadataJSON: raw)
        dismiss()
    }
}

private struct BookCoreEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let initialSection: BookCoreSection
    @State private var title: String
    @State private var desc: String
    @State private var outline: String
    @State private var metadata: BookMetadata

    init(novel: Novel, initialSection: BookCoreSection) {
        self.initialSection = initialSection
        _title = State(initialValue: novel.title); _desc = State(initialValue: novel.desc)
        _outline = State(initialValue: novel.outline); _metadata = State(initialValue: novel.metadata)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("书籍核心资料").font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(title.trimmed.isEmpty)
            }.padding(16)
            Divider()
            Form {
                Section("基本信息") {
                    TextField("书名", text: $title); TextField("副标题", text: $metadata.subtitle)
                    TextField("一句话梗概", text: $metadata.logline)
                    longEditor("书籍简介", text: $desc, height: 90)
                }
                Section("故事架构") {
                    longEditor("全书大纲", text: $outline, height: initialSection == .outline ? 240 : 140)
                    longEditor("故事框架", text: $metadata.storyFrame, height: 90)
                }
                Section("创作方向") {
                    longEditor("作者意图", text: $metadata.authorIntent, height: 80)
                    longEditor("当前聚焦", text: $metadata.currentFocus, height: 80)
                    TextField("主题（逗号分隔）", text: listBinding(\.themes))
                    TextField("目标读者", text: $metadata.targetAudience)
                    TextField("叙事视角", text: $metadata.pointOfView)
                    TextField("时态", text: $metadata.tense)
                }
                Section("写作约束") {
                    longEditor("本书规则", text: $metadata.bookRules, height: initialSection == .rules ? 180 : 100)
                    TextField("题材（逗号分隔）", text: listBinding(\.genres))
                    TextField("标签（逗号分隔）", text: listBinding(\.tags))
                    Stepper("目标章节：\(metadata.targetChapters)", value: $metadata.targetChapters, in: 0...10000)
                    Stepper("每章目标字数：\(metadata.chapterWordCount)", value: $metadata.chapterWordCount, in: 0...100000, step: 100)
                    TextField("全书目标字数", value: $metadata.targetWordCount, format: .number)
                }
                Section("作者与出版") {
                    TextField("作者（逗号分隔）", text: listBinding(\.authors))
                    TextField("笔名", text: $metadata.penName); TextField("系列名", text: $metadata.seriesName)
                    TextField("出版社", text: $metadata.publisher); TextField("ISBN", text: $metadata.isbn)
                    TextField("版权信息", text: $metadata.rights)
                }
            }.formStyle(.grouped)
            HStack {
                Text("此处只编辑整书资料；章节正文请从左侧选择章节进入。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(14)
        }.frame(minWidth: 700, minHeight: 720)
    }

    private func longEditor(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).frame(minHeight: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
        }
    }
    private func listBinding(_ keyPath: WritableKeyPath<BookMetadata, [String]>) -> Binding<String> {
        Binding(get: { metadata[keyPath: keyPath].joined(separator: ", ") }, set: { value in
            metadata[keyPath: keyPath] = value.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        })
    }
    private func save() {
        app.updateCurrentBook(title: title.trimmed, desc: desc, outline: outline, metadata: metadata)
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
