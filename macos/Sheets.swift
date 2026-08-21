import SwiftUI
import AppKit

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
                Label("固定引用（始终注入 AI 上下文）", systemImage: "pin")
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

    private var builtinAgents: [Agent] { app.agents.filter(\.isBuiltin) }
    private var customAgents: [Agent] { app.agents.filter { !$0.isBuiltin } }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overview
                    agentSection(
                        title: "内置 Agent",
                        subtitle: "复制后即可按自己的写作习惯调整",
                        agents: builtinAgents
                    )

                    if customAgents.isEmpty {
                        emptyCustomAgents
                    } else {
                        agentSection(
                            title: "我的 Agent",
                            subtitle: "你创建的人格、模型和能力配置",
                            agents: customAgents
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))

            Divider()
            footer
        }
        .frame(width: 760, height: 600)
        .sheet(isPresented: $app.showAgentEditor) { AgentEditor() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.crop.square.stack.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
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
                    .font(.system(size: 17, weight: .bold))
                Text("为不同写作任务配置专属人格与能力")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                startAIGeneration()
            } label: {
                Label("AI 创建", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)

            Button {
                app.showSkillManager = true
            } label: {
                Label("技能库", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .help("管理 Agent 可使用的 Markdown Skills")

            Button {
                startCreate()
            } label: {
                Label("新建 Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

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
        .padding(.vertical, 16)
    }

    private var overview: some View {
        HStack(spacing: 12) {
            overviewItem(
                value: "\(app.agents.count)",
                label: "全部 Agent",
                icon: "person.2.fill",
                color: .blue
            )
            overviewItem(
                value: "\(builtinAgents.count)",
                label: "内置模板",
                icon: "square.stack.3d.up.fill",
                color: .purple
            )
            overviewItem(
                value: "\(customAgents.count)",
                label: "我的配置",
                icon: "slider.horizontal.3",
                color: .orange
            )
        }
    }

    private func overviewItem(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func agentSection(title: String, subtitle: String, agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(agents.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(agents) { agent in
                    agentCard(agent)
                }
            }
        }
    }

    private func agentCard(_ agent: Agent) -> some View {
        HStack(spacing: 14) {
            AgentIconView(icon: agent.icon)
                .font(.system(size: 24))
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.22), Color.purple.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(agent.name)
                        .font(.system(size: 13.5, weight: .semibold))
                    if agent.isBuiltin {
                        badge("内置", color: .secondary)
                    }
                    if let model = agent.model, !model.isEmpty {
                        badge(model, color: .blue)
                    }
                }

                Text(agent.systemPrompt.isEmpty ? "还没有填写人格提示词" : agent.systemPrompt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(agent.systemPrompt.isEmpty ? .tertiary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    capabilityLabel(
                        icon: "wrench.and.screwdriver",
                        text: agent.tools == nil ? "工具跟随全局" : "\(agent.tools?.count ?? 0) 个工具"
                    )
                    capabilityLabel(
                        icon: "wand.and.stars",
                        text: agent.skills == nil ? "全部技能" : "\(agent.skills?.count ?? 0) 个技能"
                    )
                    if let lore = agent.loreEntryIDs, !lore.isEmpty {
                        capabilityLabel(icon: "books.vertical", text: "\(lore.count) 条知识")
                    }
                }
            }

            Spacer(minLength: 10)

            if agent.isBuiltin {
                Button {
                    duplicateAndEdit(agent)
                } label: {
                    Label("复制并编辑", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    edit(agent)
                } label: {
                    Label("编辑", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Menu {
                    Button {
                        duplicateAndEdit(agent)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.deleteAgent(agent.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多操作")
            }
        }
        .padding(13)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
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
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("创建你的第一个 Agent")
                .font(.system(size: 13, weight: .semibold))
            Text("可以从空白开始，也可以让 AI 帮你生成人格与提示词。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("空白创建") { startCreate() }
                    .buttonStyle(.bordered)
                Button("AI 帮我创建") { startAIGeneration() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.quaternary)
        }
    }

    private var footer: some View {
        HStack {
            Label("所有 Agent 配置仅保存在本机", systemImage: "lock.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("完成") { app.showAgentSheet = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

// MARK: - Agent 编辑器

struct AgentEditor: View {
    @EnvironmentObject var app: AppState

    // 基础信息
    @State private var name = ""
    @State private var icon = "🤖"
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
    // 技能绑定
    @State private var skillFlags: [String: Bool] = [:]
    @State private var allSkillsOn = true
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
    ]

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
                        } label: {
                            Label(ic, systemImage: "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                } label: {
                    AgentIconView(icon: icon)
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .help("选择头像（emoji / 符号）")
                TextField("名称（如：毒舌编辑、古风文豪）", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: AI 自动生成

    private var aiGenSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("描述你想要的写作助手，AI 将自动生成名称、头像与提示词（使用全局模型）")
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
            Label("AI 辅助创建", systemImage: "sparkles")
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
                    Stepper(value: $maxTokens, in: 256...32000, step: 256) {
                        Text("\(maxTokens) tokens").monospacedDigit()
                    }
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
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("工具权限", "允许该 Agent 调用的写作工具（只读）")
            ForEach(TOOLS, id: \.id) { t in
                Toggle(isOn: Binding(
                    get: { toolFlags[t.id] ?? true },
                    set: { toolFlags[t.id] = $0 }
                )) {
                    Text(t.label).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: 技能绑定

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("Markdown Skills", "绑定后将技能正文注入 Agent 上下文")
                Spacer()
                Button("管理…") { showMarkdownSkills = true }
                    .buttonStyle(.borderless)
                Toggle("全部技能", isOn: $allSkillsOn)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .disabled(false)
            }
            ForEach(SkillCategory.allCases) { cat in
                let items = app.skills.filter { $0.category == cat }
                VStack(alignment: .leading, spacing: 4) {
                    Text(cat.rawValue).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(items) { s in
                        Toggle(isOn: Binding(
                            get: { allSkillsOn || (skillFlags[s.id] ?? true) },
                            set: { v in
                                skillFlags[s.id] = v
                                if !v { allSkillsOn = false }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Label(s.name, systemImage: s.icon).font(.system(size: 12))
                                if s.isMarkdown {
                                    Text("MD")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(allSkillsOn)
                    }
                }
            }
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
            if let skills = a.skills {
                allSkillsOn = false
                for s in app.skills { skillFlags[s.id] = skills.contains(s.id) }
            } else {
                allSkillsOn = true
            }
            loreIDs = Set(a.loreEntryIDs ?? [])
        } else {
            icon = AGENT_ICON_CHOICES[0]
            for t in TOOLS { toolFlags[t.id] = true }
            allSkillsOn = true
        }
    }

    private func save() {
        let base = app.editingAgent
            ?? Agent(id: UUID(), name: "", icon: "🤖", systemPrompt: "", model: nil,
                     temperature: nil, topP: nil, maxTokens: nil, tools: nil, skills: nil,
                     loreEntryIDs: nil, isBuiltin: false)
        var tools: [String]? = TOOLS.compactMap { (toolFlags[$0.id] ?? true) ? $0.id : nil }
        if tools?.count == TOOLS.count { tools = nil }        // 全开 = 跟随全局
        var skills: [String]? = allSkillsOn ? nil : app.skills.compactMap { (skillFlags[$0.id] ?? false) ? $0.id : nil }
        if let s = skills, s.isEmpty { skills = nil }
        let updated = Agent(id: base.id, name: name, icon: icon, systemPrompt: systemPrompt,
                            model: useCustomModel && !modelText.isEmpty ? modelText : nil,
                            temperature: useCustomTemp ? temperature : nil,
                            topP: useCustomTopP ? topP : nil,
                            maxTokens: useCustomMaxTokens ? maxTokens : nil,
                            tools: tools,
                            skills: skills,
                            loreEntryIDs: loreIDs.isEmpty ? nil : Array(loreIDs),
                            isBuiltin: base.isBuiltin)
        app.saveAgent(updated)
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

    private var builtinSkills: [Skill] { app.skills.filter { !$0.isMarkdown } }
    private var markdownSkills: [Skill] { app.skills.filter(\.isMarkdown) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Markdown Skills")
                        .font(.system(size: 16, weight: .bold))
                    Text("每个技能都是一份保存在本机的 .md 指令文件")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.editingSkill = nil
                    app.showSkillEditor = true
                } label: {
                    Label("新建 Skill", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    skillGroup(title: "我的 Markdown Skills", subtitle: "可编辑 · 可删除 · 可直接修改源文件", skills: markdownSkills)
                    skillGroup(title: "内置技能", subtitle: "只读模板，可另存为 Markdown 后修改", skills: builtinSkills)
                }
                .padding(20)
            }

            Divider()
            HStack {
                Text(SkillStore.directory.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("打开 Skills 文件夹") { NSWorkspace.shared.open(SkillStore.directory) }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 700, height: 620)
        .onAppear { app.reloadSkills() }
        .sheet(isPresented: $app.showSkillEditor) { MarkdownSkillEditor() }
    }

    private func skillGroup(title: String, subtitle: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(skills.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if skills.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                    Text("还没有 Markdown Skill")
                        .font(.system(size: 12.5, weight: .medium))
                    Button("创建第一份 .md 技能") {
                        app.editingSkill = nil
                        app.showSkillEditor = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(skills) { skill in skillRow(skill) }
                }
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: skill.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(skill.isMarkdown ? Color.accentColor : Color.secondary)
                .frame(width: 38, height: 38)
                .background(
                    (skill.isMarkdown ? Color.accentColor : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name).font(.system(size: 12.5, weight: .semibold))
                    Text(skill.category.rawValue)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if skill.isMarkdown {
                        Text(".md")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(skill.desc)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if skill.isMarkdown {
                Button("编辑") {
                    app.editingSkill = skill
                    app.showSkillEditor = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let url = skill.fileURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                }
            } else {
                Button("另存为 MD") {
                    app.editingSkill = skill
                    app.showSkillEditor = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
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
                        ForEach(Array(PROVIDERS.keys.sorted()), id: \.self) { k in
                            Text(PROVIDERS[k]?.label ?? k).tag(k)
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
                        Stepper(value: $app.config.maxTokens, in: 256...32000, step: 256) {
                            Text("\(app.config.maxTokens) tokens（每次生成的最大长度）")
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 10) {
                        Text("输入窗口").frame(width: 60, alignment: .leading)
                        Picker("", selection: $app.config.contextWindow) {
                            Text("8k").tag(8192)
                            Text("16k").tag(16384)
                            Text("32k").tag(32768)
                            Text("64k").tag(65536)
                            Text("128k").tag(128000)
                            Text("200k").tag(200000)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        Text("tokens（模型上下文上限，用于预算告警）")
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

                Section("外观") {
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
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(app.testResult ?? "")
                    .font(.caption)
                    .foregroundStyle(app.testResult?.hasPrefix("✓") == true ? .green : .secondary)
                    .lineLimit(1)
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

    private func applyProviderPreset(_ p: String) {
        guard let preset = PROVIDERS[p] else { return }
        app.config.baseURL = preset.baseURL
        if let m = preset.models.first { app.config.model = m }
    }
}

// MARK: - 外观滑条

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
