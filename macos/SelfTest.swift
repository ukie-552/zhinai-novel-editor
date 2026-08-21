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

        // 6. Agent 存储
        let agent = Agent(id: UUID(), name: "测试Agent", icon: "sparkles",
                          systemPrompt: "你是测试人格。", temperature: 0.5, isBuiltin: false)
        AgentStore.save([agent])
        let loaded = AgentStore.load()
        check("Agent 保存/加载", loaded.contains { $0.id == agent.id && $0.systemPrompt == "你是测试人格。" })

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
                                                  temperature: 0.9) { d in
                got += d
            }
            check("LLM 流式输出(温度覆盖)", got.count >= 5 && result.text == got, "收到 \(got.count) 字符")
            check("无工具调用返回", result.toolCalls.isEmpty)
        } catch {
            check("LLM 流式输出", false, error.localizedDescription)
        }

        // 7.5 写作工具执行
        let app = AppState()
        app.selectNovel(novel.id)
        let tc1 = ToolCall(id: "t1", name: "read_chapter", arguments: "{\"number\":1}")
        check("工具 read_chapter", AppState.executeTool(tc1, app: app).contains("第一章"))
        let tc2 = ToolCall(id: "t2", name: "list_chapters", arguments: "{}")
        check("工具 list_chapters", AppState.executeTool(tc2, app: app).contains("第二章"))
        let tc3 = ToolCall(id: "t3", name: "search_database", arguments: "{\"query\":\"霜河\"}")
        check("工具 search_database", AppState.executeTool(tc3, app: app).contains("林晚舟"))
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
