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
    let system: String          // 仅在本轮调用时追加到 Agent 之后的任务/技能指令
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
    Skill(id: "chat", name: "普通对话", icon: "bubble.left.and.bubble.right", desc: "只使用当前 Agent，不附加任务指令",
          category: .write,
          system: "",
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
    skills.first { $0.id == id }
        ?? skills.first { $0.id == "chat" }
        ?? ALL_SKILLS.first { $0.id == "chat" }!
}

/// Agent 可自行调取的 Skill 目录。固定 Skill 已经完整注入，因此不再列入按需索引。
func indexedSkills(for agent: Agent, skills: [Skill]) -> [Skill] {
    return skills.filter { skill in
        skill.id != "chat"
            && skill.id != agent.fixedSkillID
    }
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
        // 编辑已有 Markdown Skill 时 ID 必须稳定，否则 Agent 白名单和工具引用会失效。
        let id = existing?.isMarkdown == true
            ? existing!.id
            : uniqueID(slug(name), excluding: nil)
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

    /// 导入外部 Markdown Skill。先解析校验，再以新的稳定 ID 写入本地目录，
    /// 因此同名文件不会覆盖已有技能，内置技能 ID 也不会发生冲突。
    @discardableResult
    static func importFile(_ sourceURL: URL) throws -> Skill {
        guard sourceURL.pathExtension.lowercased() == "md" else {
            throw SkillStoreError.unsupportedFile
        }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let source = parse(sourceURL) else { throw SkillStoreError.invalidMarkdown }
        return try save(existing: nil,
                        name: source.name,
                        desc: source.desc,
                        category: source.category,
                        icon: source.icon,
                        needsText: source.needsText,
                        chapters: source.chapters,
                        markdown: source.system)
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
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .invalidMarkdown: return "Markdown Skill 缺少有效正文或无法读取"
        case .unsupportedFile: return "仅支持 .md 文件"
        }
    }
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

// MARK: - Token 估算
/// 不同厂商 tokenizer 并不一致。这里采用偏保守的本地上界近似：
/// 非 ASCII 标量按 1 token、ASCII 按约 4 字符/token，再预留少量消息开销。
/// 宁可略早触发压缩，也不让中文、日文、韩文或 emoji 被明显低估。

func estimateTokens(_ s: String) -> Int {
    var ascii = 0
    var nonASCII = 0
    for scalar in s.unicodeScalars {
        if scalar.isASCII { ascii += 1 } else { nonASCII += 1 }
    }
    return nonASCII + (ascii + 3) / 4 + 4
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
    var originalTokens = 0
    var compressedTokens: Int?
    var protectedContentExceededBudget = false
    var requestExceedsInputBudget = false
    var inputBudget = 0
    var totalTokens: Int { compressedTokens ?? (novelInfoTokens + loreTokens + chaptersTokens + historyTokens) }
    var compressionSavedTokens: Int { max(0, originalTokens - totalTokens) }
    var compressionPercent: Int {
        guard originalTokens > 0 else { return 0 }
        return Int((Double(compressionSavedTokens) / Double(originalTokens) * 100).rounded())
    }
    var compressionApplied: Bool { compressionSavedTokens > 0 }
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
    /// Agent 固定绑定的 Skill。它只扩展 Agent 的长期行为，不改变本轮消息类型。
    let fixedSkill: Skill?
    /// 仅包含名称与说明的轻量目录；Agent 需要时通过 get_skill 获取完整正文。
    let indexedSkills: [Skill]

    init(novel: Novel, chapters: [Chapter], entries: [Entry], history: [Msg],
         userText: String, targetText: String, skill: Skill,
         fixedSkill: Skill? = nil, indexedSkills: [Skill] = []) {
        self.novel = novel
        self.chapters = chapters
        self.entries = entries
        self.history = history
        self.userText = userText
        self.targetText = targetText
        self.skill = skill
        self.fixedSkill = fixedSkill
        self.indexedSkills = indexedSkills
    }
}

struct ContextCompressionResult {
    let text: String
    let originalTokens: Int
    let finalTokens: Int
    let protectedTokens: Int
    let protectedContentExceededBudget: Bool
}

/// 面向小说的本地抽取式压缩：稀有度近似自信息，查询重合度衡量相关性，
/// 再以 MMR 风格相似度阈值去重。高优先级设定、标题和最新片段强制保留。
enum NovelContextCompressor {
    private struct Unit {
        let index: Int
        let text: String
        let terms: Set<String>
        let tokens: Int
        let protected: Bool
        var score: Double
    }

