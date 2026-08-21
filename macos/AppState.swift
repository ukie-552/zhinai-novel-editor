import Foundation
import Combine

enum SidebarTab: String, CaseIterable {
    case chapters = "章节"
    case lore = "设定库"
    case search = "搜索"
    case vectors = "向量库"
    case conversations = "多会话"
}

@MainActor
final class AppState: ObservableObject {
    // 作品与章节
    @Published var novels: [Novel] = []
    @Published var currentNovelID: UUID?
    @Published var chapters: [Chapter] = []
    @Published var entries: [Entry] = []
    @Published var selectedChapterID: UUID?

    // 本地向量库
    @Published var vectorLibraries: [VectorLibrary] = []
    @Published var selectedVectorLibraryID: UUID?
    @Published var vectorChapters: [VectorChapter] = []
    @Published var selectedVectorChapterID: UUID?
    @Published var vectorSearchText = ""
    @Published var vectorSearchResults: [VectorSearchResult] = []
    @Published var vectorImporting = false
    @Published var vectorImportMessage = ""

    // 会话与消息
    @Published var conversations: [Conversation] = []
    @Published var currentConversationID: UUID?
    @Published var messages: [Msg] = []

    // Agent
    @Published var agents: [Agent] = []
    @Published var currentAgentID: UUID = BUILTIN_AGENTS[0].id
    @Published var skills: [Skill] = []

    // UI 状态
    @Published var sidebarTab: SidebarTab = .chapters
    @Published var showSettings = false
    @Published var showEntrySheet = false
    @Published var editingEntry: Entry?
    @Published var showAgentSheet = false
    @Published var showAgentEditor = false
    @Published var editingAgent: Agent?
    @Published var showSkillManager = false
    @Published var showSkillEditor = false
    @Published var editingSkill: Skill?
    @Published var searchText = ""
    @Published var searchResults: (entries: [Entry], chapters: [Chapter]) = ([], [])
    @Published var draft = ""
    @Published var skillID = "chat"
    @Published var config = ConfigStore.load()
    @Published var toastText: String?
    @Published var testResult: String?
    @Published var confirmDeleteNovel = false

    // 生成状态
    @Published var streaming = false
    @Published var streamingText = ""
    @Published var lastPlan: ContextPlan?   // 最近一次请求的上下文用量
    private var streamTask: Task<Void, Never>?

    private var saveDebounce: Task<Void, Never>?
    private var outlineDebounce: Task<Void, Never>?

    var currentAgent: Agent { agents.first { $0.id == currentAgentID } ?? agents[0] }

    init() {
        agents = AgentStore.load()
        skills = SkillStore.load()
        vectorLibraries = VectorStore().libraries()
        selectedVectorLibraryID = vectorLibraries.first?.id
        if let id = selectedVectorLibraryID {
            vectorChapters = VectorStore().chapters(libraryID: id)
            selectedVectorChapterID = vectorChapters.first?.id
        }
        if !agents.contains(where: { $0.id == currentAgentID }) {
            currentAgentID = agents[0].id
        }
        novels = DB.shared.novels()
        if let first = novels.first {
            selectNovel(first.id)
        }
    }

    // MARK: - 作品

    func selectNovel(_ id: UUID) {
        flushSave()
        currentNovelID = id
        chapters = DB.shared.chapters(novelID: id)
        entries = DB.shared.entries(novelID: id)
        conversations = DB.shared.conversations(novelID: id)
        if conversations.isEmpty {
            conversations = [DB.shared.createConversation(novelID: id, title: "对话 1")]
        }
        currentConversationID = conversations.first?.id
        reloadMessages()
        searchText = ""
        searchResults = ([], [])
        draft = ""
        streamingText = ""
        lastPlan = nil
    }

    func createNovel() {
        let n = DB.shared.createNovel(title: "未命名作品")
        novels.insert(n, at: 0)
        selectNovel(n.id)
    }

    func renameNovel(_ id: UUID, title: String) {
        DB.shared.updateNovel(id: id, title: title)
        if let i = novels.firstIndex(where: { $0.id == id }) {
            novels[i].title = title
        }
    }

