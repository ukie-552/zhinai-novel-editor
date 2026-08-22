import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

enum SidebarTab: String, CaseIterable {
    case books = "书籍"
    case chapters = "章节"
    case lore = "设定库"
    case search = "搜索"
    case vectors = "向量库"
    case conversations = "多会话"
}

enum ContentEditingMode {
    case book
    case chapter
}

@MainActor
final class AppState: ObservableObject {
    // 作品与章节
    @Published var novels: [Novel] = []
    @Published var currentNovelID: UUID?
    @Published var chapters: [Chapter] = []
    @Published var entries: [Entry] = []
    @Published var storyNodes: [StoryNode] = []
    @Published var selectedChapterID: UUID?
    @Published var contentEditingMode: ContentEditingMode = .book

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
    @Published var conversationRunStates: [UUID: ConversationRun] = [:]
    var backgroundConversationTasks: [UUID: Task<Void, Never>] = [:]
    /// 写工具按会话隔离；锁会保留到该会话本轮任务结束，防止跨会话静默覆盖。
    var workspaceResourceOwners: [String: UUID] = [:]
    var conversationOwnedResources: [UUID: Set<String>] = [:]

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
    @Published private(set) var activeRequestSkillID = "chat"
    @Published var config = ConfigStore.load()
    @Published var toastText: String?
    @Published var testResult: String?
    @Published var confirmDeleteNovel = false

    // 生成状态
    @Published var streaming = false
    @Published private(set) var isCompressingContext = false
    @Published var streamingText = ""
    @Published var streamingReasoningDuration: Double = 0
    @Published var streamingToolName: String?
    @Published var lastPlan: ContextPlan?   // 最近一次请求的上下文用量
    @Published private(set) var currentRequestInputTokens = 0
    @Published private(set) var currentRequestOutputTokens = 0
    @Published private(set) var currentRequestTextOutputTokens = 0
    @Published private(set) var currentRequestToolOutputTokens = 0
    @Published private(set) var currentRequestOutputCharacters = 0
    @Published private(set) var currentRequestOutputLines = 0
    private var currentRequestTextOutput = ""
    private var currentRequestToolOutput = ""
    private var streamTask: Task<Void, Never>?
    private var streamingReasoningStartedAt: Date?
    private var streamingReasoningFinished = false

    private var saveDebounce: Task<Void, Never>?
    private var outlineDebounce: Task<Void, Never>?

    var currentAgent: Agent { agents.first { $0.id == currentAgentID } ?? agents[0] }

    init() {
        DB.shared.recoverInterruptedConversationRuns()
        conversationRunStates = Dictionary(uniqueKeysWithValues: DB.shared.conversationRuns().map { ($0.conversationID, $0) })
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
        // 启动时不擅自替用户选书；公共会话可直接用于找灵感或让模型创建新书。
        selectNoNovel(notifyModel: false)
    }

    // MARK: - 作品

    func selectNovel(_ id: UUID) {
        let selectionChanged = currentNovelID != id
        flushSave()
        currentNovelID = id
        if selectionChanged {
            selectedChapterID = nil
            contentEditingMode = .book
        }
        chapters = DB.shared.chapters(novelID: id)
        entries = DB.shared.entries(novelID: id)
        storyNodes = DB.shared.storyNodes(novelID: id)
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
        resetCurrentRequestUsage()
        if selectionChanged, let novel = novels.first(where: { $0.id == id }) {
            appendSelectionEvent("已切换到书籍私库《\(novel.title)》（book_id: \(novel.id.uuidString)）。后续讨论与操作以此书为当前书籍。")
        }
    }

    /// 进入不绑定任何作品的公共会话作用域。
    func selectNoNovel(notifyModel: Bool = true) {
        let selectionChanged = currentNovelID != nil
        flushSave()
        currentNovelID = nil
        chapters = []
        entries = []
        storyNodes = []
        selectedChapterID = nil
        contentEditingMode = .book
        conversations = DB.shared.conversations(novelID: GLOBAL_CHAT_NOVEL_ID)
        if conversations.isEmpty {
            conversations = [DB.shared.createConversation(novelID: GLOBAL_CHAT_NOVEL_ID, title: "公共会话")]
        }
        currentConversationID = conversations.first?.id
        reloadMessages()
        searchText = ""
        searchResults = ([], [])
        draft = ""
        streamingText = ""
        lastPlan = nil
        resetCurrentRequestUsage()
        if (notifyModel && selectionChanged) || messages.isEmpty {
            appendSelectionEvent("已切换到公共会话，当前未选择任何书籍。用户可能正在寻找灵感、策划新书，或要求创建一本新书；不要假定已有作品。")
        }
    }

    func createNovel(title: String = "未命名作品", desc: String = "", metadata: BookMetadata = BookMetadata()) {
        var n = DB.shared.createNovel(title: title, desc: desc)
        DB.shared.updateNovel(id: n.id, metadata: metadata)
        n.metadata = metadata
        novels.insert(n, at: 0)
        selectNovel(n.id)
        toast("《\(n.title)》已保存到本地")
    }