    static func compress(_ text: String, query: String, maxTokens: Int,
                         level: ContextCompressionLevel) -> ContextCompressionResult {
        let original = estimateTokens(text)
        guard original > maxTokens, maxTokens > 0 else {
            return ContextCompressionResult(text: text, originalTokens: original, finalTokens: original,
                                            protectedTokens: 0, protectedContentExceededBudget: false)
        }

        let pieces = splitUnits(text)
        guard !pieces.isEmpty else {
            return ContextCompressionResult(text: text, originalTokens: original, finalTokens: original,
                                            protectedTokens: 0, protectedContentExceededBudget: false)
        }

        let queryTerms = terms(in: query)
        var documentFrequency: [String: Int] = [:]
        let unitTerms = pieces.map { terms(in: $0) }
        for set in unitTerms {
            for term in set { documentFrequency[term, default: 0] += 1 }
        }

        let protectedWords = ["必须", "不得", "禁止", "硬规则", "高优先级"]
        let protectedSectionNames = ["作者长期意图", "当前 1–3 章聚焦", "本书硬规则", "设定库 · 已激活条目", "最新章节结尾"]
        var units: [Unit] = []
        var inProtectedSection = false
        for (index, piece) in pieces.enumerated() {
            if piece.hasPrefix("【") {
                inProtectedSection = protectedSectionNames.contains(where: piece.contains)
            }
            let set = unitTerms[index]
            let rarity = set.isEmpty ? 0 : set.reduce(0.0) { value, term in
                value + log(Double(pieces.count + 1) / Double((documentFrequency[term] ?? 0) + 1))
            } / Double(set.count)
            let overlap = set.intersection(queryTerms).count
            let relevance = queryTerms.isEmpty ? 0 : Double(overlap) / sqrt(Double(max(1, set.count)))
            let structural = (piece.contains("【") || piece.contains("——第") || piece.contains("〔")) ? 2.4 : 0
            let recency = Double(index) / Double(max(1, pieces.count - 1)) * 1.2
            let edge = (index == 0 || index >= pieces.count - 2) ? 2.0 : 0
            let isProtected = inProtectedSection || piece.contains("〔")
                || protectedWords.contains(where: piece.contains) || index >= pieces.count - 2
            let score = rarity * 0.75 + relevance * 5.0 + structural + recency + edge
            units.append(Unit(index: index, text: piece, terms: set, tokens: estimateTokens(piece),
                              protected: isProtected, score: score))
        }

        var selected: [Unit] = []
        var usedTokens = 0
        for unit in units where unit.protected {
            selected.append(unit)
            usedTokens += unit.tokens
        }
        let protectedTokens = usedTokens
        // 给说明行留少量空间；受保护内容本身超限时宁可明确超预算，也不静默裁掉硬规则。
        let selectionBudget = max(1, maxTokens - 36)

        let ranked = units.filter { !$0.protected }.sorted {
            if $0.score == $1.score { return $0.index > $1.index }
            return $0.score > $1.score
        }
        var deferred: [Unit] = []
        for unit in ranked where usedTokens + unit.tokens <= selectionBudget {
            let similarity = selected.suffix(80).map { jaccard(unit.terms, $0.terms) }.max() ?? 0
            if similarity <= level.redundancyThreshold {
                selected.append(unit)
                usedTokens += unit.tokens
            } else {
                deferred.append(unit)
            }
        }
        for unit in deferred where usedTokens + unit.tokens <= selectionBudget {
            selected.append(unit)
            usedTokens += unit.tokens
        }

        let output = selected.sorted { $0.index < $1.index }.map(\.text).joined(separator: "\n")
        let contentTokens = estimateTokens(output)
        let overflow = protectedTokens > selectionBudget
        let status = overflow ? "；受保护内容超过目标预算，未裁切" : ""
        let note = "〔上下文压缩：约 \(original) → \(contentTokens) tokens，节省 \(max(0, original - contentTokens) * 100 / max(1, original))%\(status)〕\n"
        let finalText = note + output
        return ContextCompressionResult(text: finalText, originalTokens: original,
                                        finalTokens: estimateTokens(finalText),
                                        protectedTokens: protectedTokens,
                                        protectedContentExceededBudget: overflow)
    }