    func deleteNovel() {
        guard let id = currentNovelID else { return }
        DB.shared.deleteNovel(id: id)
        novels.removeAll { $0.id == id }
        currentNovelID = nil
        if let first = novels.first { selectNovel(first.id) }
        else { chapters = []; entries = []; conversations = []; messages = []; selectedChapterID = nil }
    }

    // MARK: - 章节

    func createChapter() {
        guard let nid = currentNovelID else { return }
        let c = DB.shared.createChapter(novelID: nid)
        chapters.append(c)
        selectedChapterID = c.id
        toast("已新建第 \(c.no) 章")
    }

    func selectChapter(_ id: UUID?) {
        flushSave()
        selectedChapterID = id
    }

    func deleteChapter() {
        guard let id = selectedChapterID else { return }
        flushSave()
        DB.shared.deleteChapter(id: id)
        chapters.removeAll { $0.id == id }
        selectedChapterID = chapters.first?.id
    }

    func moveChapter(_ direction: Int) {
        guard let id = selectedChapterID, let idx = chapters.firstIndex(where: { $0.id == id }) else { return }
        let j = idx + direction
        guard j >= 0 && j < chapters.count else { return }
        chapters.swapAt(idx, j)
        for (k, c) in chapters.enumerated() where c.no != k + 1 {
            DB.shared.updateChapter(id: c.id, no: k + 1)
            chapters[k].no = k + 1
        }
    }

