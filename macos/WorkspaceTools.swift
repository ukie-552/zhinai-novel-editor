import Foundation

/// 覆盖作品正文之外的完整工作区：会话、Agent、Skills、写法向量库、交换文件和非敏感偏好。
/// API Key、任意文件读写及模型连接地址不向模型暴露。
@MainActor
enum WorkspaceTools {
    typealias JSON = [String: Any]

    static let catalog: [(id: String, label: String)] = [
        ("get_workspace_state", "读取完整工作区状态"),
        ("search_workspace", "跨全部书籍搜索"),
        ("list_conversations", "列出书籍会话"),
        ("read_conversation", "读取会话记录"),
        ("create_conversation", "创建会话"),
        ("rename_conversation", "重命名会话"),
        ("clear_conversation", "清空会话消息"),
        ("delete_conversation", "删除会话"),
        ("list_all_conversations", "跨书列出全部会话与状态"),
        ("send_message_to_conversation", "向其他会话派发后台任务"),
        ("get_conversation_run", "读取会话后台运行状态"),
        ("wait_conversations", "等待一个或多个会话"),
        ("cancel_conversation_run", "取消会话后台任务"),
        ("list_agents", "列出全部 Agent"),
        ("get_agent", "读取 Agent 配置"),
        ("create_agent", "创建 Agent"),
        ("update_agent", "修改 Agent"),
        ("duplicate_agent", "复制 Agent"),
        ("delete_agent", "删除自定义 Agent"),
        ("list_skills", "列出全部 Skills"),
        ("get_skill", "读取 Skill 指令"),
        ("create_skill", "创建 Markdown Skill"),
        ("update_skill", "修改 Markdown Skill"),
        ("delete_skill", "删除 Markdown Skill"),
        ("list_vector_libraries", "列出写法向量库"),
        ("get_vector_library", "读取向量库信息"),
        ("search_vector_library", "检索写法向量库"),
        ("list_vector_chapters", "列出向量库章节"),
        ("read_vector_chapter", "读取向量库章节"),
        ("update_vector_library", "修改向量库信息"),
        ("update_vector_chapter", "修改向量库章节"),
        ("delete_vector_library", "删除向量库"),
        ("import_vector_txt", "从 TXT 导入向量库"),
        ("get_style_profile", "提取写法画像"),
        ("export_book_file", "导出书籍交换文件"),
        ("import_book_file", "导入书籍交换文件"),
        ("list_exported_files", "列出已导出书籍文件"),
        ("delete_exported_file", "删除已导出文件"),
        ("get_workspace_preferences", "读取非敏感工作区偏好"),
        ("update_workspace_preferences", "修改非敏感工作区偏好"),
    ]

    private static func string(_ description: String = "") -> JSON {
        var out: JSON = ["type": "string"]
        if !description.isEmpty { out["description"] = description }
        return out
    }
    private static func integer(_ description: String = "") -> JSON {
        var out: JSON = ["type": "integer"]
        if !description.isEmpty { out["description"] = description }
        return out
    }
    private static func number(_ description: String = "") -> JSON {
        var out: JSON = ["type": "number"]
        if !description.isEmpty { out["description"] = description }
        return out
    }
    private static func boolean(_ description: String = "") -> JSON {
        var out: JSON = ["type": "boolean"]
        if !description.isEmpty { out["description"] = description }
        return out
    }
    private static func strings(_ description: String = "") -> JSON {
        ["type": "array", "description": description, "items": ["type": "string"]]
    }
    private static func definition(_ name: String, _ description: String,
                                   _ properties: JSON = [:], required: [String] = []) -> JSON {
        var parameters: JSON = ["type": "object", "properties": properties]
        if !required.isEmpty { parameters["required"] = required }
        return ["type": "function", "function": [
            "name": name, "description": description, "parameters": parameters
        ]]
    }

