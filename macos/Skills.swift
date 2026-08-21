import Foundation

// MARK: - 技能定义

enum SkillCategory: String, CaseIterable, Identifiable {
    case write = "创作"
    case world = "设定"
    case analyze = "分析"
    var id: String { rawValue }
}

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let desc: String
    let category: SkillCategory
    let system: String          // 追加到 Agent 系统提示词之后的技能指令
    let needsText: Bool         // 是否需要目标文本（润色）
    let chapters: Int           // 注入前文章节数
    let fileURL: URL?

    var isMarkdown: Bool { fileURL != nil }

    init(id: String, name: String, icon: String, desc: String, category: SkillCategory,
         system: String, needsText: Bool, chapters: Int, fileURL: URL? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.desc = desc
        self.category = category
        self.system = system
        self.needsText = needsText
        self.chapters = chapters
        self.fileURL = fileURL
    }
}

let ALL_SKILLS: [Skill] = [
    // ── 创作 ──
    Skill(id: "chat", name: "自由对话", icon: "bubble.left.and.bubble.right", desc: "与 AI 讨论剧情、人设与写法",
          category: .write,
          system: "与用户围绕当前作品进行创作讨论：讨论剧情、人设、世界观时严格基于参考设定；需要创作时直接给出高质量中文文本；回答简洁有条理。",
          needsText: false, chapters: 1),
    Skill(id: "continue", name: "续写正文", icon: "square.and.pencil", desc: "紧接最新章节继续写作",
          category: .write,
          system: "任务：紧接前文最后一章续写新的章节正文（1000-2500 字）。要求：人物口吻与文风和前文一致；推进剧情或深化冲突；结尾留悬念。直接输出正文，不要输出解释。",
          needsText: false, chapters: 2),
    Skill(id: "outline", name: "生成大纲", icon: "map", desc: "生成分章故事大纲",
          category: .write,
          system: "任务：为当前作品生成完整的分章故事大纲。要求：先给出核心创意（一句话）与主线/支线概述，再分章列出每章要点（章节号+标题+事件与钩子）；世界观、人物、已有剧情必须严格符合参考设定；使用 Markdown 输出。",
          needsText: false, chapters: 0),
    Skill(id: "polish", name: "润色改写", icon: "sparkles", desc: "润色选中文本或最新章节",
          category: .write,
          system: "任务：对给定文本进行润色改写。要求：保留原意与情节推进，不得擅自增删关键剧情；提升文笔、节奏与可读性，修正语病与逻辑瑕疵；先输出润色后的全文，再附简短「修改说明」。",
          needsText: true, chapters: 0),
    Skill(id: "scene", name: "场景创作", icon: "photo.artframe", desc: "为当前剧情创作一段场景描写",
          category: .write,
          system: "任务：围绕用户指定的剧情节点/场景创作一段场景正文（600-1500 字）。要求：五感描写、氛围营造、人物动作与对话自然；与设定和前文一致；直接输出正文。",
          needsText: false, chapters: 1),

    // ── 设定 ──
    Skill(id: "character", name: "人物设计", icon: "person.fill", desc: "生成完整人物卡",
          category: .world,
          system: "任务：设计一个小说人物卡。要求：包含姓名、年龄、外貌、性格、背景故事、动机与目标、弱点、与其他角色的关系、成长弧光；人物贴合作品世界观；使用 Markdown 输出。",
          needsText: false, chapters: 0),
    Skill(id: "worldbuilding", name: "世界观设定", icon: "globe.asia.australia", desc: "完善力量体系、地理、势力、历史",
          category: .world,
          system: "任务：完善作品的世界观设定。要求：围绕用户提出的方向输出核心规则、力量体系/科技、地理、势力分布、历史脉络、日常细节、禁忌与冲突点；逻辑自洽且与已有参考设定一致；使用 Markdown 输出。",
          needsText: false, chapters: 0),
    Skill(id: "location", name: "地点设计", icon: "mappin.and.ellipse", desc: "设计场景地点：地理、氛围、功能",
          category: .world,
          system: "任务：设计一个小说地点/场景设定。要求：包含地理位置、外观与布局、氛围与色调、功能与秘密、适合发生的情节类型、注意事项（与世界观一致的约束）；使用 Markdown 输出。",
          needsText: false, chapters: 0),
    Skill(id: "faction", name: "势力设计", icon: "flag.fill", desc: "设计组织势力：结构、目标、关系网",
          category: .world,
          system: "任务：设计一个小说势力/组织设定。要求：包含宗旨与目标、组织结构与关键人物、资源与地盘、与其他势力的关系、内部矛盾、对主角的影响；与已有设定一致；使用 Markdown 输出。",
          needsText: false, chapters: 0),
    Skill(id: "item", name: "物品道具设计", icon: "shippingbox.fill", desc: "设计神器/物品：来历、能力、代价",
          category: .world,
          system: "任务：设计一个小说物品/道具设定。要求：包含外观、来历与传说、能力与规则（明确边界）、使用代价或限制、在剧情中的作用；与世界观力量体系自洽；使用 Markdown 输出。",
          needsText: false, chapters: 0),

    // ── 分析 ──
    Skill(id: "consistency", name: "一致性检查", icon: "checkmark.seal", desc: "检查前文与设定的矛盾",
          category: .analyze,
          system: "任务：检查前文与参考设定之间的人物、时间线、能力、地点、细节一致性。要求：逐条列出矛盾点（引用原文位置）并给出修改建议；无矛盾时说明「未发现明显矛盾」；使用 Markdown 输出。",
          needsText: false, chapters: 2),
    Skill(id: "inspire", name: "灵感脑暴", icon: "lightbulb", desc: "围绕主题生成 5-10 个剧情创意",
          category: .analyze,
          system: "任务：围绕用户给出的主题进行头脑风暴。要求：给出 5-10 个新颖、可落地的剧情灵感/转折/设定创意，每个 2-3 句话说明价值，并标注最推荐的一个；使用 Markdown 输出。",
          needsText: false, chapters: 0),
]

