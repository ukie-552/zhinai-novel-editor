import Foundation

/// 无头自检：数据库 / 会话 / 中文搜索 / 世界书 / 上下文预算 / Agent / LLM 流式 全链路。
/// 用法：AINOVEL_DATA_DIR=/tmp/x AINOVEL_TEST_BASEURL=http://127.0.0.1:19001/v1 ./selftest
@main
@MainActor
struct SelfTest {
    static func main() async {
        var failed = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "✅" : "❌") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if !ok { failed += 1 }
        }

        // 1. DB CRUD + 会话
        let db = DB.shared
        let novel = db.createNovel(title: "自检作品", desc: "测试")
        check("创建作品", db.novels().contains { $0.id == novel.id })

        let entry = db.createEntry(novelID: novel.id, type: "character", title: "林晚舟",
                                   content: "冷面女剑客，佩剑名「霜河」。", keywords: "林晚舟,霜河")
        check("创建设定", !db.entries(novelID: novel.id).isEmpty)

        let conv = db.createConversation(novelID: novel.id, title: "测试对话")
        check("创建会话", db.conversations(novelID: novel.id).count == 1)

        let ch1 = db.createChapter(novelID: novel.id, title: "第一章", content: "林晚舟站在星海城的城墙上。")
        let ch2 = db.createChapter(novelID: novel.id, title: "第二章", content: "霜河在月光下泛着寒光。")
        check("创建章节", db.chapters(novelID: novel.id).count == 2)

        // 2. 会话内消息隔离
        db.addMessage(novelID: novel.id, conversationID: conv.id, role: "user", content: "你好", skill: "chat")
        let conv2 = db.createConversation(novelID: novel.id, title: "第二对话")
        db.addMessage(novelID: novel.id, conversationID: conv2.id, role: "user", content: "另一个对话", skill: "chat")
        let m1 = db.messages(novelID: novel.id, conversationID: conv.id)
        let m2 = db.messages(novelID: novel.id, conversationID: conv2.id)
        check("会话消息隔离", m1.count == 1 && m2.count == 1 && m1[0].content == "你好" && m2[0].content == "另一个对话")
        check("会话排序按更新时间", db.conversations(novelID: novel.id).first?.id == conv2.id)

        // 3. 中文搜索
        let r1 = db.search("霜河", novelID: novel.id)
        check("搜索「霜河」(2字)", !r1.entries.isEmpty || !r1.chapters.isEmpty)
        let r2 = db.search("星海城", novelID: novel.id)
        check("搜索「星海城」(3字FTS)", !r2.chapters.isEmpty)

        // 4. 世界书激活
        let activated = activateLorebook(entries: [entry], scanText: "她说：霜河出鞘。")
        check("世界书关键词触发", activated.count == 1)
        let pinned = Entry(id: UUID(), novelID: novel.id, type: "world", title: "力量体系", content: "灵气九阶",
                           keywords: "", pinned: true, createdAt: Date(), updatedAt: Date())
        check("固定引用始终激活", activateLorebook(entries: [pinned], scanText: "随便聊聊").count == 1)

        // 5. 上下文预算与组装
        let ctx = GenContext(novel: novel, chapters: [ch1, ch2], entries: [entry, pinned],
                             history: [], userText: "继续写", targetText: "", skill: skillByID("continue"))
        let req = buildRequest(ctx: ctx)
        check("系统提示含设定", req.system.contains("林晚舟"))
        check("系统提示含前文", req.system.contains("第一章"))
        check("预算统计正确", req.plan.loreCount == 2 && req.plan.chapterCount == 2 && req.plan.totalTokens > 0,
              "tokens=\(req.plan.totalTokens)")
        check("预算不含历史", req.plan.historyCount == 0)
        let chatCtx = GenContext(novel: novel, chapters: [], entries: [],
                                 history: m1 + m2, userText: "hi", targetText: "", skill: skillByID("chat"))
        let req2 = buildRequest(ctx: chatCtx)
        check("对话注入历史", req2.plan.historyCount == 2 && req2.messages.count == 3)
        check("普通对话不覆盖 Agent", skillByID("chat").system.isEmpty)
        check("未知技能安全回退普通对话", skillByID("missing-skill").id == "chat")
        let fixedContext = GenContext(novel: novel, chapters: [], entries: [], history: m1 + m2,
                                      userText: "继续讨论", targetText: "", skill: skillByID("chat"),
                                      fixedSkill: skillByID("scene"), indexedSkills: [skillByID("outline")])
        let fixedRequest = buildRequest(ctx: fixedContext)
        check("固定 Skill 每轮注入且保留对话历史",
              fixedRequest.system.contains("Agent 固定 Skill：场景创作") && fixedRequest.plan.historyCount == 2)
        check("按需 Skill 只注入索引不注入正文",
              fixedRequest.system.contains("outline｜生成大纲")
                && !fixedRequest.system.contains("核心创意（一句话）"))
        let loadedOnDemand = AppState.indexedSkillResult(
            ToolCall(id: "skill-load", name: "get_skill", arguments: "{\"skill_id\":\"outline\"}"),
            skills: [skillByID("outline")]
        ) ?? ""
        check("Agent 可按索引自行调取 Skill", loadedOnDemand.contains("核心创意（一句话）"))
        check("中文 token 使用保守估算", estimateTokens(String(repeating: "中", count: 100)) >= 100)

        let redundant = String(repeating: "天气平静，众人继续赶路，没有发生新的事情。", count: 80)
        let compressionSample = "【本书硬规则（必须遵守）】林晚舟不能使用火系法术。\n"
            + "【故事框架】\n"
            + redundant
            + "\n关键伏笔：霜河剑柄中藏着星海城失踪王族的血印。\n"
            + redundant
        let compressed = NovelContextCompressor.compress(
            compressionSample,
            query: "霜河 星海城 王族 血印",
            maxTokens: 420,
            level: .balanced
        )
        check("上下文压缩减少 tokens", compressed.finalTokens < compressed.originalTokens,
              "\(compressed.originalTokens) → \(compressed.finalTokens)")
        check("压缩保留硬规则", compressed.text.contains("不能使用火系法术"))
        check("压缩保留查询相关伏笔", compressed.text.contains("失踪王族的血印"))

        let protectedStress = "【当前 1–3 章聚焦（高于卷纲）】\n"
            + String(repeating: "无论预算多小，这段聚焦内容都不能被静默裁掉。", count: 80)
            + "\n【故事框架】\n" + redundant
        let protectedResult = NovelContextCompressor.compress(
            protectedStress, query: "无关查询", maxTokens: 120, level: .aggressive
        )
        let protectedOccurrences = protectedResult.text.components(separatedBy: "无论预算多小，这段聚焦内容都不能被静默裁掉。").count - 1
        check("受保护章节跨分段完整保留", protectedOccurrences == 80,
              "保留 \(protectedOccurrences)/80 段")
        check("受保护内容超预算会明确报告", protectedResult.protectedContentExceededBudget
              && protectedResult.finalTokens > 120)

        let orderedSample = "起点标记。" + redundant
            + "关键甲：霜河血印第一次出现。" + redundant
            + "关键乙：王族身份随后揭晓。" + redundant + "终点标记。"
        let orderedResult = NovelContextCompressor.compress(
            orderedSample, query: "霜河 血印 王族 身份", maxTokens: 360, level: .balanced
        )
        let keyA = orderedResult.text.range(of: "关键甲")
        let keyB = orderedResult.text.range(of: "关键乙")
        check("相关片段保持原始叙事顺序", keyA != nil && keyB != nil && keyA!.lowerBound < keyB!.lowerBound)

        let variedContext = (0..<360).map { index in
            "旅队第\(index)日抵达区域\(index)，发现编号\(index)的独立线索并记录人物反应。"
        }.joined()
        let longNovel = Novel(id: UUID(), title: "压缩率测试", desc: variedContext,
                              outline: "", createdAt: Date(), updatedAt: Date())
        let rateCtx = GenContext(novel: longNovel, chapters: [], entries: [], history: [],
                                 userText: "找出真正有变化的内容", targetText: "", skill: skillByID("inspire"))
        let uncompressedRate = buildRequest(ctx: rateCtx, tokenBudget: 1_000_000,
                                            compressionLevel: .custom, compressionTargetRetention: 0.70)
        let rateWindow = max(1, Int(Double(uncompressedRate.plan.originalTokens) / 0.85))
        let lightRate = buildRequest(ctx: rateCtx, tokenBudget: rateWindow,
                                     compressionLevel: .custom, compressionTargetRetention: 0.70)
        let strongRate = buildRequest(ctx: rateCtx, tokenBudget: rateWindow,
                                      compressionLevel: .custom, compressionTargetRetention: 0.30)
        check("达到输入窗口 80% 自动触发", lightRate.plan.compressionApplied,
              "占用约 \(uncompressedRate.plan.originalTokens * 100 / rateWindow)%")
        check("自定义百分比确实改变压缩目标", strongRate.plan.totalTokens < lightRate.plan.totalTokens,
              "保留70%=\(lightRate.plan.totalTokens)，保留30%=\(strongRate.plan.totalTokens)")

        let historyMessages = (0..<12).map { index in
            Msg(id: UUID(), novelID: longNovel.id, conversationID: UUID(), role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "最近消息编号\(index)：" + String(repeating: "对话细节。", count: 80), skill: "chat", createdAt: Date())
        }
        let historyCtx = GenContext(novel: longNovel, chapters: [], entries: [], history: historyMessages,
                                    userText: "继续", targetText: "", skill: skillByID("chat"))
        let historyRequest = buildRequest(ctx: historyCtx, tokenBudget: 2_000,
                                          compressionLevel: .aggressive)
        let recentContents = Set(historyRequest.messages.map(\.content))
        check("最近 8 条对话逐条原样保留", historyMessages.suffix(8).allSatisfy { recentContents.contains($0.content) })

        let exactlyEightLong = Array(historyMessages.suffix(8)).map { message in
            Msg(id: message.id, novelID: message.novelID, conversationID: message.conversationID,
                role: message.role, content: String(repeating: "极长最近对话。", count: 900),
                skill: message.skill, createdAt: message.createdAt)
        }
        let eightLongCtx = GenContext(novel: novel, chapters: [], entries: [], history: exactlyEightLong,
                                      userText: "继续", targetText: "", skill: skillByID("chat"))
        let eightLongRequest = buildRequest(ctx: eightLongCtx, tokenBudget: 2_000,
                                            compressionLevel: .aggressive)
        check("最近 8 条本身超限时阻止请求", eightLongRequest.plan.requestExceedsInputBudget)

        let oversizedInputCtx = GenContext(novel: novel, chapters: [], entries: [], history: [],
                                           userText: String(repeating: "用户粘贴的超长原文。", count: 1200),
                                           targetText: "", skill: skillByID("chat"))
        let oversizedInputRequest = buildRequest(ctx: oversizedInputCtx, tokenBudget: 2_000,
                                                 compressionLevel: .balanced)
        check("当前用户输入不可压缩且超限时阻止请求", oversizedInputRequest.plan.requestExceedsInputBudget)

        let criticalEnding = "唯一衔接句：林晚舟在关门前把霜河交给了顾沉。"
        let longChapter = Chapter(id: UUID(), novelID: novel.id, no: 99, title: "临界章节",
                                  content: redundant + criticalEnding,
                                  createdAt: Date(), updatedAt: Date())
        let endingCtx = GenContext(novel: novel, chapters: [longChapter], entries: [], history: [],
                                   userText: "续写下一幕", targetText: "", skill: skillByID("continue"))
        let endingRequest = buildRequest(ctx: endingCtx, tokenBudget: 600,
                                         compressionLevel: .aggressive)
        check("最新章节结尾在极端压缩下强制保留", endingRequest.system.contains(criticalEnding))

        let nonChatWithHistory = GenContext(novel: novel, chapters: [], entries: [], history: historyMessages,
                                            userText: "续写", targetText: "", skill: skillByID("continue"))
        let nonChatWithoutHistory = GenContext(novel: novel, chapters: [], entries: [], history: [],
                                               userText: "续写", targetText: "", skill: skillByID("continue"))
        check("非对话任务统计不混入未发送历史",
              buildRequest(ctx: nonChatWithHistory).plan.originalTokens
                == buildRequest(ctx: nonChatWithoutHistory).plan.originalTokens)

        // 6. Agent 存储
        let agent = Agent(id: UUID(), name: "测试Agent", icon: "sparkles",
                          systemPrompt: "你是测试人格。", temperature: 0.5,
                          skills: [], fixedSkillID: "scene", isBuiltin: false)
        check("技能库自动更新 Agent 索引",
              indexedSkills(for: agent, skills: ALL_SKILLS).contains { $0.id == "outline" })
        AgentStore.save([agent])
        let loaded = AgentStore.load()
        check("Agent 保存/加载", loaded.contains {
            $0.id == agent.id && $0.systemPrompt == "你是测试人格。" && $0.fixedSkillID == "scene"
        })
        var autoSchedule = ModelConfig()
        autoSchedule.provider = "custom"
        check("多任务默认自动规划", autoSchedule.automaticBackgroundScheduling
              && autoSchedule.plannedConversationCorePercent > 0
              && autoSchedule.plannedConversationMemoryMB >= 128)
        let ordinaryTaskMemory = autoSchedule.estimatedBackgroundTaskMemoryMB
        autoSchedule.contextWindow = 4_000_000
        check("超大上下文提高单任务内存预留", autoSchedule.estimatedBackgroundTaskMemoryMB > ordinaryTaskMemory)

        // 7. 本地向量库 TXT 解析与检索（传入真实文件时校验章节格式）
        if let path = ProcessInfo.processInfo.environment["AINOVEL_VECTOR_TEST_TXT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            do {
                let parsed = try NovelTextParser.parse(url: url)
                check("TXT 章节解析", parsed.chapters.count == 346 && parsed.chapters.first?.no == 1 && parsed.chapters.last?.no == 346,
                      "解析到 \(parsed.chapters.count) 章")
                let vectorStore = VectorStore()
                let library = try vectorStore.importTXT(url: url, expectedChapterCount: 346)
                check("向量库分块入库", library.chunkCount >= 346, "\(library.chunkCount) 个片段")
                let vectorChapters = vectorStore.chapters(libraryID: library.id)
                check("向量库完整章节容器", vectorChapters.count == 346 && vectorChapters.first?.content.isEmpty == false)
                if let first = vectorChapters.first {
                    let edited = vectorStore.updateChapter(first, title: first.title + "（测试）", content: first.content + "\n测试编辑。")
                    let reloaded = vectorStore.chapters(libraryID: library.id).first
                    check("章节编辑并重建向量", edited != nil && reloaded?.title.hasSuffix("（测试）") == true && reloaded?.content.hasSuffix("测试编辑。") == true)
                }
                let hits = vectorStore.search(libraryID: library.id, queryText: "地下城 格雷格")
                check("向量检索", !hits.isEmpty && hits.first?.chapterNo == 1)
                vectorStore.delete(library)
            } catch {
                check("TXT 向量库", false, error.localizedDescription)
            }
        }

        // 7.5 完整写作工具链
        let app = AppState()
        check("启动进入公共会话", app.currentNovelID == nil && app.currentConversationID != nil)
        check("未选书状态使用一次性事件", app.messages.filter { $0.role == "event" }.count == 1
              && app.messages.first?.content.contains("未选择任何书籍") == true)
        check("公共会话内部记录不进入书库", !db.novels().contains { $0.id == GLOBAL_CHAT_NOVEL_ID })
        let freeContext = GenContext(
            novel: Novel(id: GLOBAL_CHAT_NOVEL_ID, title: "", desc: "", outline: "",
                         createdAt: Date(), updatedAt: Date()),
            chapters: [], entries: [], history: app.messages,
            userText: "我没有灵感", targetText: "", skill: skillByID("chat")
        )
        let freeRequest = buildRequest(ctx: freeContext)
        check("公共会话事件会通知模型", freeRequest.messages.contains { $0.content.contains("【系统状态事件】") })
        app.selectNovel(novel.id)
        let toolNames = AppState.writingTools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        check("工具总数", AppState.writingTools.count == 82, "\(AppState.writingTools.count) 个")
        check("工具名称唯一", Set(toolNames).count == toolNames.count)
        check("工具 Schema 可序列化", JSONSerialization.isValidJSONObject(AppState.writingTools))
        let rootLoaders = ToolGroups.loaderDefinitions(for: ToolGroups.visibleNodes(parentID: nil, allowedNames: nil))
        check("梯形首轮仅根域", rootLoaders.count == 4)
        let mappedToolNames = Set(ToolGroups.roots.flatMap { ToolGroups.descendantToolNames(of: $0.id) })
        check("全部详细工具均有梯形路径", mappedToolNames == Set(toolNames), "已映射 \(mappedToolNames.count)/\(toolNames.count)")
        let chapterChildren = ToolGroups.visibleNodes(parentID: "content.chapters", allowedNames: nil)
        check("梯形章节操作分叶", chapterChildren.count == 5 && chapterChildren.allSatisfy(\.isLeaf))
        let patchLeaf = chapterChildren.first { $0.id == "content.chapters.patch" }!
        let patchDefinitions = ToolGroups.detailedDefinitions(for: patchLeaf, allDefinitions: AppState.writingTools, allowedNames: nil)
        check("叶子只注入所需详细工具", patchDefinitions.count == 1 && ((patchDefinitions[0]["function"] as? [String: Any])?["name"] as? String) == "replace_chapter_text")
        let readOnlyRoots = ToolGroups.visibleNodes(parentID: nil, allowedNames: ["read_chapter"])
        check("Agent 白名单裁剪目录", readOnlyRoots.map(\.id) == ["content"])
        let toolSchemaTokens = AppState.estimatedToolDefinitionTokens(AppState.writingTools)
        check("工具定义计入输入预算", toolSchemaTokens > 0, "约 \(toolSchemaTokens) tokens")
        let hugeToolResult = String(repeating: "工具读取到的长篇正文。", count: 1200)
        let roundMessages = [
            ChatMsg(role: "user", content: "读取资料"),
            ChatMsg(role: "assistant", content: "", toolCalls: [
                ToolCall(id: "round-tool", name: "read_chapter", arguments: "{\"number\":1}")
            ]),
            ChatMsg(role: "tool", content: hugeToolResult, toolCallID: "round-tool")
        ]
        let fittedToolRound = AppState.fitToolRoundMessages(
            roundMessages, system: "写作助手", toolDefinitionTokens: 200,
            inputBudget: 4_000, query: "读取资料", compressionLevel: .balanced
        )
        check("工具结果进入下一轮前重新压缩",
              fittedToolRound.fits && fittedToolRound.totalTokens <= 3_840
                && (fittedToolRound.messages.last?.content.count ?? 0) < hugeToolResult.count,
              "压缩后约 \(fittedToolRound.totalTokens) tokens")
        let tc1 = ToolCall(id: "t1", name: "read_chapter", arguments: "{\"number\":1}")
        check("工具 read_chapter", AppState.executeTool(tc1, app: app).contains("第一章"))
        let tc2 = ToolCall(id: "t2", name: "list_chapters", arguments: "{}")
        check("工具 list_chapters", AppState.executeTool(tc2, app: app).contains("第二章"))
        let tc3 = ToolCall(id: "t3", name: "search_database", arguments: "{\"query\":\"霜河\"}")
        check("工具 search_database", AppState.executeTool(tc3, app: app).contains("林晚舟"))
        let longContent = String(repeating: "分页正文段落。", count: 1800)
        db.updateChapter(id: ch2.id, content: longContent)
        let pagedRead = AppState.executeTool(ToolCall(id: "page1", name: "read_chapter",
                                                      arguments: "{\"book_id\":\"\(novel.id.uuidString)\",\"number\":2,\"offset\":6000,\"limit\":2000}"), app: app)
        check("长章节支持游标分页", pagedRead.contains("字符范围：6000") && pagedRead.contains("next_offset:"))
        let isolatedWrite = ToolCall(id: "lock1", name: "update_chapter",
                                     arguments: "{\"book_id\":\"\(novel.id.uuidString)\",\"number\":1,\"content\":\"会话隔离追加。\",\"content_mode\":\"append\"}")
        let firstWrite = app.executeConversationIsolatedTool(isolatedWrite, conversationID: conv.id, novelID: novel.id)
        let conflictingWrite = app.executeConversationIsolatedTool(isolatedWrite, conversationID: conv2.id, novelID: novel.id)
        check("跨会话写工具资源隔离", firstWrite.contains("已更新") && conflictingWrite.contains("资源冲突")
              && conflictingWrite.contains(conv.id.uuidString))
        app.releaseConversationResources(conv.id)
        let retriedWrite = app.executeConversationIsolatedTool(isolatedWrite, conversationID: conv2.id, novelID: novel.id)
        check("占用会话结束后可重试", retriedWrite.contains("已更新"))
        app.releaseConversationResources(conv2.id)

        let createBook = ToolCall(id: "w1", name: "create_book",
                                  arguments: "{\"title\":\"工具测试书\",\"description\":\"简介\",\"outline\":\"测试大纲\"}")
        check("工具创建书籍", AppState.executeTool(createBook, app: app).contains("已创建书籍"))
        guard let toolBook = app.novels.first(where: { $0.title == "工具测试书" }) else {
            check("定位工具测试书", false)
            exit(1)
        }
        let bid = toolBook.id.uuidString
        let batch = ToolCall(id: "w2", name: "batch_create_chapters",
                             arguments: "{\"book_id\":\"\(bid)\",\"chapters\":[{\"title\":\"开端\",\"content\":\"甲界标记。分割点后半段。\"},{\"title\":\"发展\",\"content\":\"第二章正文。\"}]}")
        check("工具批量写章", AppState.executeTool(batch, app: app).contains("批量创建 2 章"))
        let append = ToolCall(id: "w3", name: "update_chapter",
                              arguments: "{\"book_id\":\"\(bid)\",\"number\":1,\"content\":\"追加内容。\",\"content_mode\":\"append\"}")
        _ = AppState.executeTool(append, app: app)
        check("工具追加正文", db.chapters(novelID: toolBook.id).first?.content.hasSuffix("追加内容。") == true)
        let replace = ToolCall(id: "w4", name: "replace_chapter_text",
                               arguments: "{\"book_id\":\"\(bid)\",\"number\":1,\"old_text\":\"甲界标记\",\"new_text\":\"新世界标记\"}")
        check("工具局部改文", AppState.executeTool(replace, app: app).contains("已局部修改"))
        let split = ToolCall(id: "w5", name: "split_chapter",
                             arguments: "{\"book_id\":\"\(bid)\",\"number\":1,\"split_text\":\"分割点\",\"second_title\":\"承接\"}")
        check("工具拆分章节", AppState.executeTool(split, app: app).contains("已将第 1 章拆分"))
        let merge = ToolCall(id: "w6", name: "merge_chapters",
                             arguments: "{\"book_id\":\"\(bid)\",\"first_number\":1,\"second_number\":2,\"expected_first_title\":\"开端\",\"expected_second_title\":\"承接\"}")
        check("工具合并章节", AppState.executeTool(merge, app: app).contains("已将第 2 章"))

        let lore = ToolCall(id: "w7", name: "create_lore_entry",
                            arguments: "{\"book_id\":\"\(bid)\",\"type\":\"character\",\"title\":\"测试人物\",\"content\":\"人物设定\",\"keywords\":\"测试\"}")
        check("工具创建设定", AppState.executeTool(lore, app: app).contains("已创建设定"))
        let toolEntry = db.entries(novelID: toolBook.id).first!
        let updateLore = ToolCall(id: "w8", name: "update_lore_entry",
                                  arguments: "{\"entry_id\":\"\(toolEntry.id.uuidString)\",\"content\":\"更新后设定\",\"pinned\":true}")
        _ = AppState.executeTool(updateLore, app: app)
        check("工具修改设定", db.entries(novelID: toolBook.id).first?.content == "更新后设定")
        let deleteLore = ToolCall(id: "w9", name: "delete_lore_entry",
                                  arguments: "{\"entry_id\":\"\(toolEntry.id.uuidString)\",\"expected_title\":\"测试人物\"}")
        check("工具删除设定", AppState.executeTool(deleteLore, app: app).contains("已删除设定"))
        let deleteBook = ToolCall(id: "w10", name: "delete_book",
                                  arguments: "{\"book_id\":\"\(bid)\",\"expected_title\":\"工具测试书\"}")
        check("工具删除书籍", AppState.executeTool(deleteBook, app: app).contains("已删除书籍"))
        check("删除书籍级联清理", db.chapters(novelID: toolBook.id).isEmpty && db.entries(novelID: toolBook.id).isEmpty)

        check("工具读取工作区状态", AppState.executeTool(ToolCall(id: "x1", name: "get_workspace_state", arguments: "{}"), app: app).contains("工作区："))
        check("跨会话工具完整", ["list_all_conversations", "send_message_to_conversation", "get_conversation_run", "wait_conversations", "cancel_conversation_run"].allSatisfy(toolNames.contains))
        check("治理与边界工具完整", ["describe_tool_domains", "get_workspace_schema", "get_tool_boundaries", "get_permission_scope", "get_tool_coverage", "list_resource_locks"].allSatisfy(toolNames.contains))
        check("模型可查询工具边界", AppState.executeTool(ToolCall(id: "gov1", name: "get_tool_boundaries", arguments: "{}"), app: app).contains("任意文件系统"))

        let metadataUpdate = ToolCall(id: "meta1", name: "update_book",
                                      arguments: "{\"book_id\":\"\(novel.id.uuidString)\",\"authors\":[\"测试作者\"],\"genres\":[\"奇幻\"],\"author_intent\":\"验证完整元数据\",\"target_chapters\":88,\"point_of_view\":\"第三人称\"}")
        _ = AppState.executeTool(metadataUpdate, app: app)
        let metadataBook = db.novels().first { $0.id == novel.id }
        check("工具覆盖完整书籍元数据", metadataBook?.metadata.authors == ["测试作者"]
              && metadataBook?.metadata.targetChapters == 88 && metadataBook?.metadata.pointOfView == "第三人称")

        let legacyCharacter = db.createStoryNode(novelID: novel.id, kind: "character_design",
                                                  title: "迁移人物", content: "旧人物卡内容")
        db.migrateOverlappingStoryNodesIntoLore()
        check("重叠人物卡迁入设定库", db.entries(novelID: novel.id).contains {
            $0.type == "character" && $0.title == "迁移人物" && $0.content == "旧人物卡内容"
        })
        check("迁移后不保留重复数据源", !db.storyNodes(novelID: novel.id).contains { $0.id == legacyCharacter.id })
        check("迁移保留可追溯版本", db.revisions(novelID: novel.id, resourceType: "story_node",
                                              resourceID: legacyCharacter.id.uuidString).contains { $0.operation == "migrated_to_lore" })
        check("规划卡类型不再包含设定实体", ["character_design", "world_rule", "location_design",
                                             "faction_design", "item_design", "history_event", "power_system"]
            .allSatisfy { !GovernanceTools.storyKinds.contains($0) })

        let storyCreate = ToolCall(id: "story1", name: "create_story_node",
                                   arguments: "{\"book_id\":\"\(novel.id.uuidString)\",\"kind\":\"foreshadow\",\"title\":\"血印伏笔\",\"content\":\"第一章埋下\",\"status\":\"active\"}")
        let storyCreated = app.executeConversationIsolatedTool(storyCreate, conversationID: conv.id, novelID: novel.id)
        guard let storyNode = db.storyNodes(novelID: novel.id).first(where: { $0.title == "血印伏笔" }) else {
            check("创建创作结构对象", false, storyCreated); exit(1)
        }
        let storyUpdate = ToolCall(id: "story2", name: "update_story_node",
                                   arguments: "{\"node_id\":\"\(storyNode.id.uuidString)\",\"content\":\"第三章回收\",\"status\":\"resolved\"}")
        _ = app.executeConversationIsolatedTool(storyUpdate, conversationID: conv.id, novelID: novel.id)
        app.releaseConversationResources(conv.id)
        check("多类书籍创作卡片 CRUD", STORY_NODE_KINDS.count >= 25
              && db.storyNodes(novelID: novel.id).first(where: { $0.id == storyNode.id })?.status == "resolved")
        check("结构修改自动生成版本", db.revisions(novelID: novel.id, resourceType: "story_node", resourceID: storyNode.id.uuidString).isEmpty == false)
        if let revision = db.revisions(novelID: novel.id, resourceType: "story_node", resourceID: storyNode.id.uuidString).first {
            let restore = ToolCall(id: "story-restore", name: "restore_content_revision",
                                   arguments: "{\"revision_id\":\"\(revision.id.uuidString)\",\"expected_resource_id\":\"\(storyNode.id.uuidString)\"}")
            let restored = app.executeConversationIsolatedTool(restore, conversationID: conv2.id, novelID: novel.id)
            app.releaseConversationResources(conv2.id)
            check("创作结构版本可恢复", restored.contains("已恢复版本")
                  && db.storyNodes(novelID: novel.id).first(where: { $0.id == storyNode.id })?.status == "active")
        } else { check("创作结构版本可恢复", false) }

        let createConversation = ToolCall(id: "x2", name: "create_conversation",
                                          arguments: "{\"book_id\":\"\(novel.id.uuidString)\",\"title\":\"工具会话\"}")
        check("工具创建会话", AppState.executeTool(createConversation, app: app).contains("已创建会话"))
        let toolConversation = db.conversations(novelID: novel.id).first { $0.title == "工具会话" }!
        _ = db.addMessage(novelID: novel.id, conversationID: toolConversation.id, role: "user", content: "测试消息")
        let readConversation = ToolCall(id: "x3", name: "read_conversation",
                                        arguments: "{\"conversation_id\":\"\(toolConversation.id.uuidString)\"}")
        check("工具读取会话", AppState.executeTool(readConversation, app: app).contains("测试消息"))
        let deleteConversation = ToolCall(id: "x4", name: "delete_conversation",
                                          arguments: "{\"conversation_id\":\"\(toolConversation.id.uuidString)\",\"expected_title\":\"工具会话\"}")
        check("工具删除会话", AppState.executeTool(deleteConversation, app: app).contains("已删除会话"))

        let createAgent = ToolCall(id: "x5", name: "create_agent",
                                   arguments: "{\"name\":\"工具Agent\",\"icon\":\"🧪\",\"system_prompt\":\"测试系统提示词\",\"tools\":[\"read_chapter\"]}")
        check("工具创建 Agent", AppState.executeTool(createAgent, app: app).contains("已创建 Agent"))
        let toolAgent = app.agents.first { $0.name == "工具Agent" }!
        let updateAgent = ToolCall(id: "x6", name: "update_agent",
                                   arguments: "{\"agent_id\":\"\(toolAgent.id.uuidString)\",\"system_prompt\":\"已更新提示词\"}")
        check("工具修改 Agent", AppState.executeTool(updateAgent, app: app).contains("已更新 Agent"))
        let deleteAgent = ToolCall(id: "x7", name: "delete_agent",
                                   arguments: "{\"agent_id\":\"\(toolAgent.id.uuidString)\",\"expected_name\":\"工具Agent\"}")
        check("工具删除 Agent", AppState.executeTool(deleteAgent, app: app).contains("已删除 Agent"))

        let droppedSkillURL = AppPaths.dataDir.appendingPathComponent("拖入技能.md")
        let droppedSkillMarkdown = """
        ---
        name: 拖入测试技能
        description: 验证文件拖放导入
        category: 创作
        icon: doc.text
        ---

        严格执行拖入文件中的写作指令。
        """
        try? droppedSkillMarkdown.write(to: droppedSkillURL, atomically: true, encoding: .utf8)
        do {
            let firstImport = try SkillStore.importFile(droppedSkillURL)
            let secondImport = try SkillStore.importFile(droppedSkillURL)
            check("拖入 Markdown Skill", firstImport.name == "拖入测试技能" && firstImport.fileURL != nil)
            check("同名 Skill 导入不覆盖", firstImport.id != secondImport.id
                  && FileManager.default.fileExists(atPath: firstImport.fileURL?.path ?? "")
                  && FileManager.default.fileExists(atPath: secondImport.fileURL?.path ?? ""))
            try? SkillStore.delete(firstImport)
            try? SkillStore.delete(secondImport)
        } catch {
            check("拖入 Markdown Skill", false, error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: droppedSkillURL)

        let createSkill = ToolCall(id: "x8", name: "create_skill",
                                   arguments: "{\"name\":\"工具技能\",\"description\":\"测试\",\"category\":\"write\",\"markdown\":\"执行测试写作任务。\"}")
        check("工具创建 Skill", AppState.executeTool(createSkill, app: app).contains("已保存 Markdown Skill"))
        let toolSkill = app.skills.first { $0.name == "工具技能" }!
        let updateSkill = ToolCall(id: "x9", name: "update_skill",
                                   arguments: "{\"skill_id\":\"\(toolSkill.id)\",\"markdown\":\"执行更新后的写作任务。\"}")
        check("工具修改 Skill", AppState.executeTool(updateSkill, app: app).contains("已保存 Markdown Skill"))
        let deleteSkill = ToolCall(id: "x10", name: "delete_skill",
                                   arguments: "{\"skill_id\":\"\(toolSkill.id)\",\"expected_name\":\"工具技能\"}")
        check("工具删除 Skill", AppState.executeTool(deleteSkill, app: app).contains("已删除 Markdown Skill"))

        let vectorTXT = GovernanceTools.importsDirectory.appendingPathComponent("tool-vector.txt")
        try? "书名：工具向量书\n作者：测试者\n————————————————\n第 1 章 开端\n星海城的霜河剑在月下发光。\n第 2 章 发展\n林晚舟继续前行。".write(to: vectorTXT, atomically: true, encoding: .utf8)
        let importVector = ToolCall(id: "x11", name: "import_vector_txt",
                                    arguments: "{\"path\":\"\(vectorTXT.path)\",\"expected_chapter_count\":2}")
        check("工具导入向量库", AppState.executeTool(importVector, app: app).contains("已导入写法向量库"))
        let deniedImport = ToolCall(id: "x11-denied", name: "import_vector_txt", arguments: "{\"path\":\"/tmp/not-authorized.txt\"}")
        check("工具拒绝任意文件路径", AppState.executeTool(deniedImport, app: app).contains("Imports 授权目录"))
        let toolLibrary = VectorStore().libraries().first { $0.title == "工具向量书" }!
        let vectorSearch = ToolCall(id: "x12", name: "search_vector_library",
                                    arguments: "{\"library_id\":\"\(toolLibrary.id.uuidString)\",\"query\":\"霜河剑\"}")
        check("工具检索向量库", AppState.executeTool(vectorSearch, app: app).contains("第1章"))
        let deleteVector = ToolCall(id: "x13", name: "delete_vector_library",
                                    arguments: "{\"library_id\":\"\(toolLibrary.id.uuidString)\",\"expected_title\":\"工具向量书\"}")
        check("工具删除向量库", AppState.executeTool(deleteVector, app: app).contains("已删除向量库"))

        let exportBook = ToolCall(id: "x14", name: "export_book_file",
                                  arguments: "{\"book_id\":\"\(novel.id.uuidString)\"}")
        let exportResult = AppState.executeTool(exportBook, app: app)
        check("工具导出书籍文件", exportResult.contains("已导出"))
        let exportedURL = ((try? FileManager.default.contentsOfDirectory(at: AppPaths.dataDir.appendingPathComponent("Exports"), includingPropertiesForKeys: nil)) ?? []).first!
        let importBook = ToolCall(id: "x15", name: "import_book_file", arguments: "{\"path\":\"\(exportedURL.path)\"}")
        check("工具导入书籍文件", AppState.executeTool(importBook, app: app).contains("已导入"))
        let importedNovel = app.novels.first { $0.id != novel.id && $0.title == novel.title }!
        db.deleteNovel(id: importedNovel.id); app.novels.removeAll { $0.id == importedNovel.id }
        let deleteExport = ToolCall(id: "x16", name: "delete_exported_file",
                                    arguments: "{\"filename\":\"\(exportedURL.lastPathComponent)\",\"expected_filename\":\"\(exportedURL.lastPathComponent)\"}")
        check("工具删除导出文件", AppState.executeTool(deleteExport, app: app).contains("已删除导出文件"))

        let preferences = ToolCall(id: "x17", name: "update_workspace_preferences",
                                   arguments: "{\"context_window\":65536,\"compression_level\":\"aggressive\",\"theme_hue\":0.42,\"automatic_background_scheduling\":false,\"conversation_core_percent\":50,\"conversation_memory_mb\":256}")
        check("工具修改工作区偏好", AppState.executeTool(preferences, app: app).contains("已更新工作区偏好")
              && app.config.contextWindow == 65536
              && app.config.plannedConversationCorePercent == 50
              && app.config.plannedConversationMemoryMB == 256)

        let readableLimitError = LLM.userFacingAPIError(
            status: 400,
            body: #"{"type":"error","error":{"type":"bad_request_error","message":"invalid params, model[MiniMax-M2.7] does not support max tokens > 196608 (2013)"}}"#,
            model: "MiniMax-M2.7"
        )
        check("厂商 JSON 错误转为中文提示",
              readableLimitError.contains("输出上限设置过高")
                && readableLimitError.contains("196,608")
                && !readableLimitError.contains("bad_request_error"))
        check("认证错误给出处理建议",
              LLM.userFacingAPIError(status: 401, body: "invalid api key", model: "测试模型")
                .contains("请检查"))

        // 8. LLM 流式（需 mock）
        guard let base = ProcessInfo.processInfo.environment["AINOVEL_TEST_BASEURL"], !base.isEmpty else {
            print("⚠️ 未设置 AINOVEL_TEST_BASEURL，跳过 LLM 流式测试")
            print(failed == 0 ? "\n全部通过 ✅" : "\n\(failed) 项失败 ❌")
            exit(failed == 0 ? 0 : 1)
        }
        var cfg = ModelConfig()
        cfg.provider = "custom"
        cfg.baseURL = base
        cfg.apiKey = "test"
        cfg.model = "mock"
        cfg.temperature = 0.7
        cfg.maxTokens = 512
        var got = ""
        do {
            let result = try await LLM.streamChat(config: cfg, system: "测试",
                                                  messages: [ChatMsg(role: "user", content: "你好")],
                                                  temperature: 0.9, tools: rootLoaders) { d in
                got += d
            }
            check("LLM 流式输出(温度覆盖)", got.count >= 5 && result.text == got, "收到 \(got.count) 字符")
            check("无工具调用返回", result.toolCalls.isEmpty)
        } catch {
            check("LLM 流式输出", false, error.localizedDescription)
        }

        // 9. 跨会话后台执行：不依赖当前 UI 选中的会话，并将最终状态与消息落库。
        app.config = cfg
        let backgroundConversation = db.createConversation(novelID: novel.id, title: "后台任务会话")
        let dispatchCall = ToolCall(id: "bg1", name: "send_message_to_conversation",
                                    arguments: "{\"conversation_id\":\"\(backgroundConversation.id.uuidString)\",\"prompt\":\"后台写一小段测试文本\"}")
        let dispatchResult = AppState.executeTool(dispatchCall, app: app)
        check("跨会话派发后台任务", dispatchResult.contains("status: queued"), dispatchResult)
        let waited = await app.waitForConversationRuns([backgroundConversation.id], timeoutSeconds: 5)
        let persistedRun = db.conversationRuns().first { $0.conversationID == backgroundConversation.id }
        let backgroundMessages = db.messages(novelID: novel.id, conversationID: backgroundConversation.id)
        check("跨会话等待并完成", waited.contains("status: completed") && persistedRun?.status == "completed", waited)
        check("后台会话独立写入历史", backgroundMessages.contains { $0.role == "user" }
              && backgroundMessages.contains { $0.role == "assistant" })
        let interruptedConversation = db.createConversation(novelID: novel.id, title: "中断恢复测试")
        db.saveConversationRun(ConversationRun(conversationID: interruptedConversation.id, novelID: novel.id,
                                               status: "running", prompt: "未完成任务", agentID: nil,
                                               skillID: "chat", partialText: "部分输出", error: "",
                                               reservedCorePercent: 25, reservedMemoryMB: 128,
                                               startedAt: Date(), updatedAt: Date()))
        db.recoverInterruptedConversationRuns()
        let recovered = db.conversationRuns().first { $0.conversationID == interruptedConversation.id }
        check("重启后不伪装任务仍在运行", recovered?.status == "failed" && recovered?.error.contains("应用重启") == true)

        let tc4 = ToolCall(id: "t4", name: "read_chapter", arguments: "{\"number\":99}")
        check("工具错误处理", AppState.executeTool(tc4, app: app).contains("不存在"))
        do {
            let reply = try await LLM.testConnection(config: cfg)
            check("连接测试", reply.contains("连接成功"), reply)
        } catch {
            check("连接测试", false, error.localizedDescription)
        }

        // 8. 清理
        db.deleteNovel(id: novel.id)
        check("删除作品级联清理", db.novels().isEmpty)
        try? FileManager.default.removeItem(at: AgentStore.url)

        print(failed == 0 ? "\n全部通过 ✅" : "\n\(failed) 项失败 ❌")
        exit(failed == 0 ? 0 : 1)
    }
}
