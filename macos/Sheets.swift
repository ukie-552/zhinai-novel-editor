import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UniformTypeIdentifiers

// MARK: - 设定编辑（世界书条目）

struct EntrySheet: View {
    @EnvironmentObject var app: AppState
    @State private var type = "character"
    @State private var title = ""
    @State private var content = ""
    @State private var keywords = ""
    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(app.editingEntry == nil ? "新建设定" : "编辑设定")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    app.showEntrySheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Picker("类型", selection: $type) {
                    ForEach(ENTRY_TYPES) { t in
                        Label(t.label, systemImage: t.icon).tag(t.id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                TextField("名称（如：林晚舟）", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                TextField("触发关键词（逗号分隔）——对话/写作中出现关键词时自动注入本条设定", text: $keywords)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            TextEditor(text: $content)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                .frame(minHeight: 200, maxHeight: .infinity)

            Toggle(isOn: $pinned) {
                Label("固定引用（始终加入对话上下文）", systemImage: "pin")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            HStack {
                if app.editingEntry != nil {
                    Button("删除", role: .destructive) {
                        if let e = app.editingEntry { app.deleteEntry(e.id) }
                    }
                }
                Spacer()
                Button("取消") { app.showEntrySheet = false }
                Button("保存") {
                    app.saveEntry(type: type, title: title, content: content,
                                  keywords: keywords, pinned: pinned)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 500)
        .onAppear {
            if let e = app.editingEntry {
                type = e.type; title = e.title; content = e.content
                keywords = e.keywords; pinned = e.pinned
            } else {
                type = "character"; title = ""; content = ""; keywords = ""; pinned = false
            }
        }
    }
}

// MARK: - Agent 管理

struct AgentSheet: View {
    @EnvironmentObject var app: AppState
    @State private var filter: AgentFilter = .all
    @State private var searchText = ""

    private enum AgentFilter: String, CaseIterable, Identifiable {
        case all = "全部 Agent"
        case builtin = "内置模板"
        case custom = "我的 Agent"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .builtin: return "sparkles.rectangle.stack"
            case .custom: return "person.crop.circle"
            }
        }
    }

    private var builtinAgents: [Agent] { app.agents.filter(\.isBuiltin) }
    private var customAgents: [Agent] { app.agents.filter { !$0.isBuiltin } }
    private var visibleBuiltinAgents: [Agent] { searched(builtinAgents) }
    private var visibleCustomAgents: [Agent] { searched(customAgents) }
    private let gridColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 360), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .frame(width: 940, height: 640)
        .sheet(isPresented: $app.showAgentEditor) { AgentEditor() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.crop.square.stack.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent 工作室")
                    .font(.system(size: 16, weight: .bold))
                Text("为写作任务配置人格、模型与能力")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                app.showAgentSheet = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: startCreate) {
                Label("新建 Agent", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 8) {
                Button(action: startAIGeneration) {
                    Label("快速创建", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    app.showSkillManager = true
                } label: {
                    Label("技能库", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            Text("浏览")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(AgentFilter.allCases) { item in
                    filterButton(item)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Label("配置仅保存在本机", systemImage: "lock.fill")
                Text("可复制内置模板，再按自己的写作习惯调整。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(10)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }

    private func filterButton(_ item: AgentFilter) -> some View {
        Button {
            filter = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .frame(width: 18)
                Text(item.rawValue)
                Spacer()
                Text("\(count(for: item))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: filter == item ? .semibold : .regular))
            .foregroundStyle(filter == item ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(filter == item ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.rawValue)
                        .font(.system(size: 18, weight: .bold))
                    Text(contentSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索名称或提示词", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 170)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if filter == .all || filter == .builtin {
                        cardSection(title: "内置模板", subtitle: "选择一个起点，复制后自由修改", agents: visibleBuiltinAgents)
                    }
                    if filter == .all || filter == .custom {
                        if visibleCustomAgents.isEmpty {
                            if hasSearchText && (filter == .custom || visibleBuiltinAgents.isEmpty) {
                                emptySearchResults
                            } else if !hasSearchText {
                                emptyCustomAgents
                            }
                        } else {
                            cardSection(title: "我的 Agent", subtitle: "你创建的人格与能力配置", agents: visibleCustomAgents)
                        }
                    }
                }
                .padding(22)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.36))
        }
    }

    private func cardSection(title: String, subtitle: String, agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(agents.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                ForEach(agents) { agent in
                    agentCard(agent)
                }
            }
        }
    }

    private func agentCard(_ agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                AgentIconView(icon: agent.icon, avatarPath: agent.avatarPath)
                    .font(.system(size: 23))
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.20), Color.purple.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        if agent.isBuiltin { badge("内置", color: .secondary) }
                    }
                    Text(agent.model.flatMap { $0.isEmpty ? nil : $0 } ?? "跟随全局模型")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !agent.isBuiltin {
                    agentMenu(agent)
                }
            }

            Text(agent.systemPrompt.isEmpty ? "还没有填写人格提示词" : agent.systemPrompt)
                .font(.system(size: 11.5))
                .foregroundStyle(agent.systemPrompt.isEmpty ? .tertiary : .secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)

            HStack(spacing: 10) {
                capabilityLabel(icon: "wrench.and.screwdriver",
                                text: agent.tools == nil ? "工具跟随全局" : "\(agent.tools?.count ?? 0) 工具")
                capabilityLabel(icon: "wand.and.stars",
                                text: agent.fixedSkillID.flatMap { id in app.skills.first { $0.id == id }?.name }
                                    .map { "固定：\($0)" } ?? "无固定 Skill")
                Spacer(minLength: 0)
            }

            Divider()

            if agent.isBuiltin {
                Button { duplicateAndEdit(agent) } label: {
                    Label("复制并编辑", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button { edit(agent) } label: {
                    Label("编辑", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    private func agentMenu(_ agent: Agent) -> some View {
        Menu {
            Button { duplicateAndEdit(agent) } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) { app.deleteAgent(agent.id) } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func capabilityLabel(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
    }

    private var emptyCustomAgents: some View {
        VStack(spacing: 9) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("创建你的第一个 Agent")
                .font(.system(size: 13, weight: .semibold))
            Text("可以从空白开始，也可以根据描述自动生成人格与提示词。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("空白创建") { startCreate() }
                    .buttonStyle(.bordered)
                Button("快速创建") { startAIGeneration() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.quaternary)
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有匹配的 Agent")
                .font(.system(size: 12.5, weight: .semibold))
            Button("清除搜索") { searchText = "" }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contentSubtitle: String {
        switch filter {
        case .all: return "浏览模板与自己的配置"
        case .builtin: return "从模板开始创建，更快进入写作"
        case .custom: return "管理自己创建的 Agent"
        }
    }

    private func count(for item: AgentFilter) -> Int {
        switch item {
        case .all: return app.agents.count
        case .builtin: return builtinAgents.count
        case .custom: return customAgents.count
        }
    }

    private func searched(_ agents: [Agent]) -> [Agent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return agents }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.systemPrompt.localizedCaseInsensitiveContains(query)
                || ($0.model?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func startCreate() {
        app.createAgent()
        app.showAgentEditor = true
    }

    private func startAIGeneration() {
        app.editingAgent = nil
        app.showAgentEditor = true
    }

    private func edit(_ agent: Agent) {
        app.editingAgent = agent
        app.showAgentEditor = true
    }

    private func duplicateAndEdit(_ agent: Agent) {
        app.duplicateAgent(agent)
        if let copy = app.agents.last {
            app.editingAgent = copy
            app.showAgentEditor = true
        }
    }
}

// MARK: - Agent 工具权限树

private struct ToolPermissionGroupView: View {
    let node: ToolGroups.Node
    let labels: [String: String]
    @Binding var flags: [String: Bool]
    @Binding var expanded: Set<String>

    private var toolNames: Set<String> {
        ToolGroups.descendantToolNames(of: node.id)
    }

    private var enabledCount: Int {
        toolNames.filter { flags[$0] ?? true }.count
    }

    private var allEnabled: Bool {
        !toolNames.isEmpty && enabledCount == toolNames.count
    }

    private var groupSymbol: String {
        if allEnabled { return "checkmark.circle.fill" }
        if enabledCount > 0 { return "minus.circle.fill" }
        return "circle"
    }

    private var orderedLeafTools: [(id: String, label: String)] {
        toolNames
            .map { ($0, labels[$0] ?? $0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(node.id) },
            set: { value in
                if value { expanded.insert(node.id) } else { expanded.remove(node.id) }
            }
        )) {
            VStack(alignment: .leading, spacing: 7) {
                if node.isLeaf {
                    ForEach(orderedLeafTools, id: \.id) { tool in
                        Toggle(isOn: Binding(
                            get: { flags[tool.id] ?? true },
                            set: { flags[tool.id] = $0 }
                        )) {
                            Text(tool.label)
                                .font(.system(size: 12))
                        }
                        .toggleStyle(.checkbox)
                    }
                } else {
                    ForEach(ToolGroups.children(of: node.id), id: \.id) { child in
                        ToolPermissionGroupView(
                            node: child,
                            labels: labels,
                            flags: $flags,
                            expanded: $expanded
                        )
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.top, 7)
        } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(node.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(enabledCount)/\(toolNames.count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    let newValue = !allEnabled
                    for name in toolNames { flags[name] = newValue }
                } label: {
                    Image(systemName: groupSymbol)
                        .foregroundStyle(enabledCount > 0 ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(allEnabled ? "关闭这一组" : "允许这一组")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Agent 编辑器

struct AgentEditor: View {
    @EnvironmentObject var app: AppState

    // 基础信息
    @State private var name = ""
    @State private var icon = "🤖"
    @State private var avatarSourcePath: String?
    // 提示词
    @State private var systemPrompt = ""
    // 模型与参数
    @State private var useCustomModel = false
    @State private var modelText = ""
    @State private var useCustomTemp = false
    @State private var temperature = 0.8
    @State private var useCustomTopP = false
    @State private var topP = 1.0
    @State private var useCustomMaxTokens = false
    @State private var maxTokens = 4096
    // 工具权限（true = 允许）
    @State private var toolFlags: [String: Bool] = [:]
    @State private var expandedToolGroups: Set<String> = []
    // 技能绑定
    @State private var fixedSkillID: String?
    // 知识库挂载
    @State private var loreIDs: Set<UUID> = []
    // AI 生成
    @State private var genPrompt = ""
    @State private var genState = ""
    @State private var genBusy = false
    @State private var showMarkdownSkills = false

    private let TOOLS: [(id: String, label: String)] = [
        ("search_database", "搜索设定库（全文检索）"),
        ("read_chapter", "读取章节内容"),
        ("list_chapters", "列出章节"),
        ("get_outline", "读取故事大纲"),
        ("list_books", "列出全部书籍"),
        ("get_book", "读取书籍信息"),
        ("get_story_stats", "统计作品与各章篇幅"),
        ("create_book", "创建书籍"),
        ("update_book", "修改书籍信息与大纲"),
        ("delete_book", "删除书籍及关联内容"),
        ("create_chapter", "创建章节并写入正文"),
        ("update_chapter", "替换或追加章节内容"),
        ("replace_chapter_text", "局部修改章节正文"),
        ("delete_chapter", "删除章节"),
        ("batch_create_chapters", "批量创建章节"),
        ("move_chapter", "移动并重排章节"),
        ("duplicate_chapter", "复制章节"),
        ("split_chapter", "拆分章节"),
        ("merge_chapters", "合并相邻章节"),
        ("list_lore_entries", "列出设定库"),
        ("read_lore_entry", "读取完整设定"),
        ("create_lore_entry", "创建设定"),
        ("update_lore_entry", "修改设定"),
        ("delete_lore_entry", "删除设定"),
    ] + WorkspaceTools.catalog

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicSection
                    aiGenSection
                    promptSection
                    modelSection
                    toolSection
                    skillSection
                    loreSection
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 680)
        .onAppear { loadExisting() }
        .sheet(isPresented: $showMarkdownSkills) { SkillManagerSheet() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack {
            Text(app.editingAgent == nil ? "创建智能体" : "编辑智能体")
                .font(.system(size: 15, weight: .bold))
            Text("配置人格、模型、参数、工具、技能与知识库")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                app.showAgentEditor = false
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 基础信息

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("基础信息", "头像与名称")
            HStack(spacing: 12) {
                Menu {
                    ForEach(AGENT_ICON_CHOICES, id: \.self) { ic in
                        Button {
                            icon = ic
                            avatarSourcePath = nil
                        } label: {
                            Label(ic, systemImage: "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                } label: {
                    AgentIconView(icon: icon, avatarPath: avatarSourcePath)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .background(.quaternary.opacity(0.5), in: Circle())
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .help("选择 emoji 或符号头像")
                Button("选择本地图片…") { chooseAvatarImage() }
                    .buttonStyle(.bordered)
                if avatarSourcePath != nil {
                    Button("使用图标") { avatarSourcePath = nil }
                        .buttonStyle(.borderless)
                }
                TextField("名称（如：毒舌编辑、古风文豪）", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: AI 自动生成

    private var aiGenSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("描述你想要的写作助手，将自动生成名称、头像与提示词（使用全局模型）")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("如：一个擅长武侠打斗场景、文风凌厉的速写手", text: $genPrompt)
                        .textFieldStyle(.roundedBorder)
                    Button("✨ 生成") { Task { await generate() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(genBusy || genPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !genState.isEmpty {
                    Text(genState)
                        .font(.caption)
                        .foregroundStyle(genState.hasPrefix("✓") ? .green : .orange)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("根据描述创建", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: 系统提示词

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("提示词", "行为准则 · 最核心的配置")
            TextEditor(text: $systemPrompt)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                .frame(height: 130)
            Text("建议包含：角色定位、回答风格、工作流程与步骤、使用工具的时机、需要遵守的规范")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: 模型与参数

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("模型与参数", "未开启的项跟随全局设置")
            HStack(spacing: 8) {
                Toggle("自定义模型", isOn: $useCustomModel)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                if useCustomModel {
                    TextField("模型名", text: $modelText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Menu {
                        ForEach(PROVIDERS[app.config.provider]?.models ?? [], id: \.self) { m in
                            Button(m) { modelText = m }
                        }
                    } label: {
                        Text("预设")
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    Text("当前全局：\(app.config.model)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            paramRow(title: "温度", unit: String(format: "%.2f", temperature),
                     on: $useCustomTemp, value: $temperature, range: 0...1.5, step: 0.05,
                     followText: String(format: "全局 %.2f", app.config.temperature))
            paramRow(title: "Top-P", unit: String(format: "%.2f", topP),
                     on: $useCustomTopP, value: $topP, range: 0...1, step: 0.05,
                     followText: String(format: "全局 %.2f", app.config.topP))
            HStack(spacing: 8) {
                Toggle("输出上限", isOn: $useCustomMaxTokens)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .frame(width: 90, alignment: .leading)
                if useCustomMaxTokens {
                    TokenLimitEditor(
                        value: $maxTokens,
                        presets: [4096, 8192, 16384, 32768, 65536, 131072, 262144],
                        minimum: 256
                    )
                } else {
                    Text("全局 \(app.config.maxTokens) tokens")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func paramRow(title: String, unit: String, on: Binding<Bool>, value: Binding<Double>,
                          range: ClosedRange<Double>, step: Double, followText: String) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: on)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(width: 70, alignment: .leading)
            if on.wrappedValue {
                Slider(value: value, in: range, step: step)
                    .frame(width: 200)
                Text(unit).font(.system(size: 12)).monospacedDigit()
            } else {
                Text("跟随全局（\(followText)）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: 工具权限

    private var toolSection: some View {
        let enabledCount = TOOLS.filter { toolFlags[$0.id] ?? true }.count
        let labels = Dictionary(uniqueKeysWithValues: TOOLS.map { ($0.id, $0.label) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("工具权限", "按领域逐级展开，允许该 Agent 调用相应工具")
                Spacer()
                Text("已允许 \(enabledCount)/\(TOOLS.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Menu {
                    Button("全部允许") {
                        for tool in TOOLS { toolFlags[tool.id] = true }
                    }
                    Button("全部关闭") {
                        for tool in TOOLS { toolFlags[tool.id] = false }
                    }
                    Divider()
                    Button("展开全部") {
                        expandedToolGroups = Set(ToolGroups.nodes.map(\.id))
                    }
                    Button("全部收起") {
                        expandedToolGroups.removeAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            ForEach(ToolGroups.roots, id: \.id) { root in
                ToolPermissionGroupView(
                    node: root,
                    labels: labels,
                    flags: $toolFlags,
                    expanded: $expandedToolGroups
                )
            }
        }
    }

    // MARK: 技能绑定

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("固定 Skill", "随 Agent 每轮生效；一次只能固定一个")
                Spacer()
                Button("管理技能库…") { showMarkdownSkills = true }
                    .buttonStyle(.borderless)
            }
            Menu {
                Button {
                    fixedSkillID = nil
                } label: {
                    if fixedSkillID == nil { Label("不固定", systemImage: "checkmark") }
                    else { Text("不固定") }
                }
                Divider()
                ForEach(SkillCategory.allCases) { cat in
                    let items = app.skills.filter { $0.id != "chat" && $0.category == cat }
                    if !items.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(items) { skill in
                                Button {
                                    fixedSkillID = skill.id
                                } label: {
                                    if fixedSkillID == skill.id { Label(skill.name, systemImage: "checkmark") }
                                    else { Text(skill.name) }
                                }
                            }
                        }
                    }
                }
            } label: {
                let selected = fixedSkillID.flatMap { id in app.skills.first { $0.id == id } }
                Label(selected?.name ?? "不固定", systemImage: selected?.icon ?? "minus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            Text("固定 Skill 的完整正文会直接加入 Agent；适合创建长期专用 Agent。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("技能库中的其余 \(app.skills.filter { $0.id != "chat" && $0.id != fixedSkillID }.count) 个 Skill 会自动组成轻量索引，Agent 需要时自行调用 get_skill；技能库增删改会在下一轮自动更新。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 知识库挂载

    private var loreSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("知识库（设定库挂载）", "绑定条目始终注入该 Agent 的上下文，不受关键词触发限制")
            if app.entries.isEmpty {
                Text("当前作品还没有设定条目，先去「设定库」创建")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(app.entries) { e in
                    Toggle(isOn: Binding(
                        get: { loreIDs.contains(e.id) },
                        set: { on in
                            if on { loreIDs.insert(e.id) } else { loreIDs.remove(e.id) }
                        }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: entryTypeIcon(e.type)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(e.title).font(.system(size: 12))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Text("提示：知识库按作品挂载，切换到其他作品后未匹配的条目自动忽略")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack {
            if app.editingAgent != nil && app.editingAgent?.isBuiltin == false {
                Button("删除", role: .destructive) {
                    if let a = app.editingAgent { app.deleteAgent(a.id) }
                }
            } else if app.editingAgent != nil {
                Text("内置 Agent 不可直接修改，可复制为自定义后编辑")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("取消") { app.showAgentEditor = false }
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
    }

    // MARK: 逻辑

    private func sectionTitle(_ t: String, _ s: String) -> some View {
        HStack(spacing: 6) {
            Text(t).font(.system(size: 12.5, weight: .semibold))
            Text(s).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func loadExisting() {
        if let a = app.editingAgent {
            name = a.name
            icon = a.icon
            avatarSourcePath = a.avatarPath
            systemPrompt = a.systemPrompt
            useCustomModel = a.model != nil
            modelText = a.model ?? ""
            useCustomTemp = a.temperature != nil
            temperature = a.temperature ?? 0.8
            useCustomTopP = a.topP != nil
            topP = a.topP ?? 1.0
            useCustomMaxTokens = a.maxTokens != nil
            maxTokens = a.maxTokens ?? 4096
            for t in TOOLS { toolFlags[t.id] = a.tools?.contains(t.id) ?? true }
            fixedSkillID = a.fixedSkillID
            loreIDs = Set(a.loreEntryIDs ?? [])
        } else {
            icon = AGENT_ICON_CHOICES[0]
            for t in TOOLS { toolFlags[t.id] = true }
            fixedSkillID = nil
        }
    }

    private func save() {
        let base = app.editingAgent
            ?? Agent(id: UUID(), name: "", icon: "🤖", systemPrompt: "", model: nil,
                     temperature: nil, topP: nil, maxTokens: nil, tools: nil, skills: nil,
                     loreEntryIDs: nil, isBuiltin: false)
        var tools: [String]? = TOOLS.compactMap { (toolFlags[$0.id] ?? true) ? $0.id : nil }
        if tools?.count == TOOLS.count { tools = nil }        // 全开 = 跟随全局
        let savedAvatarPath = persistAvatarImage(for: base.id)
        let updated = Agent(id: base.id, name: name, icon: icon, avatarPath: savedAvatarPath,
                            systemPrompt: systemPrompt,
                            model: useCustomModel && !modelText.isEmpty ? modelText : nil,
                            temperature: useCustomTemp ? temperature : nil,
                            topP: useCustomTopP ? topP : nil,
                            maxTokens: useCustomMaxTokens ? maxTokens : nil,
                            tools: tools,
                            skills: nil,
                            fixedSkillID: fixedSkillID.flatMap { id in app.skills.contains { $0.id == id } ? id : nil },
                            loreEntryIDs: loreIDs.isEmpty ? nil : Array(loreIDs),
                            isBuiltin: base.isBuiltin)
        app.saveAgent(updated)
    }

    private func chooseAvatarImage() {
        let panel = NSOpenPanel()
        panel.title = "选择 Agent 头像"
        panel.prompt = "选择头像"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        avatarSourcePath = url.path
    }

    private func persistAvatarImage(for agentID: UUID) -> String? {
        let avatarDir = AppPaths.dataDir.appendingPathComponent("AgentAvatars", isDirectory: true)
        guard let sourcePath = avatarSourcePath, FileManager.default.fileExists(atPath: sourcePath) else {
            if let oldPath = app.editingAgent?.avatarPath {
                let oldURL = URL(fileURLWithPath: oldPath)
                if oldURL.deletingLastPathComponent().standardizedFileURL == avatarDir.standardizedFileURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }
            return nil
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        if sourceURL.deletingLastPathComponent().standardizedFileURL == avatarDir.standardizedFileURL {
            return sourceURL.path
        }

        do {
            try FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
            let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
            let destinationURL = avatarDir.appendingPathComponent("\(agentID.uuidString).\(fileExtension)")
            if let existing = try? FileManager.default.contentsOfDirectory(at: avatarDir,
                                                                            includingPropertiesForKeys: nil) {
                for url in existing where url.deletingPathExtension().lastPathComponent == agentID.uuidString {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL.path
        } catch {
            app.toast("头像保存失败：\(error.localizedDescription)")
            return app.editingAgent?.avatarPath
        }
    }

    /// AI 自动生成：调用全局模型产出 名称/头像/提示词
    private func generate() async {
        genBusy = true
        genState = "生成中…"
        defer { genBusy = false }
        let system = "你是一位「智能体配置生成器」。根据用户描述的写作助手需求，只输出严格 JSON（不要任何其他文字）："
            + "{\"name\":\"中文名称(6字内)\",\"icon\":\"单个emoji\",\"systemPrompt\":\"100-300字中文，定义角色定位、回答风格、工作流程与步骤、使用工具的时机、遵守的规范\"}"
        do {
            let raw = try await LLM.complete(config: app.config, system: system, user: genPrompt)
            guard let start = raw.firstIndex(of: "{"),
                  let end = raw.lastIndex(of: "}"),
                  let data = raw[start...end].data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                genState = "✗ 解析失败：" + String(raw.prefix(120))
                return
            }
            name = j["name"] as? String ?? name
            if let ic = j["icon"] as? String {
                icon = AGENT_ICON_CHOICES.contains(ic) ? ic : "🤖"
            }
            systemPrompt = j["systemPrompt"] as? String ?? systemPrompt
            genState = "✓ 已生成，请检查并保存"
        } catch {
            genState = "✗ " + error.localizedDescription
        }
    }
}

// MARK: - Markdown Skills

struct SkillManagerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var filter: SkillFilter = .mine
    @State private var searchText = ""
    @State private var isDropTargeted = false

    private enum SkillFilter: String, CaseIterable, Identifiable {
        case mine = "我的 Skills"
        case builtin = "内置模板"
        case all = "全部 Skills"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .mine: return "doc.text"
            case .builtin: return "square.stack.3d.up"
            case .all: return "square.grid.2x2"
            }
        }
    }

    private var builtinSkills: [Skill] { app.skills.filter { !$0.isMarkdown } }
    private var markdownSkills: [Skill] { app.skills.filter(\.isMarkdown) }
    private var visibleBuiltinSkills: [Skill] { searched(builtinSkills) }
    private var visibleMarkdownSkills: [Skill] { searched(markdownSkills) }
    private let gridColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 360), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .frame(width: 940, height: 640)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { app.reloadSkills() }
        .sheet(isPresented: $app.showSkillEditor) { MarkdownSkillEditor() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.blue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Skills 工作室")
                    .font(.system(size: 16, weight: .bold))
                Text("管理可复用的 Markdown 写作指令")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: createSkill) {
                Label("新建 Skill", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: chooseSkillFiles) {
                Label("选择 .md 文件导入", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            VStack(spacing: 8) {
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                Text(isDropTargeted ? "松开即可导入" : "拖入 Markdown 文件")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("支持一次拖入多个 .md")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            Divider()

            Text("浏览")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(SkillFilter.allCases) { item in
                    filterButton(item)
                }
            }

            Spacer()

            Button { NSWorkspace.shared.open(SkillStore.directory) } label: {
                Label("打开 Skills 文件夹", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text("导入时会校验格式；同名文件不会覆盖已有 Skill。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }

    private func filterButton(_ item: SkillFilter) -> some View {
        Button { filter = item } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).frame(width: 18)
                Text(item.rawValue)
                Spacer()
                Text("\(count(for: item))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: filter == item ? .semibold : .regular))
            .foregroundStyle(filter == item ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(filter == item ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.rawValue)
                        .font(.system(size: 18, weight: .bold))
                    Text(contentSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索技能", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 170)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if filter == .mine || filter == .all {
                        if visibleMarkdownSkills.isEmpty {
                            if hasSearchText && (filter == .mine || visibleBuiltinSkills.isEmpty) {
                                emptySearchResults
                            } else if !hasSearchText {
                                emptyMarkdownSkills
                            }
                        } else {
                            skillGroup(title: "我的 Skills", subtitle: "可编辑、可删除，也可直接修改源文件", skills: visibleMarkdownSkills)
                        }
                    }
                    if filter == .builtin || filter == .all {
                        skillGroup(title: "内置模板", subtitle: "只读模板，可另存为 Markdown 后修改", skills: visibleBuiltinSkills)
                    }
                }
                .padding(22)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.36))
        }
    }

    private func skillGroup(title: String, subtitle: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(skills.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                ForEach(skills) { skill in
                    skillCard(skill)
                }
            }
        }
    }

    private func skillCard(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: skill.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(skill.isMarkdown ? Color.accentColor : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background(
                        (skill.isMarkdown ? Color.accentColor : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        if skill.isMarkdown {
                            Text("MD")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(skill.category.rawValue)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if skill.isMarkdown { skillMenu(skill) }
            }

            Text(skill.desc)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Divider()

            if skill.isMarkdown {
                Button {
                    app.editingSkill = skill
                    app.showSkillEditor = true
                } label: {
                    Label("编辑 Skill", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    app.editingSkill = skill
                    app.showSkillEditor = true
                } label: {
                    Label("另存为 Markdown", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }

    private func skillMenu(_ skill: Skill) -> some View {
        Menu {
            if let url = skill.fileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }
            Divider()
            Button(role: .destructive) { app.deleteSkill(skill) } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var emptyMarkdownSkills: some View {
        VStack(spacing: 9) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("还没有自己的 Skill")
                .font(.system(size: 13, weight: .semibold))
            Text("把 .md 文件拖进窗口，或从空白开始创建。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("选择文件") { chooseSkillFiles() }.buttonStyle(.bordered)
                Button("新建 Skill") { createSkill() }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.quaternary)
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有匹配的 Skill").font(.system(size: 12.5, weight: .semibold))
            Button("清除搜索") { searchText = "" }.buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contentSubtitle: String {
        switch filter {
        case .mine: return "编辑和管理自己的 Markdown Skills"
        case .builtin: return "从内置模板快速创建自己的版本"
        case .all: return "浏览全部可用技能"
        }
    }

    private func count(for item: SkillFilter) -> Int {
        switch item {
        case .mine: return markdownSkills.count
        case .builtin: return builtinSkills.count
        case .all: return app.skills.count
        }
    }

    private func searched(_ skills: [Skill]) -> [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.desc.localizedCaseInsensitiveContains(query)
                || $0.system.localizedCaseInsensitiveContains(query)
        }
    }

    private func createSkill() {
        app.editingSkill = nil
        app.showSkillEditor = true
    }

    private func chooseSkillFiles() {
        let panel = NSOpenPanel()
        panel.title = "导入 Markdown Skills"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        if app.importSkills(from: panel.urls) > 0 { filter = .mine }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in supported {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? NSURL {
                    url = value as URL
                } else {
                    url = nil
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if app.importSkills(from: urls) > 0 { filter = .mine }
        }
        return true
    }
}

struct MarkdownSkillEditor: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var desc = ""
    @State private var category: SkillCategory = .write
    @State private var icon = "doc.text"
    @State private var needsText = false
    @State private var chapters = 0
    @State private var markdown = ""
    @State private var errorText = ""

    private var source: Skill? { app.editingSkill }
    private var editableSource: Skill? { source?.isMarkdown == true ? source : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editableSource == nil ? "新建 Markdown Skill" : "编辑 Markdown Skill")
                        .font(.system(size: 16, weight: .bold))
                    Text(editableSource?.fileURL?.lastPathComponent ?? "保存后生成独立 .md 文件")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { app.showSkillEditor = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("元数据").font(.system(size: 12.5, weight: .semibold))
                        HStack(spacing: 10) {
                            TextField("技能名称", text: $name)
                            TextField("SF Symbol，例如 bolt.fill", text: $icon)
                                .frame(width: 210)
                        }
                        TextField("一句话说明这个技能做什么", text: $desc)
                        HStack(spacing: 16) {
                            Picker("分类", selection: $category) {
                                ForEach(SkillCategory.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .frame(width: 160)
                            Toggle("需要当前章节正文", isOn: $needsText)
                                .toggleStyle(.checkbox)
                            Stepper("注入前文 \(chapters) 章", value: $chapters, in: 0...10)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("技能指令（Markdown）")
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Text("正文会追加到 Agent 系统提示词")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                        TextEditor(text: $markdown)
                            .font(.system(size: 12.5, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 310)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            }
                    }

                    if !errorText.isEmpty {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(18)
            }

            Divider()
            HStack {
                if let skill = editableSource {
                    Button("删除", role: .destructive) { app.deleteSkill(skill) }
                }
                Spacer()
                Button("取消") { app.showSkillEditor = false }
                Button("保存 .md") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 650, height: 670)
        .onAppear { load() }
    }

    private func load() {
        if let skill = source {
            name = skill.isMarkdown ? skill.name : skill.name + " 自定义"
            desc = skill.desc
            category = skill.category
            icon = skill.icon
            needsText = skill.needsText
            chapters = skill.chapters
            markdown = skill.system
        } else {
            name = ""
            desc = ""
            category = .write
            icon = "doc.text"
            needsText = false
            chapters = 0
            markdown = "# 目标\n\n描述这个技能要完成的任务。\n\n## 工作步骤\n\n1. 分析用户需求\n2. 执行任务\n3. 检查输出质量\n\n## 输出要求\n\n- 使用清晰的 Markdown 结构"
        }
    }

    private func save() {
        do {
            try app.saveSkill(existing: editableSource, name: name, desc: desc, category: category,
                              icon: icon, needsText: needsText, chapters: chapters, markdown: markdown)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @EnvironmentObject var app: AppState
    @State private var showKey = false
    @AppStorage("chat.followsStreamingOutput") private var followsStreamingOutput = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    app.showSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            Form {
                Section("模型连接") {
                    Picker("模型商", selection: $app.config.provider) {
                        ForEach(PROVIDER_SECTIONS) { providerSection in
                            Section(providerSection.title) {
                                ForEach(providerSection.providerIDs, id: \.self) { providerID in
                                    Text(PROVIDERS[providerID]?.label ?? providerID).tag(providerID)
                                }
                            }
                        }
                    }
                    .onChange(of: app.config.provider) { p in applyProviderPreset(p) }

                    TextField("Base URL", text: $app.config.baseURL)

                    HStack(spacing: 6) {
                        if showKey {
                            TextField("API Key（仅保存在本机）", text: $app.config.apiKey)
                        } else {
                            SecureField("API Key（仅保存在本机）", text: $app.config.apiKey)
                        }
                        Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
                            .buttonStyle(.borderless)
                        if app.config.provider == "ollama" {
                            Button("列出本地模型") {
                                Task { await app.loadOllamaModels() }
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("模型", text: $app.config.model)
                        Menu {
                            ForEach(presetModels, id: \.self) { m in
                                Button(m) { app.config.model = m }
                            }
                            if presetModels.isEmpty {
                                Text("无预设，手动输入")
                            }
                        } label: {
                            Text("常用")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    HStack(spacing: 10) {
                        Text("温度").frame(width: 36, alignment: .leading)
                        Slider(value: $app.config.temperature, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", app.config.temperature))
                            .monospacedDigit().frame(width: 36, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Text("输出上限").frame(width: 60, alignment: .leading)
                        TokenLimitEditor(
                            value: $app.config.maxTokens,
                            presets: [4096, 8192, 16384, 32768, 65536, 131072, 262144],
                            minimum: 256
                        )
                        Text("每次生成的最大长度")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("输入窗口").frame(width: 60, alignment: .leading)
                        TokenLimitEditor(
                            value: $app.config.contextWindow,
                            presets: [32768, 65536, 131072, 200000, 262144, 524288, 1000000, 2000000, 4000000],
                            minimum: 1024
                        )
                        Text("模型上下文上限，用于预算告警")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $app.config.enableTools) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写作工具（Tool Use）")
                            Text("让模型可调用：搜索设定库 / 读取章节 / 列出章节 / 读取大纲（只读，结果回填继续生成）")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Section("上下文压缩") {
                    Toggle("上下文达到输入窗口 80% 时自动压缩", isOn: $app.config.enableContextCompression)
                        .toggleStyle(.checkbox)

                    if app.config.enableContextCompression {
                        Picker("压缩强度", selection: $app.config.contextCompressionLevel) {
                            ForEach(ContextCompressionLevel.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        if app.config.contextCompressionLevel == .custom {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("目标压缩率")
                                    Slider(value: customCompressionPercent,
                                           in: 0.05...0.90, step: 0.05)
                                    Text("\(Int(customCompressionPercent.wrappedValue * 100))%")
                                        .monospacedDigit()
                                        .frame(width: 42, alignment: .trailing)
                                }
                                ProgressView(value: customCompressionPercent.wrappedValue)
                                    .progressViewStyle(.linear)
                                    .tint(app.config.tintColor)
                            }
                            Text("达到输入窗口 80% 后，目标压缩率表示希望删除的 token 比例；实际比例会受硬规则、最近对话等强制保留内容影响。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("保护作者意图、本书硬规则、当前聚焦、最新章节结尾、已触发设定和最近对话；工具定义也计入窗口，工具结果会在下一轮前重新压缩。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("关闭后沿用旧版固定截断规则。超长请求可能被模型服务拒绝。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("对话") {
                    Toggle(isOn: $followsStreamingOutput) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("输出跟随")
                            Text("模型生成内容时，自动滚动到最新输出；关闭后保持当前阅读位置。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Section("多任务调度") {
                    Toggle(isOn: $app.config.automaticBackgroundScheduling) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动规划核心与内存")
                            Text("根据本机资源、上下文窗口和模型类型动态计算安全并行数。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Stepper(value: $app.config.conversationCorePercent,
                            in: 10...400, step: 10) {
                        HStack {
                            Text("每会话核心份额")
                            Spacer()
                            Text(String(format: "%.1f 核", Double(app.config.automaticBackgroundScheduling ? app.config.plannedConversationCorePercent : app.config.conversationCorePercent) / 100))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .disabled(app.config.automaticBackgroundScheduling)
                    Stepper(value: $app.config.conversationMemoryMB,
                            in: 128...ModelConfig.availableMemoryMB, step: 128) {
                        HStack {
                            Text("每会话内存预留")
                            Spacer()
                            Text("\(app.config.automaticBackgroundScheduling ? app.config.plannedConversationMemoryMB : app.config.conversationMemoryMB) MB")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .disabled(app.config.automaticBackgroundScheduling)
                    HStack {
                        Label("最多同时运行 \(app.config.backgroundConcurrencyLimit) 个 Agent 任务",
                              systemImage: "square.stack.3d.up.fill")
                        Spacer()
                        Text("当前 \(app.backgroundConversationTasks.count)")
                            .foregroundStyle(.secondary)
                    }
                    Text(perConversationResourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("外观") {
                    HStack(spacing: 10) {
                        Text("背景").frame(width: 72, alignment: .leading)
                        Button {
                            app.resetBackgroundMedia()
                        } label: {
                            Label("内置背景",
                                  systemImage: app.config.backgroundMediaPath.isEmpty
                                  ? "checkmark.circle.fill" : "photo")
                        }
                        .buttonStyle(.bordered)
                        .tint(app.config.backgroundMediaPath.isEmpty ? Color.accentColor : Color.secondary)

                        Button {
                            app.chooseBackgroundMedia()
                        } label: {
                            Label(app.config.backgroundMediaPath.isEmpty
                                  ? "选择本地图片或视频…"
                                  : URL(fileURLWithPath: app.config.backgroundMediaPath).lastPathComponent,
                                  systemImage: app.config.backgroundMediaPath.isEmpty
                                  ? "folder" : "checkmark.circle.fill")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.bordered)
                        .tint(app.config.backgroundMediaPath.isEmpty ? Color.secondary : Color.accentColor)
                        .help("选择本地图片或视频作为背景")
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Text("背景透明度").frame(width: 72, alignment: .leading)
                        Slider(value: $app.config.backgroundOpacity, in: 0.10...0.90, step: 0.05)
                        Text("\(Int(app.config.backgroundOpacity * 100))%")
                            .monospacedDigit().frame(width: 38, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Text("主题色").frame(width: 72, alignment: .leading)
                        HueSlider(value: $app.config.themeHue)
                        Circle()
                            .fill(app.config.tintColor)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.white.opacity(0.65)))
                    }

                    HStack(spacing: 10) {
                        Text("主题明亮度").frame(width: 72, alignment: .leading)
                        BrightnessSlider(hue: app.config.themeHue, value: $app.config.themeBrightness)
                        Text("\(Int(app.config.themeBrightness * 100))%")
                            .monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                }

                Section("数据") {
                    HStack {
                        Text("所有数据保存在本机：\(AppPaths.dataDir.path)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("打开文件夹") { NSWorkspace.shared.open(AppPaths.dataDir) }
                    }
                    HStack {
                        Text("模型文件导入仅限 Imports 授权区")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("授权导入文件…") { app.authorizeImportFile() }
                        Button("打开授权区") { NSWorkspace.shared.open(GovernanceTools.importsDirectory) }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(app.testResult ?? "")
                    .font(.caption)
                    .foregroundStyle(app.testResult?.hasPrefix("✓") == true
                                     ? Color.green
                                     : (app.testResult?.hasPrefix("✗") == true ? Color.red : Color.secondary))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(app.testResult ?? "")
                Spacer()
                Button("测试连接") {
                    Task { await app.testConnection() }
                }
                Button("保存") {
                    app.saveConfig()
                    app.showSettings = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 620, height: 570)
    }

    private var presetModels: [String] {
        PROVIDERS[app.config.provider]?.models ?? []
    }

    private var perConversationResourceDescription: String {
        let cores = String(format: "%.2f", Double(app.config.plannedConversationCorePercent) / 100)
        return "每个会话独立预留 \(cores) 核与 \(app.config.plannedConversationMemoryMB) MB：上下文 \(app.config.estimatedConversationContextMemoryMB) MB + 工具工作区 \(app.config.estimatedConversationToolMemoryMB) MB + 输出缓冲 \(app.config.estimatedConversationOutputMemoryMB) MB + 基础开销 48 MB。运行会话的预留会累加，资源不足时自动排队。"
    }

    private var customCompressionPercent: Binding<Double> {
        Binding(
            get: { 1.0 - app.config.contextCompressionCustomRatio },
            set: { app.config.contextCompressionCustomRatio = 1.0 - $0 }
        )
    }

    private func applyProviderPreset(_ p: String) {
        guard let preset = PROVIDERS[p] else { return }
        app.config.baseURL = preset.baseURL
        if let m = preset.models.first { app.config.model = m }
    }
}

// MARK: - 外观滑条

/// Token 数既可手动输入，也可从常用档位中快速选择；不设置固定最大值。
private struct TokenLimitEditor: View {
    @Binding var value: Int
    let presets: [Int]
    let minimum: Int

    var body: some View {
        HStack(spacing: 6) {
            TextField("自定义", value: $value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 112)
                .onChange(of: value) { newValue in
                    if newValue < minimum { value = minimum }
                }
            Menu {
                ForEach(presets, id: \.self) { preset in
                    Button(Self.label(for: preset)) { value = preset }
                }
            } label: {
                Text("常用")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Text("tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func label(for value: Int) -> String {
        if value >= 1_000_000, value % 1_000_000 == 0 {
            return "\(value / 1_000_000)M"
        }
        if value >= 1_000, value % 1_000 == 0 {
            return "\(value / 1_000)K"
        }
        if value >= 1024, value % 1024 == 0 {
            return "\(value / 1024)K"
        }
        return value.formatted()
    }
}

private struct HueSlider: View {
    @Binding var value: Double

    var body: some View {
        GradientSlider(value: $value, gradient: LinearGradient(
            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
            startPoint: .leading, endPoint: .trailing
        ), thumbColor: Color(hue: value, saturation: 0.78, brightness: 0.90))
    }
}

private struct BrightnessSlider: View {
    let hue: Double
    @Binding var value: Double

    var body: some View {
        GradientSlider(value: $value, gradient: LinearGradient(
            colors: [.black, Color(hue: hue, saturation: 0.78, brightness: 1)],
            startPoint: .leading, endPoint: .trailing
        ), thumbColor: Color(hue: hue, saturation: 0.78, brightness: value))
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    let gradient: LinearGradient
    let thumbColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = max(20, geometry.size.width)
            ZStack(alignment: .leading) {
                gradient
                    .frame(height: 10)
                    .clipShape(Capsule())
                Circle()
                    .fill(thumbColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: (width - 18) * min(max(value, 0), 1))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                value = min(max(gesture.location.x / width, 0), 1)
            })
        }
        .frame(height: 22)
    }
}