    static let definitions: [[String: Any]] = [
        definition("get_workspace_state", "读取当前工作区各数据域数量、当前选择和存储位置；不返回密钥"),
        definition("search_workspace", "跨书库搜索全部书籍的书名、简介、大纲、章节和设定", [
            "query": string("搜索关键词")], required: ["query"]),

        definition("list_conversations", "列出指定书籍的全部会话", ["book_id": string("省略时使用当前书籍")]),
        definition("read_conversation", "读取指定会话的消息记录", [
            "conversation_id": string("会话 UUID"), "offset": integer("消息偏移，默认 0"),
            "limit": integer("最多读取条数，默认 50，最大 200")], required: ["conversation_id"]),
        definition("create_conversation", "在指定书籍中创建一个会话", [
            "book_id": string("省略时使用当前书籍"), "title": string("会话标题")], required: ["title"]),
        definition("rename_conversation", "重命名会话", [
            "conversation_id": string(), "title": string("新标题")], required: ["conversation_id", "title"]),
        definition("clear_conversation", "清空会话内全部消息；准确标题用于防误操作", [
            "conversation_id": string(), "expected_title": string()], required: ["conversation_id", "expected_title"]),
        definition("delete_conversation", "删除会话及其全部消息；准确标题用于防误删", [
            "conversation_id": string(), "expected_title": string()], required: ["conversation_id", "expected_title"]),
        definition("list_all_conversations", "跨全部书籍列出会话、所属书籍和后台运行状态"),
        definition("send_message_to_conversation", "向指定会话派发独立后台 Agent 任务；切换页面不会停止", [
            "conversation_id": string(), "prompt": string("要交给目标会话的任务"),
            "agent_id": string("可选 Agent UUID"), "skill_id": string("可选 Skill ID，默认 chat")],
            required: ["conversation_id", "prompt"]),
        definition("get_conversation_run", "读取指定会话的后台任务状态和最近输出", [
            "conversation_ids": strings("会话 UUID 数组；省略返回全部任务")]),
        definition("wait_conversations", "等待指定会话完成或超时，最长 30 秒", [
            "conversation_ids": strings("要等待的会话 UUID"), "timeout_seconds": number("0 到 30")], required: ["conversation_ids"]),
        definition("cancel_conversation_run", "取消指定会话正在运行的后台任务", [
            "conversation_id": string()], required: ["conversation_id"]),

        definition("list_agents", "列出全部内置及自定义 Agent"),
        definition("get_agent", "读取 Agent 的完整非敏感配置", ["agent_id": string()], required: ["agent_id"]),
        definition("create_agent", "创建自定义 Agent", agentProperties(includeID: false), required: ["name", "system_prompt"]),
        definition("update_agent", "修改自定义 Agent；省略字段保持不变，内置 Agent 只读", agentProperties(includeID: true), required: ["agent_id"]),
        definition("duplicate_agent", "复制任意 Agent 为新的自定义 Agent", [
            "agent_id": string(), "name": string("副本名称；省略时自动添加“副本”")], required: ["agent_id"]),
        definition("delete_agent", "删除自定义 Agent；准确名称用于防误删，内置 Agent 不可删除", [
            "agent_id": string(), "expected_name": string()], required: ["agent_id", "expected_name"]),

        definition("list_skills", "列出全部内置与 Markdown Skills"),
        definition("get_skill", "读取 Skill 元数据与完整指令正文", ["skill_id": string()], required: ["skill_id"]),
        definition("create_skill", "创建本地 Markdown Skill", skillProperties(includeID: false), required: ["name", "category", "markdown"]),
        definition("update_skill", "修改本地 Markdown Skill；内置 Skill 只读", skillProperties(includeID: true), required: ["skill_id"]),
        definition("delete_skill", "删除本地 Markdown Skill；准确名称用于防误删", [
            "skill_id": string(), "expected_name": string()], required: ["skill_id", "expected_name"]),

        definition("list_vector_libraries", "列出全部本地写法向量库及统计"),
        definition("get_vector_library", "读取向量库信息和写法统计", ["library_id": string()], required: ["library_id"]),
        definition("search_vector_library", "在指定向量库中进行本地语义检索", [
            "library_id": string(), "query": string(), "limit": integer("默认 12，最大 30")], required: ["library_id", "query"]),
        definition("list_vector_chapters", "列出向量库全部章节", ["library_id": string()], required: ["library_id"]),
        definition("read_vector_chapter", "读取向量库指定章节的完整正文", [
            "library_id": string(), "number": integer()], required: ["library_id", "number"]),
        definition("update_vector_library", "修改向量库书名、作者、分类和简介", [
            "library_id": string(), "title": string(), "author": string(), "category": string(), "summary": string()], required: ["library_id"]),
        definition("update_vector_chapter", "修改向量库章节并自动重建该章向量索引", [
            "library_id": string(), "number": integer(), "title": string(), "content": string()], required: ["library_id", "number", "title", "content"]),
        definition("delete_vector_library", "删除整个向量库；准确书名用于防误删", [
            "library_id": string(), "expected_title": string()], required: ["library_id", "expected_title"]),
        definition("import_vector_txt", "从明确的本地 TXT 路径导入写法向量库", [
            "path": string("UTF-8 TXT 绝对路径"), "expected_chapter_count": integer("可选的章节数校验")], required: ["path"]),
        definition("get_style_profile", "提取向量库的抽象写法画像，不返回原文片段", ["library_id": string()], required: ["library_id"]),

        definition("export_book_file", "把书籍导出到应用专用 Exports 目录", ["book_id": string("省略时使用当前书籍")]),
        definition("import_book_file", "从明确的 .zhinovel.json 绝对路径导入书籍", ["path": string()], required: ["path"]),
        definition("list_exported_files", "列出应用专用 Exports 目录中的书籍交换文件"),
        definition("delete_exported_file", "删除 Exports 目录中的指定文件；只允许准确文件名", [
            "filename": string(), "expected_filename": string()], required: ["filename", "expected_filename"]),

        definition("get_workspace_preferences", "读取模型参数、上下文、工具开关与外观等非敏感偏好；不返回 API Key"),
        definition("update_workspace_preferences", "修改非敏感工作区偏好；不能修改 API Key、服务地址或模型商", [
            "temperature": number(), "top_p": number(), "max_tokens": integer(), "context_window": integer(),
            "enable_context_compression": boolean(),
            "compression_level": ["type": "string", "enum": ["conservative", "balanced", "aggressive", "custom"]],
            "compression_custom_ratio": number(), "enable_tools": boolean(), "favorite_skills": strings(),
            "automatic_background_scheduling": boolean("自动规划核心和内存"),
            "conversation_core_percent": integer("手动模式下每个会话的核心份额；100 表示一个逻辑核心"),
            "conversation_memory_mb": integer("手动模式下每个会话独立预留的内存 MB"),
            "background_opacity": number(), "theme_hue": number(), "theme_brightness": number()]),
    ]