    func chapterEdited(title: String? = nil, content: String? = nil) {
        guard let id = selectedChapterID, let idx = chapters.firstIndex(where: { $0.id == id }) else { return }
        if let title { chapters[idx].title = title }
        if let content { chapters[idx].content = content }
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, let c = self.chapters.first(where: { $0.id == id }) else { return }
            DB.shared.updateChapter(id: id, title: c.title, content: c.content)
            self.toast("✓ 已保存")
        }
    }

    func flushSave() {
        saveDebounce?.cancel()
        saveDebounce = nil
        guard let id = selectedChapterID, let c = chapters.first(where: { $0.id == id }) else { return }
        DB.shared.updateChapter(id: id, title: c.title, content: c.content)
    }

    func novelOutlineEdited(_ outline: String) {
        guard let id = currentNovelID else { return }
        if let i = novels.firstIndex(where: { $0.id == id }) { novels[i].outline = outline }
        outlineDebounce?.cancel()
        outlineDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, let n = self.novels.first(where: { $0.id == id }) else { return }
            DB.shared.updateNovel(id: id, outline: n.outline)
        }
    }

    // MARK: - 设定库

    func createEntry() {
        guard let nid = currentNovelID else { return }
        let e = DB.shared.createEntry(novelID: nid, title: "新设定")
        entries.insert(e, at: 0)
        editingEntry = e
        showEntrySheet = true
    }

    func saveEntry(type: String, title: String, content: String, keywords: String, pinned: Bool) {
        guard let nid = currentNovelID else { return }
        if let e = editingEntry {
            DB.shared.updateEntry(id: e.id, type: type, title: title, content: content, keywords: keywords, pinned: pinned)
            if let i = entries.firstIndex(where: { $0.id == e.id }) {
                entries[i] = Entry(id: e.id, novelID: e.novelID, type: type, title: title, content: content,
                                   keywords: keywords, pinned: pinned, createdAt: e.createdAt, updatedAt: Date())
            }
        } else {
            let e = DB.shared.createEntry(novelID: nid, type: type, title: title, content: content, keywords: keywords, pinned: pinned)
            entries.insert(e, at: 0)
        }
        showEntrySheet = false
        editingEntry = nil
        refreshSearch()
    }

    func deleteEntry(_ id: UUID) {
        DB.shared.deleteEntry(id: id)
        entries.removeAll { $0.id == id }
        if editingEntry?.id == id { editingEntry = nil; showEntrySheet = false }
        refreshSearch()
    }

    // MARK: - 搜索

    func refreshSearch() {
        guard let nid = currentNovelID, !searchText.isEmpty else {
            searchResults = ([], [])
            return
        }
        searchResults = DB.shared.search(searchText, novelID: nid)
    }

    // MARK: - 本地向量库

    func importVectorTXT(_ url: URL, expectedChapterCount: Int? = nil) {
        vectorImporting = true
        vectorImportMessage = "正在解析并向量化…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let library = try VectorStore().importTXT(url: url, expectedChapterCount: expectedChapterCount)
                let libraries = VectorStore().libraries()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.vectorLibraries = libraries
                    self.selectedVectorLibraryID = library.id
                    self.vectorChapters = VectorStore().chapters(libraryID: library.id)
                    self.selectedVectorChapterID = self.vectorChapters.first?.id
                    self.vectorImporting = false
                    self.vectorImportMessage = "已导入 \(library.chapterCount) 章 / \(library.chunkCount) 个向量片段"
                    self.toast("向量库已创建：\(library.title)")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.vectorImporting = false
                    self.vectorImportMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func deleteVectorLibrary(_ library: VectorLibrary) {
        VectorStore().delete(library)
        vectorLibraries = VectorStore().libraries()
        if selectedVectorLibraryID == library.id {
            selectedVectorLibraryID = vectorLibraries.first?.id
            vectorChapters = selectedVectorLibraryID.map { VectorStore().chapters(libraryID: $0) } ?? []
            selectedVectorChapterID = vectorChapters.first?.id
            vectorSearchResults = []
        }
    }

    func selectVectorLibrary(_ id: UUID?) {
        selectedVectorLibraryID = id
        guard let id else {
            vectorChapters = []
            selectedVectorChapterID = nil
            return
        }
        vectorChapters = VectorStore().chapters(libraryID: id)
        if !vectorChapters.contains(where: { $0.id == selectedVectorChapterID }) {
            selectedVectorChapterID = vectorChapters.first?.id
        }
    }

    func saveVectorChapter(id: UUID, title: String, content: String) -> Bool {
        guard let index = vectorChapters.firstIndex(where: { $0.id == id }),
              let updated = VectorStore().updateChapter(vectorChapters[index], title: title, content: content) else {
            return false
        }
        vectorChapters[index] = updated
        vectorLibraries = VectorStore().libraries()
        if !vectorSearchText.isEmpty { searchVectors() }
        toast("第 \(updated.no) 章已保存并重建向量")
        return true
    }

    func searchVectors() {
        guard let id = selectedVectorLibraryID else {
            vectorSearchResults = []
            return
        }
        vectorSearchResults = VectorStore().search(libraryID: id, queryText: vectorSearchText)
    }

    // MARK: - 会话

    func reloadMessages() {
        guard let nid = currentNovelID, let cid = currentConversationID else {
            messages = []
            return
        }
        messages = DB.shared.messages(novelID: nid, conversationID: cid)
    }

    func createConversation() {
        guard let nid = currentNovelID else { return }
        let c = DB.shared.createConversation(novelID: nid)
        conversations.insert(c, at: 0)
        currentConversationID = c.id
        messages = []
        lastPlan = nil
    }

    func selectConversation(_ id: UUID) {
        flushSave()
        currentConversationID = id
        reloadMessages()
        lastPlan = nil
    }

    func renameConversation(_ id: UUID, title: String) {
        DB.shared.renameConversation(id: id, title: title)
        if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].title = title }
    }

    func deleteConversation() {
        guard let id = currentConversationID, let nid = currentNovelID else { return }
        DB.shared.deleteConversation(id: id)
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            conversations = [DB.shared.createConversation(novelID: nid)]
        }
        currentConversationID = conversations.first?.id
        reloadMessages()
    }

    func clearMessages() {
        guard let id = currentConversationID else { return }
        DB.shared.clearMessages(conversationID: id)
        messages = []
    }

    // MARK: - Agent

    func selectAgent(_ id: UUID) {
        currentAgentID = id
        // 当前技能不在该 Agent 的白名单内时，回退到其第一个可用技能
        if let allowed = currentAgent.skills, !allowed.contains(skillID) {
            skillID = allowed.first ?? "chat"
        }
    }

    /// 当前 Agent 可用的技能（白名单过滤）
    var availableSkills: [Skill] {
        if let ids = currentAgent.skills {
            return skills.filter { ids.contains($0.id) }
        }
        return skills
    }

    func reloadSkills() {
        skills = SkillStore.load()
        if !skills.contains(where: { $0.id == skillID }) {
            skillID = skills.first?.id ?? "chat"
        }
    }

    func saveSkill(existing: Skill?, name: String, desc: String, category: SkillCategory,
                   icon: String, needsText: Bool, chapters: Int, markdown: String) throws {
        _ = try SkillStore.save(existing: existing, name: name, desc: desc, category: category,
                                icon: icon, needsText: needsText, chapters: chapters, markdown: markdown)
        reloadSkills()
        showSkillEditor = false
        editingSkill = nil
    }

    func deleteSkill(_ skill: Skill) {
        guard skill.isMarkdown else { return }
        do {
            try SkillStore.delete(skill)
            for index in agents.indices {
                agents[index].skills?.removeAll { $0 == skill.id }
            }
            AgentStore.save(agents)
            reloadSkills()
            showSkillEditor = false
            editingSkill = nil
        } catch {
            toast("删除 Skill 失败：\(error.localizedDescription)")
        }
    }

    func saveAgent(_ agent: Agent) {
        if let i = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[i] = agent
        } else {
            agents.append(agent)
        }
        AgentStore.save(agents)
        if currentAgentID == agent.id {
            if let allowed = agent.skills, !allowed.contains(skillID) {
                skillID = allowed.first ?? "chat"
            }
        }
        showAgentEditor = false
        showAgentSheet = true
        editingAgent = nil
    }

    func createAgent() {
        let a = Agent(id: UUID(), name: "新 Agent", icon: "person.crop.circle", systemPrompt: "", temperature: nil, isBuiltin: false)
        editingAgent = a
        showAgentSheet = true
        showAgentEditor = true
    }

    func duplicateAgent(_ a: Agent) {
        let copy = Agent(id: UUID(), name: a.name + "（副本）", icon: a.icon,
                         systemPrompt: a.systemPrompt, temperature: a.temperature, isBuiltin: false)
        agents.append(copy)
        AgentStore.save(agents)
        toast("已复制为自定义 Agent")
    }

    func deleteAgent(_ id: UUID) {
        guard let a = agents.first(where: { $0.id == id }), !a.isBuiltin else { return }
        agents.removeAll { $0.id == id }
        if currentAgentID == id { currentAgentID = agents[0].id }
        if editingAgent?.id == id {
            editingAgent = nil
            showAgentEditor = false
            showAgentSheet = true
        }
        AgentStore.save(agents)
    }

    // MARK: - 对话与生成

    func sendMessage() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        performSend(text: t)
    }

    /// 编辑区的 AI 操作：以空指令直接触发技能（续写/润色/检查）
    func runAISkill(_ id: String) {
        skillID = id
        performSend(text: "")
    }

    private func performSend(text: String) {
        guard let nid = currentNovelID else { return toast("请先创建作品") }
        guard let cid = currentConversationID else { return toast("请先创建对话") }
        guard !streaming else { return }
        let skill = skillByID(skillID, skills: skills)
        if skill.id == "chat" && text.isEmpty { return }
        if config.apiKey.isEmpty && config.provider != "ollama" {
            toast("请先在设置中配置 API Key")
            showSettings = true
            return
        }
        if config.model.isEmpty {
            toast("请先在设置中配置模型")
            showSettings = true
            return
        }

        // 用户消息入库
        messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid, role: "user", content: text, skill: skill.id))

        // 组装上下文：世界书激活（关键词触发 + Agent 知识库挂载，去重）+ 前文（按预算截断）
        let chaptersText = chapters.map { String($0.content.prefix(ContextLimits.chapterMax)) }.joined()
        let historyText = messages.suffix(8).map { $0.content }.joined()
        let scanText = text + "\n" + chaptersText + "\n" + historyText
        var ctxEntries = activateLorebook(entries: entries, scanText: scanText)
        if let ids = currentAgent.loreEntryIDs {
            for e in entries where ids.contains(e.id) && !ctxEntries.contains(where: { $0.id == e.id }) {
                ctxEntries.append(e)
            }
        }
        let prev = DB.shared.lastChapters(novelID: nid, count: skill.chapters)
        let novel = novels.first { $0.id == nid } ?? Novel(id: nid, title: "未命名", desc: "", outline: "", createdAt: Date(), updatedAt: Date())

        let targetText: String
        if skill.needsText {
            targetText = selectedChapterID.flatMap { cid in chapters.first { $0.id == cid }?.content } ?? ""
        } else {
            targetText = ""
        }

        let ctx = GenContext(novel: novel, chapters: prev, entries: ctxEntries,
                             history: messages.dropLast(1).map { $0 },
                             userText: text, targetText: targetText, skill: skill)
        let req = buildRequest(ctx: ctx)
        lastPlan = req.plan

        // 最终系统提示词 = Agent 人格 + 上下文
        let agent = currentAgent
        let system: String
        if agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            system = req.system
        } else {
            system = agent.systemPrompt + "\n\n" + req.system
        }
        // Agent 参数覆盖：模型 / 温度 / top-p / 输出上限（nil = 跟随全局）
        let useModel = agent.model ?? config.model
        let useTemperature = agent.temperature ?? config.temperature
        let useTopP = agent.topP ?? config.topP
        let useMaxTokens = agent.maxTokens ?? config.maxTokens
        // 工具白名单：nil = 跟随全局开关；[] = 禁用；[名称] = 仅这些
        var tools: [[String: Any]]? = (config.enableTools && config.provider != "anthropic") ? Self.writingTools : nil
        if let allowed = agent.tools {
            tools = tools?.filter { d in
                guard let fn = d["function"] as? [String: Any], let name = fn["name"] as? String else { return false }
                return allowed.contains(name)
            }
        }

        // 占位 assistant 消息
        streaming = true
        streamingText = ""

        streamTask = Task { [weak self] in
            guard let self else { return }
            var msgs = req.messages
            let maxRounds = (tools?.isEmpty == false) ? 3 : 1
            var cfg = self.config
            cfg.model = useModel
            do {
                for round in 0..<maxRounds {
                    let (outText, toolCalls) = try await LLM.streamChat(
                        config: cfg, system: system, messages: msgs,
                        temperature: useTemperature, topP: useTopP, maxTokens: useMaxTokens,
                        tools: tools
                    ) { delta in
                        self.streamingText += delta
                    }
                    if toolCalls.isEmpty {
                        break
                    }
                    // 记录 assistant 的调用，执行工具，结果回填
                    msgs.append(ChatMsg(role: "assistant", content: outText, toolCalls: toolCalls))
                    for tc in toolCalls {
                        let result = Self.executeTool(tc, app: self)
                        let snippet = String(result.prefix(200))
                        self.streamingText += "\n\n> 🔧 工具「\(tc.name)」\n> \(snippet)\n\n"
                        msgs.append(ChatMsg(role: "tool", content: result, toolCallID: tc.id))
                    }
                    if round == maxRounds - 1 {
                        self.streamingText += "\n\n（已到达工具调用轮次上限）"
                    }
                }
                let final = self.streamingText
                self.streaming = false
                self.streamingText = ""
                if !final.isEmpty {
                    self.messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                              role: "assistant", content: final, skill: skill.id))
                }
            } catch {
                let msg = error.localizedDescription
                self.streaming = false
                self.streamingText = ""
                self.messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                          role: "assistant", content: "❌ \(msg)", skill: skill.id))
                self.toast(msg)
            }
        }
    }

    // MARK: - 写作工具（Tool Use）
    /// 给模型的只读工具：搜索设定库、读取章节、列出章节、读取大纲。
    /// 工具结果会回填给模型继续生成，界面以「🔧」事件行展示。

    static let writingTools: [[String: Any]] = [
        ["type": "function", "function": [
            "name": "search_database",
            "description": "在当前作品中全文搜索设定库条目与章节内容（支持中文关键词），返回匹配的设定与章节片段",
            "parameters": ["type": "object",
                           "properties": ["query": ["type": "string", "description": "搜索关键词"]],
                           "required": ["query"]]]],
        ["type": "function", "function": [
            "name": "read_chapter",
            "description": "读取当前作品指定章节的完整内容（按章节号，从 1 开始）",
            "parameters": ["type": "object",
                           "properties": ["number": ["type": "integer", "description": "章节号"]],
                           "required": ["number"]]]],
        ["type": "function", "function": [
            "name": "list_chapters",
            "description": "列出当前作品所有章节的编号与标题",
            "parameters": ["type": "object", "properties": [:]]]],
        ["type": "function", "function": [
            "name": "get_outline",
            "description": "读取当前作品的故事大纲",
            "parameters": ["type": "object", "properties": [:]]]],
    ]

    static func executeTool(_ tc: ToolCall, app: AppState) -> String {
        guard let nid = app.currentNovelID else { return "错误：未选择作品" }
        let args = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) as? [String: Any] ?? [:]
        switch tc.name {
        case "search_database":
            guard let q = args["query"] as? String, !q.isEmpty else { return "错误：缺少 query 参数" }
            let r = DB.shared.search(q, novelID: nid)
            var out = "搜索结果「\(q)」：\n"
            if r.entries.isEmpty && r.chapters.isEmpty { return "未找到任何匹配内容" }
            for e in r.entries.prefix(5) {
                out += "【设定·\(entryTypeLabel(e.type))】\(e.title)：\(e.content.prefix(300))\n"
            }
            for c in r.chapters.prefix(5) {
                out += "【第\(c.no)章】\(c.title)：\(c.content.prefix(400))\n"
            }
            return out
        case "read_chapter":
            guard let n = args["number"] as? Int else { return "错误：缺少 number 参数" }
            let ch = app.chapters.first { $0.no == n }
            guard let ch else { return "错误：不存在第 \(n) 章（当前共 \(app.chapters.count) 章）" }
            return "第\(ch.no)章 \(ch.title)\n\(ch.content.prefix(6000))"
        case "list_chapters":
            if app.chapters.isEmpty { return "暂无章节" }
            return app.chapters.map { "第\($0.no)章 \($0.title.isEmpty ? "（无标题）" : $0.title)" }.joined(separator: "\n")
        case "get_outline":
            let outline = app.novels.first { $0.id == nid }?.outline ?? ""
            return outline.isEmpty ? "当前作品还没有大纲" : String(outline.prefix(4000))
        default:
            return "未知工具：\(tc.name)"
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streaming = false
        let partial = streamingText
        streamingText = ""
        if let nid = currentNovelID, let cid = currentConversationID, !partial.isEmpty {
            messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                 role: "assistant", content: partial + "\n\n（已停止）",
                                                 skill: skillByID(skillID, skills: skills).id))
        }
    }

    /// 将 AI 输出插入为新章节
    func insertAsChapter(_ text: String) {
        guard let nid = currentNovelID else { return }
        let c = DB.shared.createChapter(novelID: nid, title: "", content: text)
        chapters.append(c)
        selectedChapterID = c.id
        toast("已插入为第 \(c.no) 章")
    }

    /// 将 AI 输出放入当前章节编辑器
    func sendToEditor(_ text: String) {
        guard let id = selectedChapterID, let idx = chapters.firstIndex(where: { $0.id == id }) else { return }
        chapters[idx].content = text
        chapterEdited(content: text)
        toast("已放入编辑器")
    }

    // MARK: - 设置

    func saveConfig() {
        ConfigStore.save(config)
        toast("设置已保存")
    }

    func testConnection() async {
        testResult = "测试中…"
        do {
            let reply = try await LLM.testConnection(config: config)
            testResult = "✓ \(reply)"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }

    func loadOllamaModels() async {
        do {
            let models = try await LLM.ollamaModels(baseURL: config.baseURL)
            if let first = models.first { config.model = first }
            testResult = models.isEmpty ? "Ollama 无可用模型" : "发现 \(models.count) 个模型"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }

    func toast(_ s: String) {
        toastText = s
    }
}