    private static func splitUnits(_ text: String) -> [String] {
        var result: [String] = []
        var buffer = ""
        let boundaries: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "\n"]
        for character in text {
            buffer.append(character)
            if boundaries.contains(character) || buffer.count >= 600 {
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                buffer = ""
            }
        }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private static func terms(in text: String) -> Set<String> {
        let lowered = text.lowercased()
        var result: Set<String> = []
        var ascii = ""
        var cjk: [Character] = []

        func flushASCII() {
            if ascii.count >= 2 { result.insert(ascii) }
            ascii = ""
        }
        func flushCJK() {
            if cjk.count == 1 { result.insert(String(cjk[0])) }
            if cjk.count >= 2 {
                for index in 0..<(cjk.count - 1) {
                    result.insert(String(cjk[index...index + 1]))
                }
            }
            cjk.removeAll(keepingCapacity: true)
        }

        for character in lowered {
            if character.isASCII && (character.isLetter || character.isNumber) {
                flushCJK()
                ascii.append(character)
            } else if character.unicodeScalars.allSatisfy({ $0.value >= 0x3400 && $0.value <= 0x9FFF }) {
                flushASCII()
                cjk.append(character)
            } else {
                flushASCII()
                flushCJK()
            }
        }
        flushASCII()
        flushCJK()
        return result
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }

}