    private static func agentProperties(includeID: Bool) -> JSON {
        var p: JSON = [
            "name": string(), "icon": string(), "system_prompt": string(), "model": string(),
            "temperature": number(), "top_p": number(), "max_tokens": integer(),
            "tools": strings("工具名称白名单；空数组表示禁用全部"),
            "fixed_skill_id": string("每轮固定注入的单个 Skill ID"),
            "clear_fixed_skill": boolean("true 表示取消固定 Skill"),
            "lore_entry_ids": strings("固定挂载的设定 UUID"),
            "use_all_tools": boolean("true 表示跟随全局全部工具"),
            ]
        if includeID { p["agent_id"] = string() }
        return p
    }

    private static func skillProperties(includeID: Bool) -> JSON {
        var p: JSON = [
            "name": string(), "description": string(),
            "category": ["type": "string", "enum": ["write", "world", "analyze", "创作", "设定", "分析"]],
            "icon": string(), "needs_text": boolean(), "chapters": integer("注入前文章节数，0 到 10"),
            "markdown": string("追加到 Agent 系统提示词的完整技能指令")]
        if includeID { p["skill_id"] = string() }
        return p
    }

    static func execute(_ tc: ToolCall, app: AppState) -> String? {
        guard catalog.contains(where: { $0.id == tc.name }) else { return nil }
        let args = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) as? JSON ?? [:]
        switch tc.name {
        case "get_workspace_state": return workspaceState(app)
        case "search_workspace": return searchWorkspace(args, app)
        case "list_conversations": return listConversations(args, app)
        case "read_conversation": return readConversation(args, app)
        case "create_conversation": return createConversation(args, app)
        case "rename_conversation": return renameConversation(args, app)
        case "clear_conversation": return clearConversation(args, app)
        case "delete_conversation": return deleteConversation(args, app)
        case "list_all_conversations": return listAllConversations(app)
        case "send_message_to_conversation": return sendToConversation(args, app)
        case "get_conversation_run": return getConversationRun(args, app)
        case "wait_conversations": return "等待请求必须由会话协调器执行"
        case "cancel_conversation_run": return cancelConversationRun(args, app)
        case "list_agents": return listAgents(app)
        case "get_agent": return getAgent(args, app)
        case "create_agent": return createAgent(args, app)
        case "update_agent": return updateAgent(args, app)
        case "duplicate_agent": return duplicateAgent(args, app)
        case "delete_agent": return deleteAgent(args, app)
        case "list_skills": return listSkills(app)
        case "get_skill": return getSkill(args, app)
        case "create_skill": return saveSkill(args, app, existing: nil)
        case "update_skill":
            guard let skill = findSkill(args, app), skill.isMarkdown else { return "错误：找不到可编辑的 Markdown Skill" }
            return saveSkill(args, app, existing: skill)
        case "delete_skill": return deleteSkill(args, app)
        case "list_vector_libraries": return listVectorLibraries(app)
        case "get_vector_library": return getVectorLibrary(args)
        case "search_vector_library": return searchVectorLibrary(args)
        case "list_vector_chapters": return listVectorChapters(args)
        case "read_vector_chapter": return readVectorChapter(args)
        case "update_vector_library": return updateVectorLibrary(args, app)
        case "update_vector_chapter": return updateVectorChapter(args, app)
        case "delete_vector_library": return deleteVectorLibrary(args, app)
        case "import_vector_txt": return importVectorTXT(args, app)
        case "get_style_profile": return getStyleProfile(args)
        case "export_book_file": return exportBook(args, app)
        case "import_book_file": return importBook(args, app)
        case "list_exported_files": return listExports()
        case "delete_exported_file": return deleteExport(args)
        case "get_workspace_preferences": return getPreferences(app)
        case "update_workspace_preferences": return updatePreferences(args, app)
        default: return nil
        }
    }

    // MARK: Workspace

    private static func workspaceState(_ app: AppState) -> String {
        let chapterCount = app.novels.reduce(0) { $0 + DB.shared.chapters(novelID: $1.id).count }
        let loreCount = app.novels.reduce(0) { $0 + DB.shared.entries(novelID: $1.id).count }
        let conversationCount = app.novels.reduce(0) { $0 + DB.shared.conversations(novelID: $1.id).count }
        let currentBook = app.novels.first { $0.id == app.currentNovelID }
        let currentChapter = app.chapters.first { $0.id == app.selectedChapterID }
        let currentConversation = app.conversations.first { $0.id == app.currentConversationID }
        return """
        工作区：\(app.novels.count) 本书 · \(chapterCount) 章 · \(loreCount) 条设定 · \(conversationCount) 个会话
        Agent：\(app.agents.count) 个 · Skills：\(app.skills.count) 个 · 写法向量库：\(VectorStore().libraries().count) 个
        当前书籍：\(currentBook.map { "《\($0.title)》 [\($0.id.uuidString)]" } ?? "无")
        当前章节：\(currentChapter.map { "第\($0.no)章《\($0.title)》 [\($0.id.uuidString)]" } ?? "无")
        当前会话：\(currentConversation.map { "\($0.title) [\($0.id.uuidString)]" } ?? "无")
        当前 Agent：\(app.currentAgent.name) [\(app.currentAgent.id.uuidString)]
        固定 Skill：\(app.currentAgent.fixedSkillID.flatMap { id in app.skills.first { $0.id == id }?.name } ?? "无")
        按需 Skill 索引数：\(indexedSkills(for: app.currentAgent, skills: app.skills).count)
        数据目录：\(AppPaths.dataDir.path)
        """
    }

    private static func searchWorkspace(_ args: JSON, _ app: AppState) -> String {
        guard let query = args["query"] as? String, !query.isEmpty else { return "错误：缺少 query" }
        var lines: [String] = []
        for novel in app.novels {
            if novel.title.localizedCaseInsensitiveContains(query) || novel.desc.localizedCaseInsensitiveContains(query) || novel.outline.localizedCaseInsensitiveContains(query) {
                lines.append("【书籍】《\(novel.title)》 · book_id: \(novel.id.uuidString)")
            }
            let result = DB.shared.search(query, novelID: novel.id)
            lines += result.entries.prefix(5).map { "【\(novel.title)·设定】\($0.title) [\($0.id.uuidString)]：\($0.content.prefix(240))" }
            lines += result.chapters.prefix(5).map { "【\(novel.title)·第\($0.no)章】\($0.title)：\($0.content.prefix(320))" }
            if lines.count >= 50 { break }
        }
        return lines.isEmpty ? "工作区中未找到匹配内容" : lines.prefix(50).joined(separator: "\n")
    }

    // MARK: Conversations

    private static func findBook(_ args: JSON, _ app: AppState) -> Novel? {
        if let raw = args["book_id"] as? String, let id = UUID(uuidString: raw) { return app.novels.first { $0.id == id } }
        return app.novels.first { $0.id == app.currentNovelID }
    }
    private static func findConversation(_ raw: String?, _ app: AppState) -> (Novel, Conversation)? {
        guard let raw, let id = UUID(uuidString: raw) else { return nil }
        for novel in app.novels {
            if let conversation = DB.shared.conversations(novelID: novel.id).first(where: { $0.id == id }) { return (novel, conversation) }
        }
        return nil
    }
    private static func listConversations(_ args: JSON, _ app: AppState) -> String {
        guard let novel = findBook(args, app) else { return "错误：找不到指定书籍" }
        let rows = DB.shared.conversations(novelID: novel.id)
        return rows.isEmpty ? "暂无会话" : rows.map { "\($0.title) · conversation_id: \($0.id.uuidString)" }.joined(separator: "\n")
    }
    private static func readConversation(_ args: JSON, _ app: AppState) -> String {
        guard let (novel, conversation) = findConversation(args["conversation_id"] as? String, app) else { return "错误：找不到会话" }
        let limit = max(1, min(args["limit"] as? Int ?? 50, 200))
        let offset = max(0, args["offset"] as? Int ?? 0)
        let messages = DB.shared.messages(novelID: novel.id, conversationID: conversation.id, limit: limit, offset: offset)
        if messages.isEmpty { return "会话《\(conversation.title)》暂无消息" }
        return "会话《\(conversation.title)》 · offset: \(offset) · returned: \(messages.count) · next_offset: \(messages.count == limit ? String(offset + messages.count) : "none")\n" + messages.map { "[\($0.role)] \($0.content.prefix(3000))" }.joined(separator: "\n\n")
    }
    private static func createConversation(_ args: JSON, _ app: AppState) -> String {
        guard let novel = findBook(args, app), let title = args["title"] as? String, !title.isEmpty else { return "错误：书籍或标题无效" }
        let row = DB.shared.createConversation(novelID: novel.id, title: title)
        if app.currentNovelID == novel.id { app.conversations.insert(row, at: 0) }
        return "已创建会话《\(row.title)》\nconversation_id: \(row.id.uuidString)"
    }
    private static func renameConversation(_ args: JSON, _ app: AppState) -> String {
        guard let (_, row) = findConversation(args["conversation_id"] as? String, app),
              let title = args["title"] as? String, !title.isEmpty else { return "错误：会话或标题无效" }
        DB.shared.renameConversation(id: row.id, title: title)
        if let i = app.conversations.firstIndex(where: { $0.id == row.id }) { app.conversations[i].title = title }
        return "已将会话重命名为《\(title)》"
    }
    private static func clearConversation(_ args: JSON, _ app: AppState) -> String {
        guard let (_, row) = findConversation(args["conversation_id"] as? String, app) else { return "错误：找不到会话" }
        guard args["expected_title"] as? String == row.title else { return "错误：会话标题校验失败" }
        DB.shared.clearMessages(conversationID: row.id)
        if app.currentConversationID == row.id { app.messages = [] }
        return "已清空会话《\(row.title)》"
    }
    private static func deleteConversation(_ args: JSON, _ app: AppState) -> String {
        guard let (novel, row) = findConversation(args["conversation_id"] as? String, app) else { return "错误：找不到会话" }
        guard args["expected_title"] as? String == row.title else { return "错误：会话标题校验失败" }
        if app.backgroundConversationTasks[row.id] != nil { _ = app.cancelConversationRun(row.id) }
        DB.shared.deleteConversation(id: row.id)
        if app.currentNovelID == novel.id {
            app.conversations.removeAll { $0.id == row.id }
            if app.currentConversationID == row.id {
                if app.conversations.isEmpty { app.conversations = [DB.shared.createConversation(novelID: novel.id)] }
                app.currentConversationID = app.conversations.first?.id
                app.reloadMessages()
            }
        }
        return "已删除会话《\(row.title)》"
    }
    private static func listAllConversations(_ app: AppState) -> String {
        var lines: [String] = []
        let scopes: [(UUID, String)] = [(GLOBAL_CHAT_NOVEL_ID, "自由对话")] + app.novels.map { ($0.id, "《\($0.title)》") }
        for (novelID, label) in scopes {
            for row in DB.shared.conversations(novelID: novelID) {
                let status = app.conversationRunStates[row.id]?.status ?? "idle"
                lines.append("\(label) · \(row.title) · conversation_id: \(row.id.uuidString) · status: \(status)")
            }
        }
        return lines.isEmpty ? "暂无会话" : lines.joined(separator: "\n")
    }
    private static func sendToConversation(_ args: JSON, _ app: AppState) -> String {
        guard let raw = args["conversation_id"] as? String, let id = UUID(uuidString: raw),
              let prompt = args["prompt"] as? String else { return "错误：conversation_id 或 prompt 无效" }
        let agentID = (args["agent_id"] as? String).flatMap(UUID.init(uuidString:))
        return app.dispatchConversationRun(conversationID: id, prompt: prompt, agentID: agentID,
                                           requestedSkillID: args["skill_id"] as? String)
    }
    private static func getConversationRun(_ args: JSON, _ app: AppState) -> String {
        let ids = (args["conversation_ids"] as? [String])?.compactMap(UUID.init(uuidString:))
        return app.conversationRunSnapshot(ids)
    }
    private static func cancelConversationRun(_ args: JSON, _ app: AppState) -> String {
        guard let raw = args["conversation_id"] as? String, let id = UUID(uuidString: raw) else { return "错误：conversation_id 无效" }
        return app.cancelConversationRun(id)
    }

    // MARK: Agents

    private static func findAgent(_ args: JSON, _ app: AppState) -> Agent? {
        guard let raw = args["agent_id"] as? String, let id = UUID(uuidString: raw) else { return nil }
        return app.agents.first { $0.id == id }
    }
    private static func listAgents(_ app: AppState) -> String {
        app.agents.map { "\($0.isBuiltin ? "内置" : "自定义") · \($0.icon) \($0.name) · agent_id: \($0.id.uuidString) · \($0.tools == nil ? "全部工具" : "\($0.tools!.count) 个工具")" }.joined(separator: "\n")
    }
    private static func getAgent(_ args: JSON, _ app: AppState) -> String {
        guard let a = findAgent(args, app) else { return "错误：找不到 Agent" }
        let temperature = a.temperature.map { String($0) } ?? "跟随"
        let topP = a.topP.map { String($0) } ?? "跟随"
        let maxTokens = a.maxTokens.map { String($0) } ?? "跟随"
        return """
        \(a.icon) \(a.name) · \(a.isBuiltin ? "内置只读" : "自定义")
        agent_id: \(a.id.uuidString)
        系统提示词：\(a.systemPrompt)
        模型覆盖：\(a.model ?? "跟随全局") · temperature: \(temperature) · top_p: \(topP) · max_tokens: \(maxTokens)
        工具：\(a.tools?.joined(separator: ", ") ?? "全部")
        固定 Skill：\(a.fixedSkillID ?? "无")
        动态 Skill 索引：完整技能库（固定 Skill 除外）
        固定设定：\(a.loreEntryIDs?.map(\.uuidString).joined(separator: ", ") ?? "无")
        """
    }
    private static func createAgent(_ args: JSON, _ app: AppState) -> String {
        guard let name = args["name"] as? String, !name.isEmpty,
              let prompt = args["system_prompt"] as? String else { return "错误：缺少 name 或 system_prompt" }
        let agent = Agent(id: UUID(), name: name, icon: args["icon"] as? String ?? "🤖", systemPrompt: prompt,
                          model: args["model"] as? String, temperature: args["temperature"] as? Double,
                          topP: args["top_p"] as? Double, maxTokens: args["max_tokens"] as? Int,
                          tools: validatedTools(args), skills: validatedSkills(args, app),
                          fixedSkillID: validatedFixedSkill(args, app),
                          loreEntryIDs: loreIDs(args), isBuiltin: false)
        app.agents.append(agent); AgentStore.save(app.agents)
        return "已创建 Agent《\(agent.name)》\nagent_id: \(agent.id.uuidString)"
    }
    private static func updateAgent(_ args: JSON, _ app: AppState) -> String {
        guard var a = findAgent(args, app), !a.isBuiltin else { return "错误：找不到可编辑的自定义 Agent" }
        if let v = args["name"] as? String { a.name = v }
        if let v = args["icon"] as? String { a.icon = v }
        if let v = args["system_prompt"] as? String { a.systemPrompt = v }
        if let v = args["model"] as? String { a.model = v.isEmpty ? nil : v }
        if let v = args["temperature"] as? Double { a.temperature = v }
        if let v = args["top_p"] as? Double { a.topP = v }
        if let v = args["max_tokens"] as? Int { a.maxTokens = v }
        if args["tools"] != nil || args["use_all_tools"] != nil { a.tools = validatedTools(args) }
        if args["fixed_skill_id"] != nil || args["clear_fixed_skill"] as? Bool == true {
            a.fixedSkillID = args["clear_fixed_skill"] as? Bool == true ? nil : validatedFixedSkill(args, app)
        }
        if args["lore_entry_ids"] != nil { a.loreEntryIDs = loreIDs(args) }
        app.saveAgent(a)
        return "已更新 Agent《\(a.name)》"
    }
    private static func duplicateAgent(_ args: JSON, _ app: AppState) -> String {
        guard let a = findAgent(args, app) else { return "错误：找不到 Agent" }
        let copy = Agent(id: UUID(), name: args["name"] as? String ?? a.name + "（副本）", icon: a.icon,
                         systemPrompt: a.systemPrompt, model: a.model, temperature: a.temperature, topP: a.topP,
                         maxTokens: a.maxTokens, tools: a.tools, skills: a.skills,
                         fixedSkillID: a.fixedSkillID, loreEntryIDs: a.loreEntryIDs, isBuiltin: false)
        app.agents.append(copy); AgentStore.save(app.agents)
        return "已复制 Agent《\(copy.name)》\nagent_id: \(copy.id.uuidString)"
    }
    private static func deleteAgent(_ args: JSON, _ app: AppState) -> String {
        guard let a = findAgent(args, app), !a.isBuiltin else { return "错误：找不到可删除的自定义 Agent" }
        guard args["expected_name"] as? String == a.name else { return "错误：Agent 名称校验失败" }
        app.deleteAgent(a.id)
        return "已删除 Agent《\(a.name)》"
    }
    private static func validatedTools(_ args: JSON) -> [String]? {
        if args["use_all_tools"] as? Bool == true { return nil }
        guard let requested = args["tools"] as? [String] else { return nil }
        let valid = Set(AppState.writingTools.compactMap { ($0["function"] as? JSON)?["name"] as? String })
        return requested.filter { valid.contains($0) }
    }
    private static func validatedSkills(_ args: JSON, _ app: AppState) -> [String]? {
        if args["use_all_skills"] as? Bool == true { return nil }
        guard let requested = args["skills"] as? [String] else { return nil }
        let valid = Set(app.skills.map(\.id)); return requested.filter { valid.contains($0) }
    }
    private static func validatedFixedSkill(_ args: JSON, _ app: AppState) -> String? {
        guard let id = args["fixed_skill_id"] as? String, id != "chat",
              app.skills.contains(where: { $0.id == id }) else { return nil }
        return id
    }
    private static func loreIDs(_ args: JSON) -> [UUID]? {
        (args["lore_entry_ids"] as? [String])?.compactMap(UUID.init(uuidString:))
    }

    // MARK: Skills

    private static func findSkill(_ args: JSON, _ app: AppState) -> Skill? {
        guard let id = args["skill_id"] as? String else { return nil }; return app.skills.first { $0.id == id }
    }
    private static func listSkills(_ app: AppState) -> String {
        app.skills.map { "\($0.isMarkdown ? "Markdown" : "内置") · [\($0.category.rawValue)] \($0.name) · skill_id: \($0.id) · 前文 \($0.chapters) 章" }.joined(separator: "\n")
    }
    private static func getSkill(_ args: JSON, _ app: AppState) -> String {
        guard let s = findSkill(args, app) else { return "错误：找不到 Skill" }
        return "[\(s.category.rawValue)] \(s.name) · \(s.isMarkdown ? "Markdown 可编辑" : "内置只读")\nskill_id: \(s.id)\n说明：\(s.desc)\n图标：\(s.icon) · needs_text: \(s.needsText) · chapters: \(s.chapters)\n\n\(s.system)"
    }
    private static func skillCategory(_ raw: String?) -> SkillCategory? {
        switch raw { case "write", "创作": return .write; case "world", "设定": return .world; case "analyze", "分析": return .analyze; default: return nil }
    }
    private static func saveSkill(_ args: JSON, _ app: AppState, existing: Skill?) -> String {
        let name = args["name"] as? String ?? existing?.name ?? ""
        let desc = args["description"] as? String ?? existing?.desc ?? ""
        let category = skillCategory(args["category"] as? String) ?? existing?.category
        let markdown = args["markdown"] as? String ?? existing?.system ?? ""
        guard !name.isEmpty, let category, !markdown.isEmpty else { return "错误：name、category 或 markdown 无效" }
        do {
            let saved = try SkillStore.save(existing: existing, name: name, desc: desc, category: category,
                                             icon: args["icon"] as? String ?? existing?.icon ?? "doc.text",
                                             needsText: args["needs_text"] as? Bool ?? existing?.needsText ?? false,
                                             chapters: args["chapters"] as? Int ?? existing?.chapters ?? 0, markdown: markdown)
            app.reloadSkills()
            return "已保存 Markdown Skill《\(saved.name)》\nskill_id: \(saved.id)"
        } catch { return "错误：\(error.localizedDescription)" }
    }
    private static func deleteSkill(_ args: JSON, _ app: AppState) -> String {
        guard let s = findSkill(args, app), s.isMarkdown else { return "错误：找不到可删除的 Markdown Skill" }
        guard args["expected_name"] as? String == s.name else { return "错误：Skill 名称校验失败" }
        app.deleteSkill(s); return "已删除 Markdown Skill《\(s.name)》"
    }

    // MARK: Vector libraries

    private static func vectorLibrary(_ raw: String?) -> VectorLibrary? {
        guard let raw, let id = UUID(uuidString: raw) else { return nil }; return VectorStore().libraries().first { $0.id == id }
    }
    private static func listVectorLibraries(_ app: AppState) -> String {
        let rows = VectorStore().libraries()
        return rows.isEmpty ? "暂无写法向量库" : rows.map { "《\($0.title)》 · \($0.author) · library_id: \($0.id.uuidString) · \($0.chapterCount) 章/\($0.chunkCount) 片段" }.joined(separator: "\n")
    }
    private static func getVectorLibrary(_ args: JSON) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String) else { return "错误：找不到向量库" }
        return "《\(l.title)》\nlibrary_id: \(l.id.uuidString)\n作者：\(l.author) · 分类：\(l.category)\n简介：\(l.summary)\n外部 ID：\(l.externalID)\n\(l.wordCount) 字 · \(l.chapterCount) 章 · \(l.chunkCount) 个向量片段\n来源：\(l.sourcePath)"
    }
    private static func searchVectorLibrary(_ args: JSON) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String), let query = args["query"] as? String else { return "错误：向量库或 query 无效" }
        let rows = VectorStore().search(libraryID: l.id, queryText: query, limit: max(1, min(args["limit"] as? Int ?? 12, 30)))
        return rows.isEmpty ? "未找到相关写法片段" : rows.map { "【第\($0.chapterNo)章·片段\($0.chunkNo)·相似度 \(String(format: "%.3f", $0.score))】\($0.chapterTitle)：\($0.content.prefix(800))" }.joined(separator: "\n")
    }
    private static func listVectorChapters(_ args: JSON) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String) else { return "错误：找不到向量库" }
        let rows = VectorStore().chapters(libraryID: l.id)
        return rows.isEmpty ? "向量库暂无章节" : rows.map { "第\($0.no)章《\($0.title)》 · \($0.content.count) 字符 · chapter_id: \($0.id.uuidString)" }.joined(separator: "\n")
    }
    private static func readVectorChapter(_ args: JSON) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String), let n = args["number"] as? Int,
              let c = VectorStore().chapters(libraryID: l.id).first(where: { $0.no == n }) else { return "错误：找不到向量库章节" }
        return "第\(c.no)章《\(c.title)》\nchapter_id: \(c.id.uuidString)\n\n\(c.content)"
    }
    private static func updateVectorLibrary(_ args: JSON, _ app: AppState) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String) else { return "错误：找不到向量库" }
        let ok = VectorStore().updateLibrary(l, title: args["title"] as? String ?? l.title,
                                             author: args["author"] as? String ?? l.author,
                                             category: args["category"] as? String ?? l.category,
                                             summary: args["summary"] as? String ?? l.summary)
        if ok { app.refreshVectorLibraries() }
        return ok ? "已更新向量库《\(args["title"] as? String ?? l.title)》" : "错误：向量库更新失败"
    }
    private static func updateVectorChapter(_ args: JSON, _ app: AppState) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String), let n = args["number"] as? Int,
              let c = VectorStore().chapters(libraryID: l.id).first(where: { $0.no == n }),
              let title = args["title"] as? String, let content = args["content"] as? String else { return "错误：向量库章节或内容无效" }
        guard VectorStore().updateChapter(c, title: title, content: content) != nil else { return "错误：章节更新失败" }
        if app.selectedVectorLibraryID == l.id { app.vectorChapters = VectorStore().chapters(libraryID: l.id) }
        return "已更新写法库第 \(n) 章并重建向量索引"
    }
    private static func deleteVectorLibrary(_ args: JSON, _ app: AppState) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String) else { return "错误：找不到向量库" }
        guard args["expected_title"] as? String == l.title else { return "错误：向量库标题校验失败" }
        VectorStore().delete(l); app.refreshVectorLibraries(); return "已删除向量库《\(l.title)》"
    }
    private static func importVectorTXT(_ args: JSON, _ app: AppState) -> String {
        guard let path = args["path"] as? String, let url = GovernanceTools.authorizedImportURL(path),
              url.pathExtension.lowercased() == "txt" else {
            return "错误：只允许导入应用 Imports 授权目录内的 .txt 文件；先调用 list_authorized_import_files"
        }
        do {
            let l = try VectorStore().importTXT(url: url, expectedChapterCount: args["expected_chapter_count"] as? Int)
            app.refreshVectorLibraries(); return "已导入写法向量库《\(l.title)》\nlibrary_id: \(l.id.uuidString) · \(l.chapterCount) 章/\(l.chunkCount) 片段"
        } catch { return "错误：\(error.localizedDescription)" }
    }
    private static func getStyleProfile(_ args: JSON) -> String {
        guard let l = vectorLibrary(args["library_id"] as? String) else { return "错误：找不到向量库" }
        return VectorStore().styleProfile(libraryID: l.id) ?? "正文不足，无法提取写法画像"
    }

    // MARK: Exchange files

    private static var exportsDirectory: URL {
        let url = AppPaths.dataDir.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private static func exportBook(_ args: JSON, _ app: AppState) -> String {
        guard let novel = findBook(args, app) else { return "错误：找不到指定书籍" }
        let document = ZhinaiBookDocument(novel: novel, chapters: DB.shared.chapters(novelID: novel.id), entries: DB.shared.entries(novelID: novel.id))
        let base = ZhinaiBookDocument.suggestedFilename(for: novel.title)
        var url = exportsDirectory.appendingPathComponent(base)
        if FileManager.default.fileExists(atPath: url.path) {
            let stem = String(base.dropLast(".zhinovel.json".count))
            url = exportsDirectory.appendingPathComponent("\(stem)-\(Int(Date().timeIntervalSince1970)).zhinovel.json")
        }
        do { try document.write(to: url); return "已导出《\(novel.title)》\n文件：\(url.path)" }
        catch { return "错误：\(error.localizedDescription)" }
    }
    private static func importBook(_ args: JSON, _ app: AppState) -> String {
        guard let path = args["path"] as? String, let url = GovernanceTools.authorizedImportURL(path),
              path.lowercased().hasSuffix(".zhinovel.json") else {
            return "错误：只允许导入应用 Imports 授权目录内的 .zhinovel.json 文件；先调用 list_authorized_import_files"
        }
        do {
            let doc = try ZhinaiBookDocument.read(from: url)
            var novel = DB.shared.createNovel(title: doc.book.title, desc: doc.book.description)
            var meta = doc.book.metadata ?? BookMetadata()
            if let c = doc.config {
                meta.subtitle = c.subtitle; meta.authors = c.authors; meta.penName = c.penName
                meta.genres = c.genre.isEmpty ? [] : [c.genre]; meta.tags = c.tags; meta.platform = c.platform
                meta.status = c.status; meta.language = c.language; meta.targetChapters = c.targetChapters
                meta.chapterWordCount = c.chapterWordCount; meta.reviewMode = c.reviewMode
                meta.styleLibraryID = c.styleLibraryID ?? ""; meta.styleStrength = c.styleStrength ?? 0.65
            }
            if let s = doc.story {
                meta.authorIntent = s.authorIntent; meta.currentFocus = s.currentFocus; meta.storyFrame = s.storyFrame; meta.bookRules = s.bookRules
            }
            if let p = doc.publishing {
                meta.seriesName = p.seriesName; meta.seriesNumber = p.seriesNumber; meta.targetAudience = p.targetAudience
                meta.contentRating = p.contentRating; meta.isbn = p.isbn; meta.publisher = p.publisher
                meta.publicationDate = p.publicationDate; meta.rights = p.rights; meta.source = p.source
            }
            novel.outline = doc.story?.volumeOutline ?? doc.book.outline; novel.metadata = meta
            DB.shared.updateNovel(id: novel.id, outline: novel.outline, metadata: meta)
            for c in doc.chapters.sorted(by: { $0.number < $1.number }) { _ = DB.shared.createChapter(novelID: novel.id, title: c.title, content: c.content) }
            for e in doc.lore { _ = DB.shared.createEntry(novelID: novel.id, type: e.type, title: e.title, content: e.content, keywords: e.keywords.joined(separator: ", "), pinned: e.pinned) }
            app.novels.insert(novel, at: 0)
            return "已导入《\(novel.title)》\nbook_id: \(novel.id.uuidString) · \(doc.chapters.count) 章/\(doc.lore.count) 条设定"
        } catch { return "错误：\(error.localizedDescription)" }
    }
    private static func listExports() -> String {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: exportsDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []).filter { $0.lastPathComponent.hasSuffix(".zhinovel.json") }
        return urls.isEmpty ? "Exports 目录为空" : urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return "\(url.lastPathComponent) · \(values?.fileSize ?? 0) bytes · \(url.path)"
        }.joined(separator: "\n")
    }
    private static func deleteExport(_ args: JSON) -> String {
        guard let filename = args["filename"] as? String, args["expected_filename"] as? String == filename,
              filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".zhinovel.json") else { return "错误：文件名校验失败" }
        let url = exportsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return "错误：文件不存在" }
        do { try FileManager.default.removeItem(at: url); return "已删除导出文件 \(filename)" }
        catch { return "错误：\(error.localizedDescription)" }
    }

    // MARK: Preferences

    private static func getPreferences(_ app: AppState) -> String {
        let c = app.config
        return "provider: \(c.provider)\nmodel: \(c.model)\ntemperature: \(c.temperature)\ntop_p: \(c.topP)\nmax_tokens: \(c.maxTokens)\ncontext_window: \(c.contextWindow)\ncompression: \(c.enableContextCompression) / \(c.contextCompressionLevel.rawValue) / \(c.contextCompressionCustomRatio)\nenable_tools: \(c.enableTools)\nautomatic_background_scheduling: \(c.automaticBackgroundScheduling)\nper_conversation_core_percent: \(c.plannedConversationCorePercent)\nper_conversation_memory_mb: \(c.plannedConversationMemoryMB)\nresource_based_concurrency_limit: \(c.backgroundConcurrencyLimit)\nfavorite_skills: \(c.favoriteSkills.joined(separator: ", "))\nbackground_opacity: \(c.backgroundOpacity)\ntheme_hue: \(c.themeHue)\ntheme_brightness: \(c.themeBrightness)\nAPI Key：已隐藏"
    }
    private static func updatePreferences(_ args: JSON, _ app: AppState) -> String {
        if let v = args["temperature"] as? Double { app.config.temperature = max(0, min(v, 2)) }
        if let v = args["top_p"] as? Double { app.config.topP = max(0, min(v, 1)) }
        if let v = args["max_tokens"] as? Int { app.config.maxTokens = max(1, v) }
        if let v = args["context_window"] as? Int { app.config.contextWindow = max(1024, v) }
        if let v = args["enable_context_compression"] as? Bool { app.config.enableContextCompression = v }
        if let raw = args["compression_level"] as? String, let v = ContextCompressionLevel(rawValue: raw) { app.config.contextCompressionLevel = v }
        if let v = args["compression_custom_ratio"] as? Double { app.config.contextCompressionCustomRatio = max(0.05, min(v, 1)) }
        if let v = args["enable_tools"] as? Bool { app.config.enableTools = v }
        if let v = args["automatic_background_scheduling"] as? Bool { app.config.automaticBackgroundScheduling = v }
        if let v = args["conversation_core_percent"] as? Int {
            app.config.conversationCorePercent = max(10, min(v, 400))
        }
        if let v = args["conversation_memory_mb"] as? Int {
            app.config.conversationMemoryMB = max(128, min(v, ModelConfig.availableMemoryMB))
        }
        if let v = args["favorite_skills"] as? [String] { app.config.favoriteSkills = v.filter { id in app.skills.contains { $0.id == id } } }
        if let v = args["background_opacity"] as? Double { app.config.backgroundOpacity = max(0, min(v, 1)) }
        if let v = args["theme_hue"] as? Double { app.config.themeHue = max(0, min(v, 1)) }
        if let v = args["theme_brightness"] as? Double { app.config.themeBrightness = max(0.2, min(v, 1)) }
        app.saveConfig(); return "已更新工作区偏好（连接信息和 API Key 未改动）"
    }
}
