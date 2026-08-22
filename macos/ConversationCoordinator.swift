import Foundation

@MainActor
extension AppState {
    /// 向任意会话派发独立后台 Agent 任务；任务不会因用户切换书籍或会话而停止。
    func dispatchConversationRun(conversationID: UUID, prompt: String,
                                 agentID: UUID? = nil, requestedSkillID: String? = nil) -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "错误：任务内容为空" }
        guard !(conversationID == currentConversationID && streaming) else {
            return "错误：不能向正在执行前台请求的同一会话重复派发任务"
        }
        guard backgroundConversationTasks[conversationID] == nil else { return "错误：该会话已有任务正在运行" }
        guard let target = locateConversation(conversationID) else { return "错误：找不到目标会话" }
        guard backgroundConversationTasks.count < 256 else { return "错误：后台任务队列已达到安全上限 256" }

        let chosenAgent = agents.first { $0.id == agentID } ?? currentAgent
        let chosenSkill = skillByID(requestedSkillID ?? "chat", skills: skills)
        var run = ConversationRun(conversationID: conversationID, novelID: target.novelID, status: "queued",
                                  prompt: prompt, agentID: chosenAgent.id, skillID: chosenSkill.id,
                                  partialText: "", error: "",
                                  reservedCorePercent: config.plannedConversationCorePercent,
                                  reservedMemoryMB: config.plannedConversationMemoryMB,
                                  startedAt: nil, updatedAt: Date())
        updateConversationRun(run)
        backgroundConversationTasks[conversationID] = Task { [weak self] in
            guard let self else { return }
            guard let claimedRun = await self.waitForBackgroundExecutionSlot(run) else { return }
            run = claimedRun
            await self.performBackgroundConversationRun(run: run, conversation: target.conversation,
                                                        agent: chosenAgent, skill: chosenSkill)
            self.releaseConversationResources(conversationID)
            self.backgroundConversationTasks[conversationID] = nil
        }
        let cores = Double(run.reservedCorePercent) / 100
        let coreText = String(format: "%.2f", cores)
        return "已向会话《\(target.conversation.title)》派发后台任务\nconversation_id: \(conversationID.uuidString)\nstatus: queued\n本会话预留: \(coreText) 核 / \(run.reservedMemoryMB) MB\n当前资源最多并行: \(config.backgroundConcurrencyLimit)"
    }

    private func waitForBackgroundExecutionSlot(_ pending: ConversationRun) async -> ConversationRun? {
        while !Task.isCancelled {
            let running = conversationRunStates.values.filter { $0.status == "running" }
            let usedCore = running.reduce(0) { $0 + $1.reservedCorePercent }
            let usedMemory = running.reduce(0) { $0 + $1.reservedMemoryMB }
            if usedCore + pending.reservedCorePercent <= config.backgroundCoreCapacityPercent,
               usedMemory + pending.reservedMemoryMB <= config.backgroundMemoryCapacityMB,
               running.count < 64 {
                var claimed = pending
                claimed.status = "running"; claimed.startedAt = Date(); claimed.updatedAt = Date()
                updateConversationRun(claimed)
                return claimed
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    func cancelConversationRun(_ conversationID: UUID) -> String {
        guard let task = backgroundConversationTasks[conversationID] else { return "错误：该会话没有正在运行的任务" }
        task.cancel(); backgroundConversationTasks[conversationID] = nil
        releaseConversationResources(conversationID)
        guard var run = conversationRunStates[conversationID] else { return "已取消后台任务" }
        run.status = "cancelled"; run.error = "用户或其他会话取消了任务"; run.updatedAt = Date()
        updateConversationRun(run)
        return "已取消会话后台任务"
    }

    func conversationRunSnapshot(_ ids: [UUID]? = nil) -> String {
        let selected = ids.map { wanted in wanted.compactMap { conversationRunStates[$0] } }
            ?? Array(conversationRunStates.values)
        if selected.isEmpty { return "没有后台会话任务" }
        return selected.sorted { $0.updatedAt > $1.updatedAt }.map { run in
            let title = locateConversation(run.conversationID)?.conversation.title ?? "已删除会话"
            let detail = run.error.isEmpty ? String(run.partialText.suffix(160)) : run.error
            let cores = String(format: "%.2f", Double(run.reservedCorePercent) / 100)
            return "《\(title)》 · conversation_id: \(run.conversationID.uuidString) · status: \(run.status) · 资源: \(cores) 核 / \(run.reservedMemoryMB) MB\(detail.isEmpty ? "" : " · \(detail)")"
        }.joined(separator: "\n")
    }

    func waitForConversationRuns(_ ids: [UUID], timeoutSeconds: Double) async -> String {
        let deadline = Date().addingTimeInterval(max(0, min(timeoutSeconds, 30)))
        repeat {
            let active = ids.contains { id in
                guard let status = conversationRunStates[id]?.status else { return false }
                return status == "queued" || status == "running"
            }
            if !active { break }
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        } while !Task.isCancelled
        return conversationRunSnapshot(ids)
    }

    func executeConversationWaitTool(_ call: ToolCall) async -> String? {
        guard call.name == "wait_conversations" else { return nil }
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        let ids = (args["conversation_ids"] as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
        guard !ids.isEmpty else { return "错误：conversation_ids 为空" }
        return await waitForConversationRuns(ids, timeoutSeconds: args["timeout_seconds"] as? Double ?? 30)
    }

    private func locateConversation(_ id: UUID) -> (novelID: UUID, conversation: Conversation)? {
        let novelIDs = [GLOBAL_CHAT_NOVEL_ID] + novels.map(\.id)
        for novelID in novelIDs {
            if let conversation = DB.shared.conversations(novelID: novelID).first(where: { $0.id == id }) {
                return (novelID, conversation)
            }
        }
        return nil
    }

    private func updateConversationRun(_ run: ConversationRun) {
        conversationRunStates[run.conversationID] = run
        DB.shared.saveConversationRun(run)
    }

    private func performBackgroundConversationRun(run initial: ConversationRun, conversation: Conversation,
                                                  agent: Agent, skill: Skill) async {
        var run = initial
        let novel = novels.first { $0.id == run.novelID }
            ?? Novel(id: GLOBAL_CHAT_NOVEL_ID, title: "", desc: "", outline: "", createdAt: Date(), updatedAt: Date())
        let chapters = run.novelID == GLOBAL_CHAT_NOVEL_ID ? [] : DB.shared.chapters(novelID: run.novelID)
        let allEntries = run.novelID == GLOBAL_CHAT_NOVEL_ID ? [] : DB.shared.entries(novelID: run.novelID)
        let history = DB.shared.messages(novelID: run.novelID, conversationID: run.conversationID)
        var entries = activateLorebook(entries: allEntries,
                                       scanText: run.prompt + "\n" + history.suffix(8).map(\.content).joined(separator: "\n"))
        if let ids = agent.loreEntryIDs {
            for entry in allEntries where ids.contains(entry.id) && !entries.contains(where: { $0.id == entry.id }) {
                entries.append(entry)
            }
        }
        let fixedSkill = agent.fixedSkillID.flatMap { id in skills.first { $0.id == id && $0.id != "chat" } }
        let skillIndex = indexedSkills(for: agent, skills: skills)
        let previous = Array(chapters.suffix(max(0, max(skill.chapters, fixedSkill?.chapters ?? 0))))
        let targetText = fixedSkill?.needsText == true ? chapters.last?.content ?? "" : ""
        let ctx = GenContext(novel: novel, chapters: previous, entries: entries, history: history,
                             userText: run.prompt, targetText: targetText, skill: skill,
                             fixedSkill: fixedSkill, indexedSkills: skillIndex)
        let maxTokens = agent.maxTokens ?? config.maxTokens
        let allowed = agent.tools.map(Set.init)
        let roots = ToolGroups.visibleNodes(parentID: nil, allowedNames: allowed)
        let skillLoaderTool = skillIndex.isEmpty ? nil : Self.writingTools.first { definition in
            (definition["function"] as? [String: Any])?["name"] as? String == "get_skill"
        }
        let workspaceToolRoots = config.enableTools ? ToolGroups.loaderDefinitions(for: roots) : []
        var tools: [[String: Any]]? = config.provider != "anthropic"
            ? workspaceToolRoots + [skillLoaderTool].compactMap { $0 } : nil
        var loadedLeaves: [ToolGroups.Node] = []
        var toolTokens = Self.estimatedToolDefinitionTokens(tools)
        let request = buildRequest(ctx: ctx, tokenBudget: config.contextWindow,
                                   compressionLevel: config.contextCompressionLevel,
                                   compressionTargetRetention: config.contextCompressionLevel == .custom ? config.contextCompressionCustomRatio : nil,
                                   reservedInputTokens: estimateTokens(agent.systemPrompt) + toolTokens)
        guard !request.plan.requestExceedsInputBudget else {
            run.status = "needs_attention"; run.error = "上下文超过输入窗口"; run.updatedAt = Date(); updateConversationRun(run); return
        }
        _ = DB.shared.addMessage(novelID: run.novelID, conversationID: run.conversationID,
                                 role: "user", content: run.prompt, skill: skill.id)
        let system = agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? request.system : agent.systemPrompt + "\n\n" + request.system
        var cfg = config; cfg.model = agent.model ?? config.model
        var msgs = request.messages
        var lastPersistedAt = Date.distantPast
        var reasoningStartedAt: Date?
        var reasoningDuration: Double = 0
        do {
            for _ in 0..<10 {
                try Task.checkCancellation()
                let result = try await LLM.streamChat(config: cfg, system: system, messages: msgs,
                                                      temperature: agent.temperature ?? config.temperature,
                                                      topP: agent.topP ?? config.topP, maxTokens: maxTokens,
                                                      tools: tools, onToolDelta: nil) { delta in
                    run.partialText += delta; run.updatedAt = Date()
                    let parsed = ModelOutputParser.parse(run.partialText)
                    if !parsed.reasoning.isEmpty {
                        if reasoningStartedAt == nil { reasoningStartedAt = Date() }
                        if let startedAt = reasoningStartedAt {
                            reasoningDuration = Date().timeIntervalSince(startedAt)
                        }
                    }
                    self.conversationRunStates[run.conversationID] = run
                    if Date().timeIntervalSince(lastPersistedAt) >= 1 {
                        DB.shared.saveConversationRun(run)
                        lastPersistedAt = Date()
                    }
                }
                if result.toolCalls.isEmpty { break }
                msgs.append(ChatMsg(role: "assistant",
                                    content: ModelOutputParser.parse(result.text).response,
                                    toolCalls: result.toolCalls))
                for call in result.toolCalls {
                    let output: String
                    if let node = ToolGroups.node(forLoader: call.name) {
                        if node.isLeaf {
                            loadedLeaves.removeAll { $0.id == node.id }; loadedLeaves.append(node)
                            if loadedLeaves.count > 4 { loadedLeaves.removeFirst() }
                        }
                        let nextParent = node.isLeaf ? node.parentID : node.id
                        let nav = ToolGroups.loaderDefinitions(for: roots)
                            + ToolGroups.loaderDefinitions(for: ToolGroups.visibleNodes(parentID: nextParent, allowedNames: allowed))
                        let details = loadedLeaves.flatMap { ToolGroups.detailedDefinitions(for: $0, allDefinitions: Self.writingTools, allowedNames: allowed) }
                        tools = nav + details + [skillLoaderTool].compactMap { $0 }
                        toolTokens = Self.estimatedToolDefinitionTokens(tools)
                        output = node.isLeaf ? "已加载【\(node.label)】详细工具" : "已展开【\(node.label)】下一层"
                    } else if let loadedSkill = Self.indexedSkillResult(call, skills: skillIndex) {
                        output = loadedSkill
                    } else if let waited = await executeConversationWaitTool(call) {
                        output = waited
                    } else {
                        output = executeConversationIsolatedTool(call, conversationID: run.conversationID,
                                                                 novelID: run.novelID)
                    }
                    msgs.append(ChatMsg(role: "tool", content: output, toolCallID: call.id))
                }
                let fitted = Self.fitToolRoundMessages(msgs, system: system, toolDefinitionTokens: toolTokens,
                                                       inputBudget: config.contextWindow, query: run.prompt,
                                                       compressionLevel: config.contextCompressionLevel)
                guard fitted.fits else { run.status = "needs_attention"; run.error = "工具结果超过输入窗口"; break }
                msgs = fitted.messages
                updateConversationRun(run)
            }
            if Task.isCancelled { throw CancellationError() }
            if run.status != "needs_attention" { run.status = "completed" }
            if !run.partialText.isEmpty {
                let parsed = ModelOutputParser.parse(run.partialText)
                _ = DB.shared.addMessage(novelID: run.novelID, conversationID: run.conversationID,
                                         role: "assistant", content: parsed.response, skill: skill.id,
                                         reasoning: parsed.reasoning,
                                         reasoningDuration: parsed.reasoning.isEmpty ? 0 : reasoningDuration)
            }
            run.updatedAt = Date(); updateConversationRun(run)
            if currentConversationID == run.conversationID { reloadMessages() }
        } catch is CancellationError {
            run.status = "cancelled"; run.error = "任务已取消"; run.updatedAt = Date(); updateConversationRun(run)
        } catch {
            run.status = "failed"; run.error = error.localizedDescription; run.updatedAt = Date(); updateConversationRun(run)
            _ = DB.shared.addMessage(novelID: run.novelID, conversationID: run.conversationID,
                                     role: "assistant", content: "❌ \(error.localizedDescription)", skill: skill.id)
        }
    }

    private func scopedToolCall(_ call: ToolCall, novelID: UUID) -> ToolCall {
        let scopedNames: Set<String> = ["search_database", "read_chapter", "list_chapters", "get_outline", "get_book", "get_story_stats",
            "update_book", "delete_book", "create_chapter", "update_chapter", "replace_chapter_text", "delete_chapter",
            "batch_create_chapters", "move_chapter", "duplicate_chapter", "split_chapter", "merge_chapters", "list_lore_entries", "create_lore_entry"]
        guard novelID != GLOBAL_CHAT_NOVEL_ID, scopedNames.contains(call.name),
              var args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any],
              args["book_id"] == nil else { return call }
        args["book_id"] = novelID.uuidString
        guard let data = try? JSONSerialization.data(withJSONObject: args), let json = String(data: data, encoding: .utf8) else { return call }
        return ToolCall(id: call.id, name: call.name, arguments: json)
    }

    func executeConversationIsolatedTool(_ call: ToolCall, conversationID: UUID, novelID: UUID) -> String {
        let scoped = scopedToolCall(call, novelID: novelID)
        let keys = mutationResourceKeys(for: scoped, novelID: novelID)
        guard !keys.isEmpty else { return Self.executeTool(scoped, app: self) }

        for key in keys {
            if let conflict = workspaceResourceOwners.first(where: { existing, owner in
                owner != conversationID && resourcesConflict(existing, key)
            }) {
                return "资源冲突：\(key) 正被会话 \(conflict.value.uuidString) 占用。本次写入未执行。请使用 get_conversation_run / wait_conversations 查询，或 send_message_to_conversation 与该会话协调后重试。"
            }
        }
        for key in keys {
            workspaceResourceOwners[key] = conversationID
            conversationOwnedResources[conversationID, default: []].insert(key)
        }
        captureRevisionBeforeMutation(scoped, conversationID: conversationID, novelID: novelID)
        return Self.executeTool(scoped, app: self)
    }

    func releaseConversationResources(_ conversationID: UUID) {
        for key in conversationOwnedResources.removeValue(forKey: conversationID) ?? [] {
            if workspaceResourceOwners[key] == conversationID { workspaceResourceOwners[key] = nil }
        }
    }

    private func resourcesConflict(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + ":") || rhs.hasPrefix(lhs + ":")
    }

    private func mutationResourceKeys(for call: ToolCall, novelID: UUID) -> [String] {
        let writes: Set<String> = [
            "create_book", "update_book", "delete_book", "create_chapter", "update_chapter",
            "replace_chapter_text", "delete_chapter", "batch_create_chapters", "move_chapter",
            "duplicate_chapter", "split_chapter", "merge_chapters", "create_lore_entry",
            "update_lore_entry", "delete_lore_entry", "create_conversation", "rename_conversation",
            "clear_conversation", "delete_conversation", "create_agent", "update_agent", "duplicate_agent",
            "delete_agent", "create_skill", "update_skill", "delete_skill", "update_vector_library",
            "update_vector_chapter", "delete_vector_library", "import_vector_txt", "export_book_file",
            "import_book_file", "delete_exported_file", "update_workspace_preferences",
            "delete_authorized_import_file", "create_story_node", "batch_create_story_nodes",
            "update_story_node", "delete_story_node", "restore_content_revision"
        ]
        guard writes.contains(call.name) else { return [] }
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        let value: (String) -> String? = { args[$0] as? String }
        let bookID = value("book_id") ?? (novelID == GLOBAL_CHAT_NOVEL_ID ? nil : novelID.uuidString)

        switch call.name {
        case "create_book", "import_book_file": return ["workspace:books"]
        case "update_book", "delete_book", "export_book_file": return bookID.map { ["book:\($0)"] } ?? ["workspace:books"]
        case "update_chapter", "replace_chapter_text":
            return bookID.map { ["book:\($0):chapters:\(args["number"] as? Int ?? -1)"] } ?? ["workspace:books"]
        case "create_chapter", "delete_chapter", "batch_create_chapters", "move_chapter",
             "duplicate_chapter", "split_chapter", "merge_chapters":
            return bookID.map { ["book:\($0):chapters"] } ?? ["workspace:books"]
        case "create_lore_entry": return bookID.map { ["book:\($0):lore"] } ?? ["workspace:books"]
        case "update_lore_entry", "delete_lore_entry":
            guard let entryID = value("entry_id") else { return ["workspace:lore"] }
            for novel in novels where DB.shared.entries(novelID: novel.id).contains(where: { $0.id.uuidString == entryID }) {
                return ["book:\(novel.id.uuidString):lore:\(entryID)"]
            }
            return ["workspace:lore:\(entryID)"]
        case "create_conversation": return ["book:\(bookID ?? novelID.uuidString):conversations"]
        case "rename_conversation", "clear_conversation", "delete_conversation":
            return ["conversation:\(value("conversation_id") ?? "unknown")"]
        case "create_agent": return ["workspace:agents"]
        case "update_agent", "duplicate_agent", "delete_agent": return ["workspace:agents:\(value("agent_id") ?? "unknown")"]
        case "create_skill": return ["workspace:skills"]
        case "update_skill", "delete_skill": return ["workspace:skills:\(value("skill_id") ?? "unknown")"]
        case "import_vector_txt": return ["workspace:vectors"]
        case "update_vector_library", "delete_vector_library": return ["workspace:vectors:\(value("library_id") ?? "unknown")"]
        case "update_vector_chapter": return ["workspace:vectors:\(value("library_id") ?? "unknown"):chapters:\(value("chapter_id") ?? "unknown")"]
        case "delete_exported_file": return ["workspace:exports:\(value("filename") ?? "unknown")"]
        case "update_workspace_preferences": return ["workspace:preferences"]
        case "delete_authorized_import_file": return ["workspace:imports:\(value("filename") ?? "unknown")"]
        case "create_story_node", "batch_create_story_nodes": return ["book:\(bookID ?? novelID.uuidString):story"]
        case "update_story_node", "delete_story_node":
            let nodeID = value("node_id") ?? "unknown"
            for novel in novels where DB.shared.storyNodes(novelID: novel.id).contains(where: { $0.id.uuidString == nodeID }) {
                return ["book:\(novel.id.uuidString):story:\(nodeID)"]
            }
            return ["workspace:story:\(nodeID)"]
        case "restore_content_revision": return ["revision:\(value("revision_id") ?? "unknown")"]
        default: return ["workspace:\(call.name)"]
        }
    }

    private func captureRevisionBeforeMutation(_ call: ToolCall, conversationID: UUID, novelID: UUID) {
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        let targetNovel = (args["book_id"] as? String).flatMap(UUID.init(uuidString:)) ?? novelID
        func saveChapter(_ chapter: Chapter) {
            DB.shared.addRevision(novelID: chapter.novelID, resourceType: "chapter", resourceID: chapter.id.uuidString,
                                  conversationID: conversationID, operation: "before_\(call.name)",
                                  snapshotJSON: GovernanceTools.json(["id": chapter.id.uuidString, "number": chapter.no,
                                                                     "title": chapter.title, "content": chapter.content]))
        }
        switch call.name {
        case "update_book", "delete_book":
            guard let novel = novels.first(where: { $0.id == targetNovel }) else { return }
            let metadata = (try? JSONEncoder().encode(novel.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            DB.shared.addRevision(novelID: novel.id, resourceType: "book", resourceID: novel.id.uuidString,
                                  conversationID: conversationID, operation: "before_\(call.name)",
                                  snapshotJSON: GovernanceTools.json(["title": novel.title, "description": novel.desc,
                                                                     "outline": novel.outline, "metadata": metadata]))
        case "update_chapter", "replace_chapter_text", "delete_chapter", "duplicate_chapter", "split_chapter":
            guard let number = args["number"] as? Int,
                  let chapter = DB.shared.chapters(novelID: targetNovel).first(where: { $0.no == number }) else { return }
            saveChapter(chapter)
        case "merge_chapters":
            let numbers = [args["first_number"] as? Int, args["second_number"] as? Int].compactMap { $0 }
            for chapter in DB.shared.chapters(novelID: targetNovel) where numbers.contains(chapter.no) { saveChapter(chapter) }
        case "move_chapter":
            for chapter in DB.shared.chapters(novelID: targetNovel) { saveChapter(chapter) }
        case "update_lore_entry", "delete_lore_entry":
            guard let raw = args["entry_id"] as? String, let id = UUID(uuidString: raw) else { return }
            for novel in novels {
                guard let entry = DB.shared.entries(novelID: novel.id).first(where: { $0.id == id }) else { continue }
                DB.shared.addRevision(novelID: novel.id, resourceType: "lore", resourceID: raw,
                                      conversationID: conversationID, operation: "before_\(call.name)",
                                      snapshotJSON: GovernanceTools.json(["id": raw, "type": entry.type, "title": entry.title,
                                                                         "content": entry.content, "keywords": entry.keywords,
                                                                         "pinned": entry.pinned]))
                return
            }
        case "update_story_node", "delete_story_node":
            guard let raw = args["node_id"] as? String, let id = UUID(uuidString: raw) else { return }
            for novel in novels {
                guard let node = DB.shared.storyNodes(novelID: novel.id).first(where: { $0.id == id }) else { continue }
                DB.shared.addRevision(novelID: novel.id, resourceType: "story_node", resourceID: raw,
                                      conversationID: conversationID, operation: "before_\(call.name)",
                                      snapshotJSON: GovernanceTools.json(["id": raw, "kind": node.kind, "title": node.title,
                                                                         "content": node.content, "status": node.status,
                                                                         "parent_id": node.parentID?.uuidString ?? "",
                                                                         "sort_order": node.sortOrder, "metadata_json": node.metadataJSON]))
                return
            }
        default: break
        }
    }
}