func skillByID(_ id: String, skills: [Skill] = ALL_SKILLS) -> Skill {
    skills.first { $0.id == id } ?? skills.first ?? ALL_SKILLS[0]
}

// MARK: - Markdown Skills

enum SkillStore {
    static var directory: URL {
        let url = AppPaths.dataDir.appendingPathComponent("skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load() -> [Skill] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let custom = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(parse)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return ALL_SKILLS + custom
    }

    static func parse(_ url: URL) -> Skill? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var metadata: [String: String] = [:]
        var body = normalized

        if normalized.hasPrefix("---\n"),
           let end = normalized.range(of: "\n---\n", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex) {
            let front = normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in front.split(separator: "\n", omittingEmptySubsequences: false) {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                metadata[key] = value
            }
            body = String(normalized[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let fallbackID = url.deletingPathExtension().lastPathComponent
        let id = metadata["id"].flatMap(cleanID) ?? cleanID(fallbackID) ?? UUID().uuidString.lowercased()
        let name = metadata["name"]?.nonEmpty ?? fallbackID
        let desc = metadata["description"]?.nonEmpty ?? "本地 Markdown 技能"
        let category = SkillCategory(rawValue: metadata["category"] ?? "") ?? .write
        let icon = metadata["icon"]?.nonEmpty ?? "doc.text"
        let needsText = parseBool(metadata["needs_text"] ?? metadata["needstext"])
        let chapters = max(0, min(10, Int(metadata["chapters"] ?? "0") ?? 0))
        guard !body.isEmpty else { return nil }

        return Skill(id: id, name: name, icon: icon, desc: desc, category: category,
                     system: body, needsText: needsText, chapters: chapters, fileURL: url)
    }

    @discardableResult
    static func save(existing: Skill?, name: String, desc: String, category: SkillCategory,
                     icon: String, needsText: Bool, chapters: Int, markdown: String) throws -> Skill {
        let preferredID = existing?.isMarkdown == true ? existing!.id : slug(name)
        let id = uniqueID(preferredID, excluding: existing?.fileURL)
        let url = existing?.fileURL ?? directory.appendingPathComponent(id).appendingPathExtension("md")
        let text = """
        ---
        id: \(id)
        name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))
        description: \(desc.trimmingCharacters(in: .whitespacesAndNewlines))
        category: \(category.rawValue)
        icon: \(icon.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "doc.text")
        needs_text: \(needsText ? "true" : "false")
        chapters: \(max(0, min(10, chapters)))
        ---

        \(markdown.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        guard let skill = parse(url) else { throw SkillStoreError.invalidMarkdown }
        return skill
    }

    static func delete(_ skill: Skill) throws {
        guard let url = skill.fileURL else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func uniqueID(_ value: String, excluding: URL?) -> String {
        var candidate = cleanID(value) ?? "skill"
        var number = 2
        while ALL_SKILLS.contains(where: { $0.id == candidate }) ||
                (directory.appendingPathComponent(candidate).appendingPathExtension("md").path != excluding?.path &&
                 FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).appendingPathExtension("md").path)) {
            candidate = "\(cleanID(value) ?? "skill")-\(number)"
            number += 1
        }
        return candidate
    }

    private static func slug(_ value: String) -> String {
        let latin = value.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? value
        let parts = latin.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return cleanID(parts.joined(separator: "-")) ?? "skill-\(UUID().uuidString.lowercased().prefix(8))"
    }

    private static func cleanID(_ value: String) -> String? {
        let cleaned = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "yes", "1", "on"].contains(value.lowercased())
    }
}

enum SkillStoreError: LocalizedError {
    case invalidMarkdown
    var errorDescription: String? { "Markdown Skill 缺少有效正文" }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 世界书（Lorebook）激活机制
/// 参考 SillyTavern 的世界书：条目配置关键词，上下文出现关键词时自动注入设定。

func activateLorebook(entries: [Entry], scanText: String) -> [Entry] {
    let seps: Set<Character> = [",", "，", "、", " ", "　"]
    return entries.filter { e in
        if e.pinned { return true }
        let kws = e.keywords.split(whereSeparator: { seps.contains($0) })
            .map(String.init).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return kws.contains { !$0.isEmpty && scanText.contains($0) }
    }
}

// MARK: - Token 估算（粗略：中文≈2字/token，英文≈4字符/token）

func estimateTokens(_ s: String) -> Int {
    var cjk = 0, other = 0
    for ch in s.unicodeScalars {
        if ch.value >= 0x4E00 && ch.value <= 0x9FFF { cjk += 1 } else { other += 1 }
    }
    return cjk / 2 + other / 4 + 1
}

// MARK: - 上下文预算（防上下文爆炸）
/// 所有注入内容都有上限，并返回用量明细供 UI 显示。

struct ContextPlan {
    var novelInfoTokens = 0
    var loreTokens = 0
    var loreCount = 0
    var chaptersTokens = 0
    var chapterCount = 0
    var historyTokens = 0
    var historyCount = 0
    var totalTokens: Int { novelInfoTokens + loreTokens + chaptersTokens + historyTokens }
}

enum ContextLimits {
    static let descMax = 500          // 作品简介
    static let outlineMax = 4000      // 大纲
    static let chapterMax = 6000      // 每章正文
    static let loreTotalMax = 6000    // 世界书合计
    static let loreCountMax = 12      // 世界书条数
    static let historyCountMax = 16   // 历史消息条数
    static let historyMsgMax = 1500   // 每条历史消息
}

struct GenContext {
    let novel: Novel
    let chapters: [Chapter]
    let entries: [Entry]
    let history: [Msg]
    let userText: String
    let targetText: String
    let skill: Skill
}

/// 组装最终请求：返回 (system, messages, plan)。
/// system 不含 Agent 人格（由调用方前置注入），此处为 作品信息 + 世界书 + 前文 + 技能指令。
func buildRequest(ctx: GenContext) -> (system: String, messages: [ChatMsg], plan: ContextPlan) {
    var plan = ContextPlan()
    var L: [String] = []

    // 作品信息
    var infoLines: [String] = []
    if !ctx.novel.title.isEmpty { infoLines.append("当前作品：《\(ctx.novel.title)》") }
    if !ctx.novel.desc.isEmpty { infoLines.append("作品简介：\(String(ctx.novel.desc.prefix(ContextLimits.descMax)))") }
    if !ctx.novel.outline.isEmpty {
        infoLines.append("故事大纲：")
        infoLines.append(String(ctx.novel.outline.prefix(ContextLimits.outlineMax)))
    }
    if !infoLines.isEmpty {
        plan.novelInfoTokens = estimateTokens(infoLines.joined(separator: "\n"))
        L.append(contentsOf: infoLines)
    }

    // 世界书（已激活）
    if !ctx.entries.isEmpty {
        var used = 0
        var loreLines: [String] = ["【设定库 · 已激活条目（关键词自动触发或固定引用，必须严格遵守，不得矛盾）】"]
        var count = 0
        for e in ctx.entries {
            let line = "〔\(count + 1)〕\(entryTypeLabel(e.type))｜\(e.title)：\(e.content)"
            if used + line.count > ContextLimits.loreTotalMax || count >= ContextLimits.loreCountMax { break }
            loreLines.append(line)
            used += line.count
            count += 1
        }
        plan.loreTokens = estimateTokens(loreLines.joined(separator: "\n"))
        plan.loreCount = count
        L.append("")
        L.append(contentsOf: loreLines)
    }

    // 前文
    if !ctx.chapters.isEmpty {
        var chapterLines: [String] = ["【前文（创作时须与之一致并自然衔接）】"]
        for c in ctx.chapters {
            chapterLines.append("——第 \(c.no) 章 \(c.title)——")
            chapterLines.append(String(c.content.prefix(ContextLimits.chapterMax)))
        }
        plan.chaptersTokens = estimateTokens(chapterLines.joined(separator: "\n"))
        plan.chapterCount = ctx.chapters.count
        L.append("")
        L.append(contentsOf: chapterLines)
    }

    // Agent 系统提示词 + 技能指令由上层注入（在 system 中），这里补技能指令
    if !ctx.skill.system.isEmpty {
        L.append("")
        L.append(ctx.skill.system)
    }

    // 历史与用户消息
    if ctx.skill.id == "chat" {
        var msgs: [ChatMsg] = []
        let history = ctx.history.suffix(ContextLimits.historyCountMax)
        for m in history {
            msgs.append(ChatMsg(role: m.role == "user" ? "user" : "assistant",
                                content: String(m.content.prefix(ContextLimits.historyMsgMax))))
        }
        plan.historyTokens = estimateTokens(history.map { $0.content }.joined(separator: "\n"))
        plan.historyCount = history.count
        msgs.append(ChatMsg(role: "user", content: ctx.userText))
        return (L.joined(separator: "\n"), msgs, plan)
    }
    return (L.joined(separator: "\n"), [ChatMsg(role: "user", content: buildUserMessage(ctx))], plan)
}

func buildUserMessage(_ ctx: GenContext) -> String {
    switch ctx.skill.id {
    case "chat":
        return ctx.userText
    case "continue":
        return "请紧接前文续写新的章节。续写要求：\n\(ctx.userText.isEmpty ? "自然地推进剧情。" : ctx.userText)"
    case "outline":
        return "请为《\(ctx.novel.title)》（\(ctx.novel.desc)）生成故事大纲。创作要求：\n\(ctx.userText.isEmpty ? "无特别要求，请自由发挥。" : ctx.userText)"
    case "polish":
        return "请润色以下文本：\n\n\(ctx.targetText.isEmpty ? "（未提供文本）" : ctx.targetText)\n\n润色要求：\(ctx.userText.isEmpty ? "保持原意，提升文笔。" : ctx.userText)"
    case "scene":
        return "请创作场景：\(ctx.userText.isEmpty ? "结合前文当前剧情自然展开" : ctx.userText)"
    case "character":
        return "请设计人物。方向：\n\(ctx.userText.isEmpty ? "请结合作品风格自由发挥。" : ctx.userText)"
    case "worldbuilding":
        return "请完善世界观设定。方向：\n\(ctx.userText.isEmpty ? "请结合作品风格自由发挥。" : ctx.userText)"
    case "location":
        return "请设计地点。方向：\n\(ctx.userText.isEmpty ? "请结合作品风格自由发挥。" : ctx.userText)"
    case "faction":
        return "请设计势力。方向：\n\(ctx.userText.isEmpty ? "请结合作品风格自由发挥。" : ctx.userText)"
    case "item":
        return "请设计物品道具。方向：\n\(ctx.userText.isEmpty ? "请结合作品风格自由发挥。" : ctx.userText)"
    case "inspire":
        return "请围绕以下主题展开头脑风暴：\n\(ctx.userText.isEmpty ? "（未提供主题，请结合作品给出创意）" : ctx.userText)"
    case "consistency":
        return "请检查前文与参考设定的一致性，并输出检查报告。"
    default:
        return ctx.userText
    }
}