/// 组装最终请求：返回 (system, messages, plan)。
/// system 不含 Agent 人格（由调用方前置注入），此处为 作品信息 + 世界书 + 前文 + 技能指令。
func buildRequest(ctx: GenContext, tokenBudget: Int? = nil,
                  compressionLevel: ContextCompressionLevel? = nil,
                  compressionTargetRetention: Double? = nil,
                  reservedInputTokens: Int = 0) -> (system: String, messages: [ChatMsg], plan: ContextPlan) {
    var plan = ContextPlan()
    var L: [String] = []
    let usesCompression = tokenBudget != nil && compressionLevel != nil
    func content(_ value: String, legacyMax: Int) -> String {
        usesCompression ? value : String(value.prefix(legacyMax))
    }

    // 作品信息。公共会话的“未选书”状态由一次性事件承载，这里不重复注入。
    var infoLines: [String] = []
    if ctx.novel.id != GLOBAL_CHAT_NOVEL_ID, !ctx.novel.title.isEmpty {
        infoLines.append("当前作品：《\(ctx.novel.title)》")
        infoLines.append("book_id：\(ctx.novel.id.uuidString)")
    }
    let meta = ctx.novel.metadata
    let configParts = ctx.novel.id == GLOBAL_CHAT_NOVEL_ID ? [] : [
        meta.genres.first.map { "题材：\($0)" },
        meta.platform == "other" ? nil : "目标平台：\(meta.platform)",
        "语言：\(meta.language)",
        "状态：\(meta.status)",
        "目标：\(meta.targetChapters) 章，每章约 \(meta.chapterWordCount) 字"
    ].compactMap { $0 }
    if !configParts.isEmpty { infoLines.append(configParts.joined(separator: "｜")) }
    if ctx.novel.id != GLOBAL_CHAT_NOVEL_ID, !ctx.novel.desc.isEmpty { infoLines.append("作品简介：\(content(ctx.novel.desc, legacyMax: ContextLimits.descMax))") }
    if !meta.authorIntent.isEmpty {
        infoLines.append("【作者长期意图（高优先级）】")
        infoLines.append(content(meta.authorIntent, legacyMax: 3000))
    }
    if !meta.currentFocus.isEmpty {
        infoLines.append("【当前 1–3 章聚焦（高于卷纲）】")
        infoLines.append(content(meta.currentFocus, legacyMax: 2000))
    }
    if !meta.storyFrame.isEmpty {
        infoLines.append("【故事框架】")
        infoLines.append(content(meta.storyFrame, legacyMax: 5000))
    }
    if !ctx.novel.outline.isEmpty {
        infoLines.append("【卷纲 / 故事大纲】")
        infoLines.append(content(ctx.novel.outline, legacyMax: ContextLimits.outlineMax))
    }
    if !meta.bookRules.isEmpty {
        infoLines.append("【本书硬规则（必须遵守）】")
        infoLines.append(content(meta.bookRules, legacyMax: 3000))
    }
    if let libraryID = UUID(uuidString: meta.styleLibraryID),
       let profile = VectorStore().styleProfile(libraryID: libraryID) {
        let strengthLabel = meta.styleStrength >= 0.8 ? "强" : (meta.styleStrength <= 0.4 ? "弱" : "中等")
        infoLines.append("【去 AI 味写法指导｜强度：\(strengthLabel)】")
        infoLines.append(profile)
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
            if !usesCompression && (used + line.count > ContextLimits.loreTotalMax || count >= ContextLimits.loreCountMax) { break }
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
            chapterLines.append(content(c.content, legacyMax: ContextLimits.chapterMax))
        }
        if usesCompression, let latest = ctx.chapters.last, !latest.content.isEmpty {
            chapterLines.append("【最新章节结尾（续写衔接，强制保留）】")
            chapterLines.append(String(latest.content.suffix(2400)))
        }
        plan.chaptersTokens = estimateTokens(chapterLines.joined(separator: "\n"))
        plan.chapterCount = ctx.chapters.count
        L.append("")
        L.append(contentsOf: chapterLines)
    }

    // 固定 Skill 属于 Agent 的长期能力；按需 Skill 只属于这一轮。固定项先注入，
    // 两者相同时只保留一份，避免重复指令放大权重。
    if let fixedSkill = ctx.fixedSkill, !fixedSkill.system.isEmpty {
        L.append("")
        L.append("【Agent 固定 Skill：\(fixedSkill.name)】")
        L.append(fixedSkill.system)
        if fixedSkill.needsText, !ctx.targetText.isEmpty {
            L.append("【固定 Skill 的目标文本】")
            L.append(ctx.targetText)
        }
    }
    if !ctx.skill.system.isEmpty, ctx.skill.id != ctx.fixedSkill?.id {
        L.append("")
        L.append("【本轮按需任务 / Skill：\(ctx.skill.name)】")
        L.append(ctx.skill.system)
    }
    if !ctx.indexedSkills.isEmpty {
        L.append("")
        L.append("【可按需调取的 Skill 索引】")
        L.append("以下内容只是能力目录，不是当前任务指令。仅当用户任务明确需要某项能力时，调用 get_skill(skill_id) 读取完整正文，再按其指令完成任务；不要同时加载无关 Skill。")
        for skill in ctx.indexedSkills {
            L.append("- \(skill.id)｜\(skill.name)｜\(skill.category.rawValue)｜\(skill.desc)")
        }
    }

    let rawSystem = L.joined(separator: "\n")
    let isChat = ctx.skill.id == "chat"
    let userMessage = isChat ? ctx.userText : buildUserMessage(ctx)
    let rawSystemTokens = estimateTokens(rawSystem)
    let rawHistoryTokens = isChat ? estimateTokens(ctx.history.map { $0.content }.joined(separator: "\n")) : 0
    let userTokens = estimateTokens(userMessage)
    plan.originalTokens = rawSystemTokens + rawHistoryTokens + userTokens + max(0, reservedInputTokens)

    let query = [ctx.userText, ctx.targetText, ctx.novel.title, ctx.novel.metadata.currentFocus,
                 ctx.entries.map { "\($0.title) \($0.keywords)" }.joined(separator: " ")]
        .joined(separator: "\n")
    let finalSystem: String
    var historyBudget: Int? = nil
    if let tokenBudget, let compressionLevel {
        plan.inputBudget = tokenBudget
        // 4% 留给消息包装、工具定义及不同厂商 tokenizer 的估算误差。
        let safeInputBudget = max(256, Int(Double(tokenBudget) * 0.96))
        let availableContextBudget = max(1, safeInputBudget - userTokens - max(0, reservedInputTokens))
        let rawContextTokens = rawSystemTokens + rawHistoryTokens
        let retention = min(0.95, max(0.10,
            compressionTargetRetention ?? compressionLevel.targetRetentionRatio))
        // 达到配置输入窗口的 80% 即提前压缩，避免流式请求在包装后才发现超限。
        let triggerTokens = max(1, Int(Double(tokenBudget) * 0.80))
        let shouldCompress = plan.originalTokens >= triggerTokens
        let targetContextTokens = shouldCompress
            ? min(availableContextBudget, max(1, Int(Double(rawContextTokens) * retention)))
            : rawContextTokens

        let systemBudget: Int
        if isChat, shouldCompress, rawHistoryTokens > 0 {
            let recent = Array(ctx.history.suffix(8))
            let protectedRecentTokens = estimateTokens(recent.map { $0.content }.joined(separator: "\n"))
            let olderHistoryTokens = max(0, rawHistoryTokens - protectedRecentTokens)
            let variableDemand = rawSystemTokens + olderHistoryTokens
            let remainingAfterRecent = max(0, targetContextTokens - protectedRecentTokens)
            let proportionalSystem = variableDemand == 0 ? 0
                : Int(Double(remainingAfterRecent) * Double(rawSystemTokens) / Double(variableDemand))
            systemBudget = max(1, min(rawSystemTokens, proportionalSystem))
            let allocatedHistory = max(protectedRecentTokens, targetContextTokens - systemBudget)
            historyBudget = min(rawHistoryTokens, allocatedHistory)
        } else {
            systemBudget = shouldCompress ? targetContextTokens : rawSystemTokens
            historyBudget = isChat ? rawHistoryTokens : nil
        }
        let systemCompression = NovelContextCompressor.compress(rawSystem, query: query,
                                                                 maxTokens: systemBudget, level: compressionLevel)
        finalSystem = systemCompression.text
        plan.protectedContentExceededBudget = systemCompression.protectedContentExceededBudget
    } else {
        finalSystem = rawSystem
    }

    // 历史与用户消息
    if ctx.skill.id == "chat" {
        var msgs: [ChatMsg] = []
        if let historyBudget, let compressionLevel,
           rawHistoryTokens > historyBudget, ctx.history.count > 8 {
            let recent = Array(ctx.history.suffix(8))
            let older = ctx.history.dropLast(recent.count).map {
                let content = $0.role == "assistant" ? ModelOutputParser.parse($0.content).response : $0.content
                return "【\($0.role == "user" ? "用户" : "助手")】\(content)"
            }.joined(separator: "\n")
            let recentTokens = estimateTokens(recent.map {
                $0.role == "assistant" ? ModelOutputParser.parse($0.content).response : $0.content
            }.joined(separator: "\n"))
            let memoryBudget = max(0, historyBudget - recentTokens - 24)
            if memoryBudget >= 64 {
                let memoryCompression = NovelContextCompressor.compress(
                    older, query: query, maxTokens: memoryBudget, level: compressionLevel
                )
                plan.protectedContentExceededBudget = plan.protectedContentExceededBudget
                    || memoryCompression.protectedContentExceededBudget
                msgs.append(ChatMsg(role: "user", content: "【较早对话压缩记忆】\n\(memoryCompression.text)"))
            }
            for m in recent {
                let visibleContent = m.role == "assistant" ? ModelOutputParser.parse(m.content).response : m.content
                msgs.append(ChatMsg(role: m.role == "assistant" ? "assistant" : "user",
                                    content: m.role == "event" ? "【系统状态事件】\(visibleContent)" : visibleContent))
            }
            plan.historyCount = recent.count + (memoryBudget >= 64 ? 1 : 0)
        } else {
            let history = usesCompression ? ctx.history[...] : ctx.history.suffix(ContextLimits.historyCountMax)[...]
            for m in history {
                let cleanContent = m.role == "assistant" ? ModelOutputParser.parse(m.content).response : m.content
                let value = usesCompression ? cleanContent : String(cleanContent.prefix(ContextLimits.historyMsgMax))
                msgs.append(ChatMsg(role: m.role == "assistant" ? "assistant" : "user",
                                    content: m.role == "event" ? "【系统状态事件】\(value)" : value))
            }
            plan.historyCount = history.count
        }
        plan.historyTokens = estimateTokens(msgs.map { $0.content }.joined(separator: "\n"))
        msgs.append(ChatMsg(role: "user", content: userMessage))
        plan.compressedTokens = estimateTokens(finalSystem) + plan.historyTokens + userTokens + max(0, reservedInputTokens)
        if plan.inputBudget > 0 {
            plan.requestExceedsInputBudget = plan.totalTokens > Int(Double(plan.inputBudget) * 0.96)
        }
        return (finalSystem, msgs, plan)
    }
    plan.compressedTokens = estimateTokens(finalSystem) + estimateTokens(userMessage) + max(0, reservedInputTokens)
    if plan.inputBudget > 0 {
        plan.requestExceedsInputBudget = plan.totalTokens > Int(Double(plan.inputBudget) * 0.96)
    }
    return (finalSystem, [ChatMsg(role: "user", content: userMessage)], plan)
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