    func importBook() {
        let panel = NSOpenPanel()
        panel.title = "导入织奈书籍"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let document = try ZhinaiBookDocument.read(from: url)
            let novel = DB.shared.createNovel(title: document.book.title, desc: document.book.description)
            DB.shared.updateNovel(id: novel.id, outline: document.book.outline)
            var metadata = document.book.metadata ?? BookMetadata()
            if metadata.authors.isEmpty, let author = document.book.author, !author.isEmpty {
                metadata.authors = [author]
            }
            if let config = document.config {
                metadata.subtitle = config.subtitle
                metadata.authors = config.authors
                metadata.penName = config.penName
                metadata.genres = config.genre.isEmpty ? [] : [config.genre]
                metadata.tags = config.tags
                metadata.platform = config.platform
                metadata.status = config.status
                metadata.language = config.language
                metadata.targetChapters = config.targetChapters
                metadata.chapterWordCount = config.chapterWordCount
                metadata.reviewMode = config.reviewMode
                metadata.styleLibraryID = config.styleLibraryID ?? ""
                metadata.styleStrength = config.styleStrength ?? 0.65
            }
            if let story = document.story {
                metadata.authorIntent = story.authorIntent
                metadata.currentFocus = story.currentFocus
                metadata.storyFrame = story.storyFrame
                metadata.bookRules = story.bookRules
                DB.shared.updateNovel(id: novel.id, outline: story.volumeOutline)
            }
            if let publishing = document.publishing {
                metadata.seriesName = publishing.seriesName
                metadata.seriesNumber = publishing.seriesNumber
                metadata.targetAudience = publishing.targetAudience
                metadata.contentRating = publishing.contentRating
                metadata.isbn = publishing.isbn
                metadata.publisher = publishing.publisher
                metadata.publicationDate = publishing.publicationDate
                metadata.rights = publishing.rights
                metadata.source = publishing.source
            }
            DB.shared.updateNovel(id: novel.id, metadata: metadata)
            for chapter in document.chapters.sorted(by: { $0.number < $1.number }) {
                _ = DB.shared.createChapter(novelID: novel.id, title: chapter.title, content: chapter.content)
            }
            for entry in document.lore {
                _ = DB.shared.createEntry(
                    novelID: novel.id,
                    type: entry.type,
                    title: entry.title,
                    content: entry.content,
                    keywords: entry.keywords.joined(separator: ", "),
                    pinned: entry.pinned
                )
            }
            novels = DB.shared.novels()
            selectNovel(novel.id)
            sidebarTab = .chapters
            toast("已导入《\(document.book.title)》")
        } catch {
            showBookFileError(title: "无法导入书籍", error: error)
        }
    }

    func exportCurrentBook() {
        flushSave()
        guard let novel = novels.first(where: { $0.id == currentNovelID }) else {
            return toast("请先选择一本书")
        }
        let document = ZhinaiBookDocument(
            novel: novel,
            chapters: chapters,
            entries: entries
        )
        let panel = NSSavePanel()
        panel.title = "导出织奈书籍"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ZhinaiBookDocument.suggestedFilename(for: novel.title)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try document.write(to: url)
            toast("书籍已导出")
        } catch {
            showBookFileError(title: "无法导出书籍", error: error)
        }
    }

    private func showBookFileError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func renameNovel(_ id: UUID, title: String) {
        DB.shared.updateNovel(id: id, title: title)
        if let i = novels.firstIndex(where: { $0.id == id }) {
            novels[i].title = title
        }
    }

    func updateCurrentBook(title: String, desc: String, outline: String, metadata: BookMetadata) {
        guard let id = currentNovelID, let i = novels.firstIndex(where: { $0.id == id }) else { return }
        let previous = novels[i]
        let metadataJSON = (try? JSONEncoder().encode(previous.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        DB.shared.addRevision(
            novelID: id, resourceType: "book", resourceID: id.uuidString,
            conversationID: currentConversationID, operation: "before_ui_update",
            snapshotJSON: GovernanceTools.json([
                "id": id.uuidString, "title": previous.title, "description": previous.desc,
                "outline": previous.outline, "metadata": metadataJSON
            ])
        )
        DB.shared.updateNovel(id: id, title: title, desc: desc, outline: outline, metadata: metadata)
        novels[i].title = title
        novels[i].desc = desc
        novels[i].outline = outline
        novels[i].metadata = metadata
        novels[i].updatedAt = Date()
        toast("书籍上下文已保存")
    }

    func deleteNovel() {
        guard let id = currentNovelID else { return }
        for conversationID in conversationRunStates.values.filter({ $0.novelID == id }).map(\.conversationID) {
            if backgroundConversationTasks[conversationID] != nil { _ = cancelConversationRun(conversationID) }
        }
        DB.shared.deleteNovel(id: id)
        novels.removeAll { $0.id == id }
        currentNovelID = nil
        selectNoNovel()
    }

    // MARK: - 章节

    func createChapter() {
        guard let nid = currentNovelID else { return }
        let c = DB.shared.createChapter(novelID: nid)
        chapters.append(c)
        selectedChapterID = c.id
        contentEditingMode = .chapter
        toast("已新建第 \(c.no) 章")
    }

    func selectChapter(_ id: UUID?) {
        flushSave()
        selectedChapterID = id
        contentEditingMode = id == nil ? .book : .chapter
    }

    func showBookWorkspace() {
        flushSave()
        selectedChapterID = nil
        contentEditingMode = .book
    }

    func deleteChapter() {
        guard let id = selectedChapterID else { return }
        flushSave()
        DB.shared.deleteChapter(id: id)
        chapters.removeAll { $0.id == id }
        selectedChapterID = nil
        contentEditingMode = .book
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

    // MARK: - 书籍创作卡片

    func refreshStoryNodes() {
        guard let id = currentNovelID else { storyNodes = []; return }
        storyNodes = DB.shared.storyNodes(novelID: id)
    }

    @discardableResult
    func createStoryNode(kind: String, title: String = "") -> StoryNode? {
        guard let id = currentNovelID, STORY_NODE_KINDS.contains(where: { $0.id == kind }) else { return nil }
        let definition = storyNodeKind(kind)
        let node = DB.shared.createStoryNode(
            novelID: id, kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新建\(definition.label)" : title
        )
        refreshStoryNodes()
        return node
    }

    func updateStoryNode(_ node: StoryNode, kind: String, title: String, content: String,
                         status: String, parentID: UUID?, sortOrder: Int, metadataJSON: String) {
        guard STORY_NODE_KINDS.contains(where: { $0.id == kind }) else { return }
        saveStoryNodeRevision(node, operation: "before_ui_update")
        DB.shared.updateStoryNode(id: node.id, kind: kind, title: title, content: content,
                                  status: status, parentID: parentID, setParent: true,
                                  sortOrder: sortOrder, metadataJSON: metadataJSON)
        refreshStoryNodes()
        toast("\(storyNodeKind(kind).label)已保存")
    }

    func deleteStoryNode(_ node: StoryNode) {
        saveStoryNodeRevision(node, operation: "before_ui_delete")
        DB.shared.deleteStoryNode(id: node.id)
        refreshStoryNodes()
        toast("已删除《\(node.title)》")
    }

    private func saveStoryNodeRevision(_ node: StoryNode, operation: String) {
        DB.shared.addRevision(
            novelID: node.novelID, resourceType: "story_node", resourceID: node.id.uuidString,
            conversationID: currentConversationID, operation: operation,
            snapshotJSON: GovernanceTools.json([
                "id": node.id.uuidString, "kind": node.kind, "title": node.title,
                "content": node.content, "status": node.status,
                "parent_id": node.parentID?.uuidString as Any,
                "sort_order": node.sortOrder, "metadata_json": node.metadataJSON
            ])
        )
    }

    // MARK: - 设定库

    func createEntry(type: String = "note") {
        guard let nid = currentNovelID else { return }
        let safeType = ENTRY_TYPES.contains(where: { $0.id == type }) ? type : "note"
        let e = DB.shared.createEntry(novelID: nid, type: safeType, title: "新\(entryTypeLabel(safeType))")
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

    func refreshVectorLibraries() {
        let previousSelection = selectedVectorLibraryID
        vectorLibraries = VectorStore().libraries()
        if let previousSelection, vectorLibraries.contains(where: { $0.id == previousSelection }) {
            selectVectorLibrary(previousSelection)
        } else {
            selectVectorLibrary(vectorLibraries.first?.id)
        }
        if !vectorSearchText.isEmpty { searchVectors() }
        vectorImportMessage = "数据库已刷新 · \(vectorLibraries.count) 本书"
        toast("本地写法库已刷新")
    }

    func importVectorTXT(_ url: URL, expectedChapterCount: Int? = nil) {
        vectorImporting = true
        vectorImportMessage = "正在解析并建立写法向量…"
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
                    self.toast("写法向量库已创建：\(library.title)")
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

    func updateVectorLibrary(_ library: VectorLibrary, title: String, author: String,
                             category: String, summary: String) -> Bool {
        guard VectorStore().updateLibrary(library, title: title, author: author,
                                          category: category, summary: summary) else {
            toast("书籍信息保存失败")
            return false
        }
        vectorLibraries = VectorStore().libraries()
        toast("写法库书籍信息已保存")
        return true
    }

    func refreshVectorLibraryMetadata(_ library: VectorLibrary) {
        guard VectorStore().refreshLibraryMetadata(library) else {
            toast("无法从源 TXT 读取书籍信息")
            return
        }
        vectorLibraries = VectorStore().libraries()
        toast("已从 TXT 刷新书名、作者、字数、书籍 ID 和简介")
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
        guard let cid = currentConversationID else {
            messages = []
            return
        }
        let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
        messages = DB.shared.messages(novelID: nid, conversationID: cid)
    }

    func createConversation() {
        let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
        let c = DB.shared.createConversation(novelID: nid)
        conversations.insert(c, at: 0)
        currentConversationID = c.id
        messages = []
        lastPlan = nil
        resetCurrentRequestUsage()
        appendCurrentSelectionEvent()
    }

    func selectConversation(_ id: UUID) {
        flushSave()
        currentConversationID = id
        reloadMessages()
        lastPlan = nil
        resetCurrentRequestUsage()
    }

    func renameConversation(_ id: UUID, title: String) {
        DB.shared.renameConversation(id: id, title: title)
        if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].title = title }
    }

    func deleteConversation() {
        guard let id = currentConversationID else { return }
        if backgroundConversationTasks[id] != nil { _ = cancelConversationRun(id) }
        let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
        DB.shared.deleteConversation(id: id)
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            conversations = [DB.shared.createConversation(novelID: nid)]
        }
        currentConversationID = conversations.first?.id
        reloadMessages()
        resetCurrentRequestUsage()
        if messages.isEmpty { appendCurrentSelectionEvent() }
    }

    func clearMessages() {
        guard let id = currentConversationID else { return }
        DB.shared.clearMessages(conversationID: id)
        messages = []
        resetCurrentRequestUsage()
        appendCurrentSelectionEvent()
    }

    /// 选择状态只在发生变化时写入一次对话历史，避免每轮重复注入。
    private func appendCurrentSelectionEvent() {
        if let novel = novels.first(where: { $0.id == currentNovelID }) {
            appendSelectionEvent("已切换到书籍私库《\(novel.title)》（book_id: \(novel.id.uuidString)）。后续讨论与操作以此书为当前书籍。")
        } else {
            appendSelectionEvent("已切换到公共会话，当前未选择任何书籍。用户可能正在寻找灵感、策划新书，或要求创建一本新书；不要假定已有作品。")
        }
    }

    private func appendSelectionEvent(_ content: String) {
        guard let cid = currentConversationID else { return }
        let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
        let event = DB.shared.addMessage(novelID: nid, conversationID: cid,
                                         role: "event", content: content, skill: "context_event")
        messages.append(event)
    }

    // MARK: - Agent

    func selectAgent(_ id: UUID) {
        currentAgentID = id
    }

    /// 快捷任务可使用完整技能库；对话中的 Agent 通过动态索引自行调取。
    var availableSkills: [Skill] {
        return skills
    }

    func reloadSkills() {
        skills = SkillStore.load()
        var changed = false
        for index in agents.indices {
            if let id = agents[index].fixedSkillID, !skills.contains(where: { $0.id == id }) {
                agents[index].fixedSkillID = nil
                changed = true
            }
        }
        if changed { AgentStore.save(agents) }
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
                if agents[index].fixedSkillID == skill.id { agents[index].fixedSkillID = nil }
            }
            AgentStore.save(agents)
            reloadSkills()
            showSkillEditor = false
            editingSkill = nil
        } catch {
            toast("删除 Skill 失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func importSkills(from urls: [URL]) -> Int {
        var imported = 0
        var failures: [String] = []
        for url in urls {
            do {
                try SkillStore.importFile(url)
                imported += 1
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if imported > 0 { reloadSkills() }
        if failures.isEmpty {
            toast("已导入 \(imported) 个 Markdown Skill")
        } else if imported > 0 {
            toast("已导入 \(imported) 个，\(failures.count) 个未导入")
        } else {
            toast(failures.first ?? "没有可导入的 Markdown Skill")
        }
        return imported
    }

    func saveAgent(_ agent: Agent) {
        if let i = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[i] = agent
        } else {
            agents.append(agent)
        }
        AgentStore.save(agents)
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
        let copyID = UUID()
        var copiedAvatarPath: String?
        if let avatarPath = a.avatarPath, FileManager.default.fileExists(atPath: avatarPath) {
            let sourceURL = URL(fileURLWithPath: avatarPath)
            let avatarDir = AppPaths.dataDir.appendingPathComponent("AgentAvatars", isDirectory: true)
            let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
            let destinationURL = avatarDir.appendingPathComponent("\(copyID.uuidString).\(fileExtension)")
            try? FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
            if (try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)) != nil {
                copiedAvatarPath = destinationURL.path
            }
        }
        let copy = Agent(id: copyID, name: a.name + "（副本）", icon: a.icon, avatarPath: copiedAvatarPath,
                         systemPrompt: a.systemPrompt, temperature: a.temperature, isBuiltin: false)
        var configuredCopy = copy
        configuredCopy.model = a.model
        configuredCopy.topP = a.topP
        configuredCopy.maxTokens = a.maxTokens
        configuredCopy.tools = a.tools
        configuredCopy.skills = a.skills
        configuredCopy.fixedSkillID = a.fixedSkillID
        configuredCopy.loreEntryIDs = a.loreEntryIDs
        agents.append(configuredCopy)
        AgentStore.save(agents)
        toast("已复制为自定义 Agent")
    }

    func deleteAgent(_ id: UUID) {
        guard let a = agents.first(where: { $0.id == id }), !a.isBuiltin else { return }
        if let avatarPath = a.avatarPath {
            let avatarURL = URL(fileURLWithPath: avatarPath)
            let avatarDir = AppPaths.dataDir.appendingPathComponent("AgentAvatars", isDirectory: true)
            if avatarURL.deletingLastPathComponent().standardizedFileURL == avatarDir.standardizedFileURL {
                try? FileManager.default.removeItem(at: avatarURL)
            }
        }
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
        performSend(text: t, requestedSkillID: "chat")
    }

    /// 编辑区快捷任务：只对这一轮生效，不改变 Agent 的固定 Skill。
    func runAISkill(_ id: String) {
        performSend(text: "", requestedSkillID: id)
    }

    private func performSend(text: String, requestedSkillID: String,
                             compressionIndicatorPrepared: Bool = false) {
        guard !streaming, !isCompressingContext || compressionIndicatorPrepared else { return }
        let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
        if currentConversationID == nil { createConversation() }
        guard let cid = currentConversationID else { return toast("无法创建对话") }
        // 工具从数据库读取章节；发起请求前先落盘编辑器中的最新草稿。
        flushSave()
        let requestedSkill = skillByID(requestedSkillID, skills: skills)
        let skill = requestedSkill.id == "chat" || availableSkills.contains(where: { $0.id == requestedSkill.id })
            ? requestedSkill : skillByID("chat", skills: skills)
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

        // 用量只代表当前这一次请求。每次真正发起前立即清零。
        resetCurrentRequestUsage()

        // 组装上下文：世界书激活（关键词触发 + Agent 知识库挂载，去重）+ 前文（按预算截断）
        let hasSelectedNovel = currentNovelID != nil
        let chaptersText = hasSelectedNovel ? chapters.map { String($0.content.prefix(ContextLimits.chapterMax)) }.joined() : ""
        let historyText = messages.suffix(8).map { $0.content }.joined()
        let scanText = text + "\n" + chaptersText + "\n" + historyText
        var ctxEntries = hasSelectedNovel ? activateLorebook(entries: entries, scanText: scanText) : []
        if let ids = currentAgent.loreEntryIDs {
            for e in entries where ids.contains(e.id) && !ctxEntries.contains(where: { $0.id == e.id }) {
                ctxEntries.append(e)
            }
        }
        let agent = currentAgent
        let fixedSkill = agent.fixedSkillID.flatMap { id in skills.first { $0.id == id && $0.id != "chat" } }
        let skillIndex = indexedSkills(for: agent, skills: skills)
        let contextChapterCount = max(skill.chapters, fixedSkill?.chapters ?? 0)
        let prev = hasSelectedNovel ? DB.shared.lastChapters(novelID: nid, count: contextChapterCount) : []
        let novel = novels.first { $0.id == nid }
            ?? Novel(id: GLOBAL_CHAT_NOVEL_ID, title: "", desc: "", outline: "", createdAt: Date(), updatedAt: Date())

        let targetText: String
        if skill.needsText || fixedSkill?.needsText == true {
            targetText = selectedChapterID.flatMap { cid in chapters.first { $0.id == cid }?.content } ?? ""
        } else {
            targetText = ""
        }

        let ctx = GenContext(novel: novel, chapters: prev, entries: ctxEntries,
                             history: messages,
                             userText: text, targetText: targetText, skill: skill,
                             fixedSkill: fixedSkill, indexedSkills: skillIndex)
        let useMaxTokens = agent.maxTokens ?? config.maxTokens
        // 梯形加载：初始只注入根目录，逐层展开，到叶子后才注入少量详细 Schema。
        // Agent.tools 仍按最终工具名过滤；没有权限的目录分支不会出现。
        let allowedToolNames = agent.tools.map(Set.init)
        let rootToolNodes = ToolGroups.visibleNodes(parentID: nil, allowedNames: allowedToolNames)
        let skillLoaderTool = skillIndex.isEmpty ? nil : Self.writingTools.first { definition in
            (definition["function"] as? [String: Any])?["name"] as? String == "get_skill"
        }
        let workspaceToolRoots = config.enableTools ? ToolGroups.loaderDefinitions(for: rootToolNodes) : []
        // Skill 调取独立于工作区工具总开关；关闭写作工具后，Agent 仍可按索引读取 Skill。
        var tools: [[String: Any]]? = config.provider != "anthropic"
            ? workspaceToolRoots + [skillLoaderTool].compactMap { $0 }
            : nil
        var loadedToolLeaves: [ToolGroups.Node] = []
        var toolDefinitionTokens = Self.estimatedToolDefinitionTokens(tools)
        // “输入窗口”和“输出上限”是两个独立的用户配置，不互相扣减。
        let inputBudget = max(1024, config.contextWindow)
        let reservedInputTokens = estimateTokens(agent.systemPrompt) + toolDefinitionTokens
        let requiresCompression = config.enableContextCompression
            && Self.estimatedUncompressedInputTokens(ctx: ctx,
                                                     reservedInputTokens: reservedInputTokens) >= Int(Double(inputBudget) * 0.80)
        if requiresCompression && !compressionIndicatorPrepared {
            isCompressingContext = true
            Task { @MainActor [weak self] in
                // 留出一帧让“上下文压缩中”先显示出来；压缩期间输入区保持锁定。
                try? await Task.sleep(nanoseconds: 30_000_000)
                self?.performSend(text: text, requestedSkillID: skill.id,
                                  compressionIndicatorPrepared: true)
            }
            return
        }
        let req = buildRequest(
            ctx: ctx,
            tokenBudget: config.enableContextCompression ? inputBudget : nil,
            compressionLevel: config.enableContextCompression ? config.contextCompressionLevel : nil,
            compressionTargetRetention: config.contextCompressionLevel == .custom
                ? config.contextCompressionCustomRatio : nil,
            reservedInputTokens: reservedInputTokens
        )
        if compressionIndicatorPrepared { isCompressingContext = false }
        lastPlan = req.plan
        // 输入在上下文规划（含可能发生的压缩）完成后锁定；生成及工具轮次不再刷新。
        currentRequestInputTokens = req.plan.totalTokens
        if req.plan.requestExceedsInputBudget {
            if skill.id == "chat" { draft = text }
            toast("当前输入、最近对话或受保护设定已超过输入窗口，请增大窗口或精简内容")
            return
        }

        // 预算检查通过后才把用户消息入库，避免失败请求不断堆积进下一轮历史。
        draft = ""
        activeRequestSkillID = skill.id
        messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                             role: "user", content: text, skill: skill.id))

        // 最终系统提示词 = Agent 人格 + 上下文
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
        // 占位 assistant 消息
        streaming = true
        streamingText = ""
        streamingReasoningDuration = 0
        streamingToolName = nil
        streamingReasoningStartedAt = nil
        streamingReasoningFinished = false

        streamTask = Task { [weak self] in
            guard let self else { return }
            var msgs = req.messages
            // 根域 → 子域 → 操作叶子 → 实际调用，跨域任务再预留数轮。
            let maxRounds = (tools?.isEmpty == false) ? 10 : 1
            var cfg = self.config
            cfg.model = useModel
            do {
                for round in 0..<maxRounds {
                    let (outText, toolCalls) = try await LLM.streamChat(
                        config: cfg, system: system, messages: msgs,
                        temperature: useTemperature, topP: useTopP, maxTokens: useMaxTokens,
                        tools: tools,
                        onToolDelta: { fragment in
                            self.recordCurrentRequestToolOutput(fragment)
                        },
                        onToolName: { name in
                            self.streamingToolName = name
                        }
                    ) { delta in
                        self.streamingText += delta
                        self.refreshStreamingReasoningState()
                        self.recordCurrentRequestTextOutput(delta)
                    }
                    if toolCalls.isEmpty {
                        break
                    }
                    // 记录 assistant 的调用，执行工具，结果回填
                    msgs.append(ChatMsg(role: "assistant",
                                        content: ModelOutputParser.parse(outText).response,
                                        toolCalls: toolCalls))
                    for tc in toolCalls {
                        self.streamingToolName = tc.name
                        let result: String
                        if let node = ToolGroups.node(forLoader: tc.name),
                           !ToolGroups.descendantToolNames(of: node.id).isDisjoint(with: allowedToolNames ?? ToolGroups.descendantToolNames(of: node.id)) {
                            if node.isLeaf {
                                loadedToolLeaves.removeAll { $0.id == node.id }
                                loadedToolLeaves.append(node)
                                if loadedToolLeaves.count > 4 { loadedToolLeaves.removeFirst() }
                            }
                            let nextParent = node.isLeaf ? node.parentID : node.id
                            let navigationNodes = ToolGroups.visibleNodes(parentID: nextParent, allowedNames: allowedToolNames)
                            let navigation = ToolGroups.loaderDefinitions(for: rootToolNodes)
                                + ToolGroups.loaderDefinitions(for: navigationNodes)
                            let details = loadedToolLeaves.flatMap {
                                ToolGroups.detailedDefinitions(for: $0, allDefinitions: Self.writingTools,
                                                               allowedNames: allowedToolNames)
                            }
                            // loader 名和详细工具名天然不同；按 function name 去重以防根/导航重合。
                            var seen = Set<String>()
                            tools = (navigation + details + [skillLoaderTool].compactMap { $0 }).filter { definition in
                                guard let function = definition["function"] as? [String: Any],
                                      let name = function["name"] as? String else { return false }
                                return seen.insert(name).inserted
                            }
                            toolDefinitionTokens = Self.estimatedToolDefinitionTokens(tools)
                            let path = ToolGroups.breadcrumb(for: node).map(\.label).joined(separator: " → ")
                            result = node.isLeaf
                                ? "已加载工具路径：\(path)。下一步请直接调用本叶子的 \(details.count) 个详细工具。"
                                : "已展开工具路径：\(path)。下一步请选择更具体的操作子域。"
                        } else if let waited = await self.executeConversationWaitTool(tc) {
                            result = waited
                        } else if let loadedSkill = Self.indexedSkillResult(tc, skills: skillIndex) {
                            result = loadedSkill
                        } else {
                            result = self.executeConversationIsolatedTool(tc, conversationID: cid, novelID: nid)
                        }
                        msgs.append(ChatMsg(role: "tool", content: result, toolCallID: tc.id))
                    }
                    self.streamingToolName = nil
                    if round < maxRounds - 1 {
                        let fittedRound = Self.fitToolRoundMessages(
                            msgs,
                            system: system,
                            toolDefinitionTokens: toolDefinitionTokens,
                            inputBudget: inputBudget,
                            query: text,
                            compressionLevel: self.config.contextCompressionLevel
                        )
                        msgs = fittedRound.messages
                        if !fittedRound.fits {
                            self.streamingText += "\n\n（工具结果超过输入窗口，已停止继续调用模型；请增大输入窗口或缩小读取范围。）"
                            break
                        }
                    } else {
                        self.streamingText += "\n\n（已到达工具调用轮次上限）"
                    }
                }
                let parsed = ModelOutputParser.parse(self.streamingText)
                let reasoningDuration = self.finalStreamingReasoningDuration(hasReasoning: !parsed.reasoning.isEmpty)
                self.streaming = false
                self.streamingText = ""
                self.streamingToolName = nil
                self.activeRequestSkillID = "chat"
                // 工具可能删除当前作品；作品已不存在时不再写入一条孤立消息。
                if (!parsed.response.isEmpty || !parsed.reasoning.isEmpty),
                   nid == GLOBAL_CHAT_NOVEL_ID || self.novels.contains(where: { $0.id == nid }) {
                    self.messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                              role: "assistant", content: parsed.response, skill: skill.id,
                                                              reasoning: parsed.reasoning,
                                                              reasoningDuration: reasoningDuration))
                }
            } catch {
                let msg = error.localizedDescription
                self.streaming = false
                self.streamingText = ""
                self.streamingToolName = nil
                self.activeRequestSkillID = "chat"
                if nid == GLOBAL_CHAT_NOVEL_ID || self.novels.contains(where: { $0.id == nid }) {
                    self.messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                              role: "assistant", content: "❌ \(msg)", skill: skill.id))
                }
                self.toast(msg.components(separatedBy: "\n").first ?? "模型请求失败")
            }
            self.releaseConversationResources(cid)
        }
    }

    /// 仅用于判断是否会跨过压缩触发线，不生成压缩结果，避免界面显示虚假的压缩状态。
    private static func estimatedUncompressedInputTokens(ctx: GenContext,
                                                         reservedInputTokens: Int) -> Int {
        let meta = ctx.novel.metadata
        let bookText = [ctx.novel.title, ctx.novel.desc, ctx.novel.outline,
                        meta.authorIntent, meta.currentFocus, meta.storyFrame, meta.bookRules]
            .joined(separator: "\n")
        let chapterText = ctx.chapters
            .map { $0.title + "\n" + $0.content }
            .joined(separator: "\n")
        let entryText = ctx.entries
            .map { $0.title + "\n" + $0.keywords + "\n" + $0.content }
            .joined(separator: "\n")
        let historyText = ctx.history.map(\.content).joined(separator: "\n")
        let indexText = ctx.indexedSkills
            .map { "\($0.id) \($0.name) \($0.category.rawValue) \($0.desc)" }
            .joined(separator: "\n")
        let requestText = [ctx.fixedSkill?.system ?? "", ctx.skill.system, indexText,
                           ctx.userText, ctx.targetText].joined(separator: "\n")
        let source = [bookText, chapterText, entryText, historyText, requestText].joined(separator: "\n")
        return estimateTokens(source) + max(0, reservedInputTokens)
    }

    /// get_skill 只能读取本轮提供给 Agent 的索引，防止绕过 Agent 的 Skill 范围。
    static func indexedSkillResult(_ call: ToolCall, skills: [Skill]) -> String? {
        guard call.name == "get_skill" else { return nil }
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        guard let id = args["skill_id"] as? String,
              let skill = skills.first(where: { $0.id == id }) else {
            return "错误：该 Skill 不在当前 Agent 的按需索引中"
        }
        return """
        【已调取 Skill：\(skill.name)】
        skill_id: \(skill.id)
        分类：\(skill.category.rawValue)
        说明：\(skill.desc)

        \(skill.system)
        """
    }

    // MARK: - 当前单次请求 Token 用量

    private func resetCurrentRequestUsage() {
        currentRequestInputTokens = 0
        currentRequestOutputTokens = 0
        currentRequestTextOutputTokens = 0
        currentRequestToolOutputTokens = 0
        currentRequestOutputCharacters = 0
        currentRequestOutputLines = 0
        currentRequestTextOutput = ""
        currentRequestToolOutput = ""
    }

    private func recordCurrentRequestTextOutput(_ delta: String) {
        guard !delta.isEmpty else { return }
        currentRequestTextOutput += delta
        currentRequestTextOutputTokens = estimateTokens(currentRequestTextOutput)
        refreshCurrentRequestOutputMetrics()
    }

    private func refreshStreamingReasoningState() {
        let parsed = ModelOutputParser.parse(streamingText)
        guard !parsed.reasoning.isEmpty else { return }
        if streamingReasoningStartedAt == nil { streamingReasoningStartedAt = Date() }
        if !streamingReasoningFinished, let startedAt = streamingReasoningStartedAt {
            streamingReasoningDuration = Date().timeIntervalSince(startedAt)
            if !parsed.isThinking { streamingReasoningFinished = true }
        }
    }

    private func finalStreamingReasoningDuration(hasReasoning: Bool) -> Double {
        guard hasReasoning else { return 0 }
        if !streamingReasoningFinished, let startedAt = streamingReasoningStartedAt {
            streamingReasoningDuration = Date().timeIntervalSince(startedAt)
        }
        return max(0.1, streamingReasoningDuration)
    }

    /// 模型生成的工具名和 JSON 参数也属于模型输出；章节正文、设定和书籍修改内容
    /// 都在这些参数中，因此必须和对话文本一起计入本轮输出。
    private func recordCurrentRequestToolOutput(_ fragment: String) {
        guard !fragment.isEmpty else { return }
        currentRequestToolOutput += fragment
        currentRequestToolOutputTokens = estimateTokens(currentRequestToolOutput)
        refreshCurrentRequestOutputMetrics()
    }

    private func refreshCurrentRequestOutputMetrics() {
        currentRequestOutputTokens = currentRequestTextOutputTokens + currentRequestToolOutputTokens
        let combined = currentRequestTextOutput + currentRequestToolOutput
        currentRequestOutputCharacters = combined.count
        currentRequestOutputLines = combined.isEmpty
            ? 0
            : combined.reduce(1) { count, character in character == "\n" ? count + 1 : count }
    }

    struct FittedToolRound {
        let messages: [ChatMsg]
        let totalTokens: Int
        let fits: Bool
    }

    static func estimatedToolDefinitionTokens(_ tools: [[String: Any]]?) -> Int {
        guard let tools, !tools.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: tools),
              let json = String(data: data, encoding: .utf8) else { return 0 }
        return estimateTokens(json)
    }

    private static func estimatedMessageTokens(_ message: ChatMsg) -> Int {
        var total = estimateTokens(message.content) + 8
        if let calls = message.toolCalls {
            for call in calls {
                total += estimateTokens(call.name) + estimateTokens(call.arguments) + 8
            }
        }
        return total
    }

    /// 工具结果进入下一轮模型调用前重新分配输入预算。系统、普通对话和工具调用参数
    /// 保持原样，只压缩工具返回正文；若固定内容本身已超限，则停止下一轮请求。
    static func fitToolRoundMessages(
        _ messages: [ChatMsg],
        system: String,
        toolDefinitionTokens: Int,
        inputBudget: Int,
        query: String,
        compressionLevel: ContextCompressionLevel
    ) -> FittedToolRound {
        var fitted = messages
        let safeBudget = max(1, Int(Double(inputBudget) * 0.96))
        let toolIndices = fitted.indices.filter { fitted[$0].role == "tool" }
        let fixedTokens = estimateTokens(system) + toolDefinitionTokens
            + fitted.indices.filter { fitted[$0].role != "tool" }.reduce(0) {
                $0 + estimatedMessageTokens(fitted[$1])
            }
        let availableForToolContent = max(0, safeBudget - fixedTokens - toolIndices.count * 8)
        let perToolBudget = toolIndices.isEmpty ? 0 : max(1, availableForToolContent / toolIndices.count)

        for index in toolIndices where estimateTokens(fitted[index].content) > perToolBudget {
            let compressed = NovelContextCompressor.compress(
                fitted[index].content,
                query: query,
                maxTokens: perToolBudget,
                level: compressionLevel
            ).text
            fitted[index].content = truncateToEstimatedTokens(compressed, maxTokens: perToolBudget)
        }

        let total = estimateTokens(system) + toolDefinitionTokens
            + fitted.reduce(0) { $0 + estimatedMessageTokens($1) }
        return FittedToolRound(messages: fitted, totalTokens: total, fits: total <= safeBudget)
    }

    private static func truncateToEstimatedTokens(_ text: String, maxTokens: Int) -> String {
        guard maxTokens > 0 else { return "" }
        guard estimateTokens(text) > maxTokens else { return text }
        var low = 0
        var high = text.count
        while low < high {
            let middle = (low + high + 1) / 2
            if estimateTokens(String(text.prefix(middle))) <= maxTokens {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return String(text.prefix(low))
    }

    // MARK: - 写作工具（Tool Use）
    /// 给模型的作品工具：查询资料，以及创建、编写、修改、删除书籍和章节。
    /// 工具结果会回填给模型继续生成，界面以「🔧」事件行展示。

    static let writingTools: [[String: Any]] = [
        ["type": "function", "function": [
            "name": "search_database",
            "description": "在指定书籍中全文搜索设定库与章节内容；book_id 省略时使用当前书籍",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "query": ["type": "string", "description": "搜索关键词"]],
                           "required": ["query"]]]],
        ["type": "function", "function": [
            "name": "read_chapter",
            "description": "读取指定书籍的章节正文（按章节号，从 1 开始）；book_id 省略时使用当前书籍",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "number": ["type": "integer", "description": "章节号"],
                            "offset": ["type": "integer", "description": "正文字符偏移，默认 0"],
                            "limit": ["type": "integer", "description": "本页字符数，默认 6000，最大 20000"]],
                           "required": ["number"]]]],
        ["type": "function", "function": [
            "name": "list_chapters",
            "description": "列出指定书籍所有章节的编号、标题和正文字符数；book_id 省略时使用当前书籍",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"]]]]],
        ["type": "function", "function": [
            "name": "get_outline",
            "description": "分页读取指定书籍的故事大纲；book_id 省略时使用当前书籍",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "offset": ["type": "integer", "description": "字符偏移，默认 0"],
                "limit": ["type": "integer", "description": "本页字符数，默认 4000，最大 20000"]]]]],
        ["type": "function", "function": [
            "name": "list_books",
            "description": "列出书库中所有书籍及其 ID、章节数和总正文字符数",
            "parameters": ["type": "object", "properties": [:]]]],
        ["type": "function", "function": [
            "name": "get_book",
            "description": "读取一本书的书名、简介、大纲和主要元数据；book_id 省略时使用当前书籍",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"]]]]],
        ["type": "function", "function": [
            "name": "get_story_stats",
            "description": "统计指定书籍的章节数、正文字符数、设定条目数和各章篇幅；book_id 省略时使用当前书籍",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"]]]]],
        ["type": "function", "function": [
            "name": "create_book",
            "description": "创建一本新书。创建后返回 book_id，但不会切换用户当前正在查看的书；后续可把 book_id 传给章节工具",
            "parameters": ["type": "object",
                           "properties": [
                            "title": ["type": "string", "description": "书名"],
                            "description": ["type": "string", "description": "书籍简介"],
                            "outline": ["type": "string", "description": "故事大纲"],
                            "authors": ["type": "array", "items": ["type": "string"]], "pen_name": ["type": "string"],
                            "genres": ["type": "array", "items": ["type": "string"]], "tags": ["type": "array", "items": ["type": "string"]],
                            "language": ["type": "string"], "platform": ["type": "string"], "status": ["type": "string"],
                            "author_intent": ["type": "string"], "current_focus": ["type": "string"],
                            "story_frame": ["type": "string"], "book_rules": ["type": "string"]],
                           "required": ["title"]]]],
        ["type": "function", "function": [
            "name": "update_book",
            "description": "修改书籍的书名、简介或大纲；book_id 省略时修改当前书籍",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "title": ["type": "string", "description": "新书名"],
                            "description": ["type": "string", "description": "新简介"],
                            "outline": ["type": "string", "description": "新故事大纲"],
                            "subtitle": ["type": "string"], "authors": ["type": "array", "items": ["type": "string"]],
                            "pen_name": ["type": "string"], "language": ["type": "string"],
                            "genres": ["type": "array", "items": ["type": "string"]], "tags": ["type": "array", "items": ["type": "string"]],
                            "status": ["type": "string"], "platform": ["type": "string"],
                            "target_chapters": ["type": "integer"], "chapter_word_count": ["type": "integer"],
                            "review_mode": ["type": "string"], "style_library_id": ["type": "string"], "style_strength": ["type": "number"],
                            "series_name": ["type": "string"], "series_number": ["type": "string"], "logline": ["type": "string"],
                            "author_intent": ["type": "string"], "current_focus": ["type": "string"],
                            "story_frame": ["type": "string"], "book_rules": ["type": "string"],
                            "themes": ["type": "array", "items": ["type": "string"]],
                            "target_audience": ["type": "string"], "content_rating": ["type": "string"],
                            "point_of_view": ["type": "string"], "tense": ["type": "string"], "target_word_count": ["type": "integer"],
                            "isbn": ["type": "string"], "publisher": ["type": "string"], "publication_date": ["type": "string"],
                            "rights": ["type": "string"], "source": ["type": "string"],
                            "custom_metadata": ["type": "object", "additionalProperties": ["type": "string"]]]]]],
        ["type": "function", "function": [
            "name": "delete_book",
            "description": "永久删除一本书及其章节、设定和会话。必须提供当前准确书名用于防误删",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "expected_title": ["type": "string", "description": "必须与待删除书名完全一致"]],
                           "required": ["expected_title"]]]],
        ["type": "function", "function": [
            "name": "create_chapter",
            "description": "在指定书籍末尾新建章节并写入正文；book_id 省略时使用当前书籍",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "title": ["type": "string", "description": "章节标题"],
                            "content": ["type": "string", "description": "章节正文"]],
                           "required": ["title", "content"]]]],
        ["type": "function", "function": [
            "name": "update_chapter",
            "description": "修改指定章节标题或正文。正文可整篇替换或追加；book_id 省略时使用当前书籍",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "number": ["type": "integer", "description": "章节号"],
                            "title": ["type": "string", "description": "新章节标题；省略则不改"],
                            "content": ["type": "string", "description": "要写入或追加的正文；省略则不改"],
                            "content_mode": ["type": "string", "enum": ["replace", "append"], "description": "正文写入方式，默认 replace"]],
                           "required": ["number"]]]],
        ["type": "function", "function": [
            "name": "replace_chapter_text",
            "description": "精准替换章节正文中的一段原文；仅当原文恰好出现一次时执行，适合局部修订",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "number": ["type": "integer", "description": "章节号"],
                            "old_text": ["type": "string", "description": "需要被替换的原文"],
                            "new_text": ["type": "string", "description": "替换后的文字"]],
                           "required": ["number", "old_text", "new_text"]]]],
        ["type": "function", "function": [
            "name": "delete_chapter",
            "description": "永久删除指定章节。必须提供当前准确章节标题用于防误删",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "number": ["type": "integer", "description": "章节号"],
                            "expected_title": ["type": "string", "description": "必须与待删除章节标题完全一致"]],
                           "required": ["number", "expected_title"]]]],
        ["type": "function", "function": [
            "name": "batch_create_chapters",
            "description": "按给定顺序批量创建多个章节，适合一次写入分卷或连续章节",
            "parameters": ["type": "object",
                           "properties": [
                            "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                            "chapters": ["type": "array", "description": "章节数组",
                                         "items": ["type": "object", "properties": [
                                            "title": ["type": "string"], "content": ["type": "string"]],
                                            "required": ["title", "content"]]]],
                           "required": ["chapters"]]]],
        ["type": "function", "function": [
            "name": "move_chapter",
            "description": "把章节移动到新的章节位置，并自动重排章节号",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "number": ["type": "integer", "description": "当前章节号"],
                "new_position": ["type": "integer", "description": "目标章节位置，从 1 开始"]],
                "required": ["number", "new_position"]]]],
        ["type": "function", "function": [
            "name": "duplicate_chapter",
            "description": "复制指定章节到书籍末尾，可指定副本标题",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "number": ["type": "integer", "description": "要复制的章节号"],
                "title": ["type": "string", "description": "副本标题；省略时在原题后加“副本”"]],
                "required": ["number"]]]],
        ["type": "function", "function": [
            "name": "split_chapter",
            "description": "在正文中唯一的分割文本处拆分章节；原章节保留前半段，新章节紧随其后",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "number": ["type": "integer", "description": "待拆分章节号"],
                "split_text": ["type": "string", "description": "唯一的分割文本；该文本归入新章节开头"],
                "second_title": ["type": "string", "description": "新章节标题"]],
                "required": ["number", "split_text", "second_title"]]]],
        ["type": "function", "function": [
            "name": "merge_chapters",
            "description": "合并两个相邻章节：正文并入前一章并删除后一章；准确标题用于防误操作",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "first_number": ["type": "integer"], "second_number": ["type": "integer"],
                "expected_first_title": ["type": "string"], "expected_second_title": ["type": "string"],
                "separator": ["type": "string", "description": "合并时正文间隔，默认两个换行"]],
                "required": ["first_number", "second_number", "expected_first_title", "expected_second_title"]]]],
        ["type": "function", "function": [
            "name": "list_lore_entries",
            "description": "列出指定书籍的设定库条目，可按类型筛选",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "type": ["type": "string", "description": "可选类型筛选，如 character/location/faction/world/note"]]]]],
        ["type": "function", "function": [
            "name": "read_lore_entry",
            "description": "按 entry_id 读取一条完整设定",
            "parameters": ["type": "object", "properties": [
                "entry_id": ["type": "string", "description": "设定条目 UUID"]], "required": ["entry_id"]]]],
        ["type": "function", "function": [
            "name": "create_lore_entry",
            "description": "创建人物、地点、势力、物品、世界观、历史、灵感或笔记等设定条目",
            "parameters": ["type": "object", "properties": [
                "book_id": ["type": "string", "description": "书籍 UUID；省略时使用当前书籍"],
                "type": ["type": "string", "enum": ["character", "location", "faction", "item", "world", "history", "idea", "note", "other"]],
                "title": ["type": "string"], "content": ["type": "string"],
                "keywords": ["type": "string", "description": "逗号分隔的触发关键词"],
                "pinned": ["type": "boolean", "description": "是否固定注入上下文"]],
                "required": ["type", "title", "content"]]]],
        ["type": "function", "function": [
            "name": "update_lore_entry",
            "description": "修改指定设定条目的类型、标题、内容、关键词或固定状态",
            "parameters": ["type": "object", "properties": [
                "entry_id": ["type": "string", "description": "设定条目 UUID"],
                "type": ["type": "string", "enum": ["character", "location", "faction", "item", "world", "history", "idea", "note", "other"]],
                "title": ["type": "string"], "content": ["type": "string"],
                "keywords": ["type": "string"], "pinned": ["type": "boolean"]],
                "required": ["entry_id"]]]],
        ["type": "function", "function": [
            "name": "delete_lore_entry",
            "description": "永久删除指定设定条目；必须提供当前准确标题用于防误删",
            "parameters": ["type": "object", "properties": [
                "entry_id": ["type": "string", "description": "设定条目 UUID"],
                "expected_title": ["type": "string", "description": "必须与条目标题完全一致"]],
                "required": ["entry_id", "expected_title"]]]],
    ] + WorkspaceTools.definitions + GovernanceTools.definitions

    static func executeTool(_ tc: ToolCall, app: AppState) -> String {
        if let governed = GovernanceTools.execute(tc, app: app) { return governed }
        let args = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) as? [String: Any] ?? [:]
        switch tc.name {
        case "search_database":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let q = args["query"] as? String, !q.isEmpty else { return "错误：缺少 query 参数" }
            let r = DB.shared.search(q, novelID: novel.id)
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
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let n = args["number"] as? Int else { return "错误：缺少 number 参数" }
            let chapters = DB.shared.chapters(novelID: novel.id)
            let ch = chapters.first { $0.no == n }
            guard let ch else { return "错误：不存在第 \(n) 章（当前共 \(chapters.count) 章）" }
            let offset = max(0, args["offset"] as? Int ?? 0)
            let limit = max(1, min(args["limit"] as? Int ?? 6000, 20000))
            let page = String(ch.content.dropFirst(min(offset, ch.content.count)).prefix(limit))
            let next = offset + page.count < ch.content.count ? String(offset + page.count) : "none"
            return "第\(ch.no)章 \(ch.title)\n字符范围：\(offset)..<\(offset + page.count) / \(ch.content.count) · next_offset: \(next)\n\(page)"
        case "list_chapters":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            let chapters = DB.shared.chapters(novelID: novel.id)
            if chapters.isEmpty { return "暂无章节" }
            return chapters.map { "第\($0.no)章 \($0.title.isEmpty ? "（无标题）" : $0.title) · \($0.content.count) 字符" }.joined(separator: "\n")
        case "get_outline":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            let outline = novel.outline
            if outline.isEmpty { return "当前作品还没有大纲" }
            let offset = max(0, args["offset"] as? Int ?? 0), limit = max(1, min(args["limit"] as? Int ?? 4000, 20000))
            let page = String(outline.dropFirst(min(offset, outline.count)).prefix(limit))
            let next = offset + page.count < outline.count ? String(offset + page.count) : "none"
            return "大纲字符范围：\(offset)..<\(offset + page.count) / \(outline.count) · next_offset: \(next)\n\(page)"
        case "list_books":
            if app.novels.isEmpty { return "书库为空" }
            return app.novels.map { novel in
                let chapters = DB.shared.chapters(novelID: novel.id)
                return "《\(novel.title)》 · book_id: \(novel.id.uuidString) · \(chapters.count) 章 · \(chapters.reduce(0) { $0 + $1.content.count }) 字符"
            }.joined(separator: "\n")
        case "get_book":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            return toolBookDescription(novel)
        case "get_story_stats":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            let chapters = DB.shared.chapters(novelID: novel.id)
            let entries = DB.shared.entries(novelID: novel.id)
            var out = "《\(novel.title)》：\(chapters.count) 章，正文共 \(chapters.reduce(0) { $0 + $1.content.count }) 字符，设定 \(entries.count) 条"
            if !chapters.isEmpty { out += "\n" + chapters.map { "第\($0.no)章 \($0.content.count) 字符" }.joined(separator: "\n") }
            return out
        case "create_book":
            guard let title = args["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "错误：缺少 title 参数"
            }
            let desc = args["description"] as? String ?? ""
            let outline = args["outline"] as? String ?? ""
            var novel = DB.shared.createNovel(title: title, desc: desc)
            novel.outline = outline
            novel.metadata = updatedMetadata(novel.metadata, args: args)
            DB.shared.updateNovel(id: novel.id, outline: outline, metadata: novel.metadata)
            app.novels.insert(novel, at: 0)
            return "已创建书籍《\(novel.title)》\nbook_id: \(novel.id.uuidString)"
        case "update_book":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            let title = args["title"] as? String
            let desc = args["description"] as? String
            let outline = args["outline"] as? String
            let metadata = updatedMetadata(novel.metadata, args: args)
            guard title != nil || desc != nil || outline != nil || metadata != novel.metadata else { return "错误：没有提供任何要修改的字段" }
            DB.shared.updateNovel(id: novel.id, title: title, desc: desc, outline: outline, metadata: metadata)
            if let i = app.novels.firstIndex(where: { $0.id == novel.id }) {
                if let title { app.novels[i].title = title }
                if let desc { app.novels[i].desc = desc }
                if let outline { app.novels[i].outline = outline }
                app.novels[i].metadata = metadata
                app.novels[i].updatedAt = Date()
            }
            return "已更新书籍《\(title ?? novel.title)》"
        case "delete_book":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let expected = args["expected_title"] as? String, expected == novel.title else {
                return "错误：expected_title 与实际书名不一致，未删除"
            }
            if app.currentNovelID == novel.id { app.flushSave() }
            for conversationID in app.conversationRunStates.values.filter({ $0.novelID == novel.id }).map(\.conversationID) {
                if app.backgroundConversationTasks[conversationID] != nil { _ = app.cancelConversationRun(conversationID) }
            }
            DB.shared.deleteNovel(id: novel.id)
            app.novels.removeAll { $0.id == novel.id }
            if app.currentNovelID == novel.id {
                app.currentNovelID = nil
                if let next = app.novels.first { app.selectNovel(next.id) }
                else {
                    app.chapters = []; app.entries = []; app.conversations = []; app.messages = []
                    app.selectedChapterID = nil; app.currentConversationID = nil
                }
            }
            return "已删除书籍《\(novel.title)》及其全部关联内容"
        case "create_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let title = args["title"] as? String, let content = args["content"] as? String else {
                return "错误：缺少 title 或 content 参数"
            }
            let chapter = DB.shared.createChapter(novelID: novel.id, title: title, content: content)
            if app.currentNovelID == novel.id { app.chapters.append(chapter) }
            return "已创建第 \(chapter.no) 章《\(chapter.title)》\nchapter_id: \(chapter.id.uuidString)\n正文字符数：\(chapter.content.count)"
        case "update_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int,
                  let chapter = DB.shared.chapters(novelID: novel.id).first(where: { $0.no == number }) else {
                return "错误：找不到指定章节"
            }
            let title = args["title"] as? String
            var content: String?
            if let supplied = args["content"] as? String {
                let mode = args["content_mode"] as? String ?? "replace"
                guard mode == "replace" || mode == "append" else { return "错误：content_mode 只能是 replace 或 append" }
                content = mode == "append" ? chapter.content + supplied : supplied
            }
            guard title != nil || content != nil else { return "错误：没有提供任何要修改的字段" }
            DB.shared.updateChapter(id: chapter.id, title: title, content: content)
            refreshToolChapter(chapter.id, novelID: novel.id, app: app)
            return "已更新第 \(number) 章《\(title ?? chapter.title)》" + (content.map { "\n正文字符数：\($0.count)" } ?? "")
        case "replace_chapter_text":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int,
                  let chapter = DB.shared.chapters(novelID: novel.id).first(where: { $0.no == number }) else {
                return "错误：找不到指定章节"
            }
            guard let oldText = args["old_text"] as? String, !oldText.isEmpty,
                  let newText = args["new_text"] as? String else { return "错误：缺少 old_text 或 new_text 参数" }
            let matches = chapter.content.components(separatedBy: oldText).count - 1
            guard matches == 1 else {
                return matches == 0 ? "错误：章节中未找到指定原文，未修改" : "错误：指定原文出现 \(matches) 次，无法安全确定替换位置"
            }
            let updated = chapter.content.replacingOccurrences(of: oldText, with: newText)
            DB.shared.updateChapter(id: chapter.id, content: updated)
            refreshToolChapter(chapter.id, novelID: novel.id, app: app)
            return "已局部修改第 \(number) 章《\(chapter.title)》\n正文字符数：\(updated.count)"
        case "delete_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int,
                  let chapter = DB.shared.chapters(novelID: novel.id).first(where: { $0.no == number }) else {
                return "错误：找不到指定章节"
            }
            guard let expected = args["expected_title"] as? String, expected == chapter.title else {
                return "错误：expected_title 与实际章节标题不一致，未删除"
            }
            if app.selectedChapterID == chapter.id { app.flushSave() }
            DB.shared.deleteChapter(id: chapter.id)
            if app.currentNovelID == novel.id {
                app.chapters.removeAll { $0.id == chapter.id }
                if app.selectedChapterID == chapter.id { app.selectedChapterID = app.chapters.first?.id }
            }
            return "已删除第 \(number) 章《\(chapter.title)》"
        case "batch_create_chapters":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let inputs = args["chapters"] as? [[String: Any]], !inputs.isEmpty else {
                return "错误：chapters 必须是非空数组"
            }
            guard inputs.count <= 50 else { return "错误：单次最多创建 50 章" }
            guard inputs.allSatisfy({ $0["title"] is String && $0["content"] is String }) else {
                return "错误：每个章节都必须包含 title 和 content；没有创建任何章节"
            }
            var created: [Chapter] = []
            for input in inputs {
                let title = input["title"] as! String
                let content = input["content"] as! String
                created.append(DB.shared.createChapter(novelID: novel.id, title: title, content: content))
            }
            if app.currentNovelID == novel.id { app.chapters = DB.shared.chapters(novelID: novel.id) }
            return "已批量创建 \(created.count) 章：" + created.map { "第\($0.no)章《\($0.title)》" }.joined(separator: "、")
        case "move_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int, let newPosition = args["new_position"] as? Int else {
                return "错误：缺少 number 或 new_position 参数"
            }
            var chapters = DB.shared.chapters(novelID: novel.id)
            guard let index = chapters.firstIndex(where: { $0.no == number }) else { return "错误：找不到指定章节" }
            guard newPosition >= 1 && newPosition <= chapters.count else { return "错误：new_position 超出 1...\(chapters.count)" }
            let moving = chapters.remove(at: index)
            chapters.insert(moving, at: newPosition - 1)
            renumberToolChapters(chapters)
            if app.currentNovelID == novel.id { app.chapters = DB.shared.chapters(novelID: novel.id) }
            return "已将《\(moving.title)》从第 \(number) 章移动到第 \(newPosition) 章"
        case "duplicate_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int,
                  let source = DB.shared.chapters(novelID: novel.id).first(where: { $0.no == number }) else {
                return "错误：找不到指定章节"
            }
            let title = args["title"] as? String ?? source.title + "（副本）"
            let copy = DB.shared.createChapter(novelID: novel.id, title: title, content: source.content)
            if app.currentNovelID == novel.id { app.chapters.append(copy) }
            return "已复制为第 \(copy.no) 章《\(copy.title)》\nchapter_id: \(copy.id.uuidString)"
        case "split_chapter":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let number = args["number"] as? Int,
                  let source = DB.shared.chapters(novelID: novel.id).first(where: { $0.no == number }) else {
                return "错误：找不到指定章节"
            }
            guard let splitText = args["split_text"] as? String, !splitText.isEmpty,
                  let secondTitle = args["second_title"] as? String, !secondTitle.isEmpty else {
                return "错误：缺少 split_text 或 second_title 参数"
            }
            let parts = source.content.components(separatedBy: splitText)
            guard parts.count == 2 else {
                return parts.count == 1 ? "错误：正文中未找到分割文本" : "错误：分割文本出现多次，无法安全拆分"
            }
            DB.shared.updateChapter(id: source.id, content: parts[0])
            let second = DB.shared.createChapter(novelID: novel.id, title: secondTitle, content: splitText + parts[1])
            var reordered = DB.shared.chapters(novelID: novel.id)
            if let newIndex = reordered.firstIndex(where: { $0.id == second.id }) {
                let inserted = reordered.remove(at: newIndex)
                reordered.insert(inserted, at: min(number, reordered.count))
                renumberToolChapters(reordered)
            }
            if app.currentNovelID == novel.id { app.chapters = DB.shared.chapters(novelID: novel.id) }
            return "已将第 \(number) 章拆分为《\(source.title)》和《\(secondTitle)》"
        case "merge_chapters":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let firstNumber = args["first_number"] as? Int,
                  let secondNumber = args["second_number"] as? Int,
                  secondNumber == firstNumber + 1 else { return "错误：只能合并两个相邻章节" }
            let chapters = DB.shared.chapters(novelID: novel.id)
            guard let first = chapters.first(where: { $0.no == firstNumber }),
                  let second = chapters.first(where: { $0.no == secondNumber }) else { return "错误：找不到指定章节" }
            guard args["expected_first_title"] as? String == first.title,
                  args["expected_second_title"] as? String == second.title else {
                return "错误：章节标题校验失败，未合并"
            }
            let separator = args["separator"] as? String ?? "\n\n"
            DB.shared.updateChapter(id: first.id, content: first.content + separator + second.content)
            DB.shared.deleteChapter(id: second.id)
            renumberToolChapters(DB.shared.chapters(novelID: novel.id))
            if app.currentNovelID == novel.id {
                app.chapters = DB.shared.chapters(novelID: novel.id)
                if app.selectedChapterID == second.id { app.selectedChapterID = first.id }
            }
            return "已将第 \(secondNumber) 章《\(second.title)》合并入第 \(firstNumber) 章《\(first.title)》"
        case "list_lore_entries":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            let type = args["type"] as? String
            let entries = DB.shared.entries(novelID: novel.id).filter { type == nil || $0.type == type }
            if entries.isEmpty { return "没有符合条件的设定条目" }
            return entries.map {
                "【\(entryTypeLabel($0.type))】\($0.title) · entry_id: \($0.id.uuidString) · 关键词：\($0.keywords.isEmpty ? "无" : $0.keywords)\($0.pinned ? " · 已固定" : "")"
            }.joined(separator: "\n")
        case "read_lore_entry":
            guard let entry = toolEntry(args["entry_id"] as? String, app: app) else { return "错误：找不到指定设定条目" }
            return "【\(entryTypeLabel(entry.type))】\(entry.title)\nentry_id: \(entry.id.uuidString)\n关键词：\(entry.keywords.isEmpty ? "无" : entry.keywords)\n固定：\(entry.pinned ? "是" : "否")\n\n\(entry.content)"
        case "create_lore_entry":
            guard let novel = toolNovel(args, app: app) else { return "错误：找不到指定书籍" }
            guard let type = args["type"] as? String, ENTRY_TYPES.contains(where: { $0.id == type }),
                  let title = args["title"] as? String, !title.isEmpty,
                  let content = args["content"] as? String else { return "错误：type、title 或 content 参数无效" }
            let entry = DB.shared.createEntry(novelID: novel.id, type: type, title: title, content: content,
                                              keywords: args["keywords"] as? String ?? "",
                                              pinned: args["pinned"] as? Bool ?? false)
            if app.currentNovelID == novel.id { app.entries.insert(entry, at: 0) }
            return "已创建设定【\(entryTypeLabel(entry.type))】\(entry.title)\nentry_id: \(entry.id.uuidString)"
        case "update_lore_entry":
            guard let entry = toolEntry(args["entry_id"] as? String, app: app) else { return "错误：找不到指定设定条目" }
            let type = args["type"] as? String
            if let type, !ENTRY_TYPES.contains(where: { $0.id == type }) { return "错误：无效的设定类型" }
            let title = args["title"] as? String
            let content = args["content"] as? String
            let keywords = args["keywords"] as? String
            let pinned = args["pinned"] as? Bool
            guard type != nil || title != nil || content != nil || keywords != nil || pinned != nil else {
                return "错误：没有提供任何要修改的字段"
            }
            DB.shared.updateEntry(id: entry.id, type: type, title: title, content: content, keywords: keywords, pinned: pinned)
            if app.currentNovelID == entry.novelID { app.entries = DB.shared.entries(novelID: entry.novelID) }
            return "已更新设定《\(title ?? entry.title)》"
        case "delete_lore_entry":
            guard let entry = toolEntry(args["entry_id"] as? String, app: app) else { return "错误：找不到指定设定条目" }
            guard args["expected_title"] as? String == entry.title else { return "错误：expected_title 与实际标题不一致，未删除" }
            DB.shared.deleteEntry(id: entry.id)
            if app.currentNovelID == entry.novelID { app.entries.removeAll { $0.id == entry.id } }
            return "已删除设定【\(entryTypeLabel(entry.type))】\(entry.title)"
        default:
            return WorkspaceTools.execute(tc, app: app) ?? "未知工具：\(tc.name)"
        }
    }

    private static func toolNovel(_ args: [String: Any], app: AppState) -> Novel? {
        if let raw = args["book_id"] as? String, !raw.isEmpty {
            guard let id = UUID(uuidString: raw) else { return nil }
            return app.novels.first { $0.id == id }
        }
        guard let id = app.currentNovelID else { return nil }
        return app.novels.first { $0.id == id }
    }

    private static func refreshToolChapter(_ chapterID: UUID, novelID: UUID, app: AppState) {
        guard app.currentNovelID == novelID,
              let fresh = DB.shared.chapters(novelID: novelID).first(where: { $0.id == chapterID }),
              let index = app.chapters.firstIndex(where: { $0.id == chapterID }) else { return }
        app.chapters[index] = fresh
    }

    private static func renumberToolChapters(_ chapters: [Chapter]) {
        // 先写入临时负数，避免未来增加唯一索引时出现章节号冲突。
        for (index, chapter) in chapters.enumerated() { DB.shared.updateChapter(id: chapter.id, no: -(index + 1)) }
        for (index, chapter) in chapters.enumerated() { DB.shared.updateChapter(id: chapter.id, no: index + 1) }
    }

    private static func toolEntry(_ rawID: String?, app: AppState) -> Entry? {
        guard let rawID, let id = UUID(uuidString: rawID) else { return nil }
        for novel in app.novels {
            if let entry = DB.shared.entries(novelID: novel.id).first(where: { $0.id == id }) { return entry }
        }
        return nil
    }

    private static func toolBookDescription(_ novel: Novel) -> String {
        let m = novel.metadata
        let chapters = DB.shared.chapters(novelID: novel.id)
        return """
        《\(novel.title)》
        book_id: \(novel.id.uuidString)
        简介：\(novel.desc.isEmpty ? "无" : novel.desc)
        大纲：\(novel.outline.isEmpty ? "无" : novel.outline)
        作者：\(m.authors.isEmpty ? (m.penName.isEmpty ? "未设置" : m.penName) : m.authors.joined(separator: "、"))
        类型：\(m.genres.isEmpty ? "未设置" : m.genres.joined(separator: "、"))
        标签：\(m.tags.isEmpty ? "无" : m.tags.joined(separator: "、"))
        副标题：\(m.subtitle.isEmpty ? "无" : m.subtitle) · 笔名：\(m.penName.isEmpty ? "无" : m.penName)
        状态：\(m.status) · 平台：\(m.platform) · 语言：\(m.language)
        目标：\(m.targetChapters) 章 × \(m.chapterWordCount) 字 · 总字数 \(m.targetWordCount)
        作者意图：\(m.authorIntent.isEmpty ? "无" : m.authorIntent)
        当前聚焦：\(m.currentFocus.isEmpty ? "无" : m.currentFocus)
        故事框架：\(m.storyFrame.isEmpty ? "无" : m.storyFrame)
        本书规则：\(m.bookRules.isEmpty ? "无" : m.bookRules)
        系列：\(m.seriesName) \(m.seriesNumber) · 受众：\(m.targetAudience) · 分级：\(m.contentRating)
        视角：\(m.pointOfView) · 时态：\(m.tense) · 主题：\(m.themes.joined(separator: "、"))
        出版：ISBN \(m.isbn) · \(m.publisher) · \(m.publicationDate) · 权利 \(m.rights)
        规模：\(chapters.count) 章 · \(chapters.reduce(0) { $0 + $1.content.count }) 正文字符
        """
    }

    private static func updatedMetadata(_ original: BookMetadata, args: [String: Any]) -> BookMetadata {
        var m = original
        if let v = args["subtitle"] as? String { m.subtitle = v }; if let v = args["authors"] as? [String] { m.authors = v }
        if let v = args["pen_name"] as? String { m.penName = v }; if let v = args["language"] as? String { m.language = v }
        if let v = args["genres"] as? [String] { m.genres = v }; if let v = args["tags"] as? [String] { m.tags = v }
        if let v = args["status"] as? String { m.status = v }; if let v = args["platform"] as? String { m.platform = v }
        if let v = args["target_chapters"] as? Int { m.targetChapters = max(0, v) }
        if let v = args["chapter_word_count"] as? Int { m.chapterWordCount = max(0, v) }
        if let v = args["review_mode"] as? String { m.reviewMode = v }; if let v = args["style_library_id"] as? String { m.styleLibraryID = v }
        if let v = args["style_strength"] as? Double { m.styleStrength = max(0, min(v, 1)) }
        if let v = args["series_name"] as? String { m.seriesName = v }; if let v = args["series_number"] as? String { m.seriesNumber = v }
        if let v = args["logline"] as? String { m.logline = v }; if let v = args["author_intent"] as? String { m.authorIntent = v }
        if let v = args["current_focus"] as? String { m.currentFocus = v }; if let v = args["story_frame"] as? String { m.storyFrame = v }
        if let v = args["book_rules"] as? String { m.bookRules = v }; if let v = args["themes"] as? [String] { m.themes = v }
        if let v = args["target_audience"] as? String { m.targetAudience = v }; if let v = args["content_rating"] as? String { m.contentRating = v }
        if let v = args["point_of_view"] as? String { m.pointOfView = v }; if let v = args["tense"] as? String { m.tense = v }
        if let v = args["target_word_count"] as? Int { m.targetWordCount = max(0, v) }
        if let v = args["isbn"] as? String { m.isbn = v }; if let v = args["publisher"] as? String { m.publisher = v }
        if let v = args["publication_date"] as? String { m.publicationDate = v }; if let v = args["rights"] as? String { m.rights = v }
        if let v = args["source"] as? String { m.source = v }; if let v = args["custom_metadata"] as? [String: String] { m.custom = v }
        return m
    }

    func stopStreaming() {
        streamTask?.cancel()
        streaming = false
        let parsed = ModelOutputParser.parse(streamingText)
        let reasoningDuration = finalStreamingReasoningDuration(hasReasoning: !parsed.reasoning.isEmpty)
        streamingText = ""
        streamingToolName = nil
        if let cid = currentConversationID, !parsed.response.isEmpty || !parsed.reasoning.isEmpty {
            let nid = currentNovelID ?? GLOBAL_CHAT_NOVEL_ID
            messages.append(DB.shared.addMessage(novelID: nid, conversationID: cid,
                                                 role: "assistant",
                                                 content: parsed.response + (parsed.response.isEmpty ? "（已停止）" : "\n\n（已停止）"),
                                                 skill: activeRequestSkillID,
                                                 reasoning: parsed.reasoning,
                                                 reasoningDuration: reasoningDuration))
        }
        activeRequestSkillID = "chat"
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

    func chooseBackgroundMedia() {
        let panel = NSOpenPanel()
        panel.title = "选择背景图片或视频"
        panel.prompt = "设为背景"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let backgroundDir = AppPaths.dataDir.appendingPathComponent("Background", isDirectory: true)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension.lowercased()
        let destinationURL = backgroundDir.appendingPathComponent("custom-background.\(fileExtension)")

        do {
            try FileManager.default.createDirectory(at: backgroundDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let previousURL = URL(fileURLWithPath: config.backgroundMediaPath)
            if !config.backgroundMediaPath.isEmpty,
               previousURL.deletingLastPathComponent().standardizedFileURL == backgroundDir.standardizedFileURL,
               previousURL.standardizedFileURL != destinationURL.standardizedFileURL,
               FileManager.default.fileExists(atPath: previousURL.path) {
                try? FileManager.default.removeItem(at: previousURL)
            }

            config.backgroundMediaPath = destinationURL.path
            ConfigStore.save(config)
            toast("背景已更新")
        } catch {
            toast("背景设置失败：\(error.localizedDescription)")
        }
    }

    /// 用户主动选择文件后复制进 Imports；模型只能读取这里和应用自己的 Exports。
    func authorizeImportFile() {
        let panel = NSOpenPanel()
        panel.title = "授权文件给模型导入"
        panel.prompt = "复制到授权导入区"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .json]
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let directory = GovernanceTools.importsDirectory
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            destination = directory.appendingPathComponent("\(stem)-\(Int(Date().timeIntervalSince1970))\(ext.isEmpty ? "" : ".\(ext)")")
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            toast("已授权导入文件：\(destination.lastPathComponent)")
        } catch { toast("授权导入失败：\(error.localizedDescription)") }
    }

    func resetBackgroundMedia() {
        let selectedURL = URL(fileURLWithPath: config.backgroundMediaPath)
        let backgroundDir = AppPaths.dataDir.appendingPathComponent("Background", isDirectory: true)
        if !config.backgroundMediaPath.isEmpty,
           selectedURL.deletingLastPathComponent().standardizedFileURL == backgroundDir.standardizedFileURL {
            try? FileManager.default.removeItem(at: selectedURL)
        }
        config.backgroundMediaPath = ""
        ConfigStore.save(config)
        toast("已恢复默认背景")
    }

    func saveConfig() {
        ConfigStore.save(config)
        toast("设置已保存")
    }

    func testConnection() async {
        testResult = "测试中…"
        do {
            _ = try await LLM.testConnection(config: config)
            testResult = "✓ 连接成功，当前输出上限可用"
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
