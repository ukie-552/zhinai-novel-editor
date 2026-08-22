import Foundation
import SwiftUI
import AppKit

/// 公共会话使用的内部作用域。它不会出现在用户书库中，只用于持久化未选择书籍时的会话。
let GLOBAL_CHAT_NOVEL_ID = UUID(uuidString: "00000000-0000-0000-0000-00000000C7A7")!

// MARK: - 路径与配置

enum AppPaths {
    static var dataDir: URL {
        if let env = ProcessInfo.processInfo.environment["AINOVEL_DATA_DIR"], !env.isEmpty {
            let dir = URL(fileURLWithPath: env, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("ZhinaiNovelEditor", isDirectory: true)
        let legacyDir = base.appendingPathComponent("AINovelWorkbench", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path),
           FileManager.default.fileExists(atPath: legacyDir.path) {
            try? FileManager.default.moveItem(at: legacyDir, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var configURL: URL { dataDir.appendingPathComponent("config.json") }
    static var dbURL: URL { dataDir.appendingPathComponent("novels.db") }
    static var vectorDBURL: URL { dataDir.appendingPathComponent("vectors.db") }
}

// MARK: - 核心模型

struct Novel: Identifiable {
    let id: UUID
    var title: String
    var desc: String
    var outline: String
    let createdAt: Date
    var updatedAt: Date
    var metadata: BookMetadata = BookMetadata()
}

/// 书籍自身的可交换元数据。章节数、当前字数等统计值由正文实时计算。
struct BookMetadata: Codable, Equatable {
    var subtitle = ""
    var authors: [String] = []
    var penName = ""
    var language = "zh-CN"
    var genres: [String] = []
    var tags: [String] = []
    var status = "incubating"
    var platform = "other"
    var targetChapters = 200
    var chapterWordCount = 3000
    var reviewMode = "manual"
    var styleLibraryID = ""
    var styleStrength = 0.65
    var seriesName = ""
    var seriesNumber = ""
    var logline = ""
    var authorIntent = ""
    var currentFocus = ""
    var storyFrame = ""
    var bookRules = ""
    var themes: [String] = []
    var targetAudience = ""
    var contentRating = ""
    var pointOfView = ""
    var tense = ""
    var targetWordCount = 0
    var isbn = ""
    var publisher = ""
    var publicationDate = ""
    var rights = ""
    var source = ""
    var custom: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        penName = try c.decodeIfPresent(String.self, forKey: .penName) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "zh-CN"
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "incubating"
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "other"
        targetChapters = try c.decodeIfPresent(Int.self, forKey: .targetChapters) ?? 200
        chapterWordCount = try c.decodeIfPresent(Int.self, forKey: .chapterWordCount) ?? 3000
        reviewMode = try c.decodeIfPresent(String.self, forKey: .reviewMode) ?? "manual"
        styleLibraryID = try c.decodeIfPresent(String.self, forKey: .styleLibraryID) ?? ""
        styleStrength = try c.decodeIfPresent(Double.self, forKey: .styleStrength) ?? 0.65
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName) ?? ""
        seriesNumber = try c.decodeIfPresent(String.self, forKey: .seriesNumber) ?? ""
        logline = try c.decodeIfPresent(String.self, forKey: .logline) ?? ""
        authorIntent = try c.decodeIfPresent(String.self, forKey: .authorIntent) ?? ""
        currentFocus = try c.decodeIfPresent(String.self, forKey: .currentFocus) ?? ""
        storyFrame = try c.decodeIfPresent(String.self, forKey: .storyFrame) ?? ""
        bookRules = try c.decodeIfPresent(String.self, forKey: .bookRules) ?? ""
        themes = try c.decodeIfPresent([String].self, forKey: .themes) ?? []
        targetAudience = try c.decodeIfPresent(String.self, forKey: .targetAudience) ?? ""
        contentRating = try c.decodeIfPresent(String.self, forKey: .contentRating) ?? ""
        pointOfView = try c.decodeIfPresent(String.self, forKey: .pointOfView) ?? ""
        tense = try c.decodeIfPresent(String.self, forKey: .tense) ?? ""
        targetWordCount = try c.decodeIfPresent(Int.self, forKey: .targetWordCount) ?? 0
        isbn = try c.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        publicationDate = try c.decodeIfPresent(String.self, forKey: .publicationDate) ?? ""
        rights = try c.decodeIfPresent(String.self, forKey: .rights) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        custom = try c.decodeIfPresent([String: String].self, forKey: .custom) ?? [:]
    }
}

struct Chapter: Identifiable {
    let id: UUID
    let novelID: UUID
    var no: Int
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
}

struct EntryTypeDef: Identifiable {
    let id: String
    let label: String
    let icon: String
}

let ENTRY_TYPES: [EntryTypeDef] = [
    EntryTypeDef(id: "character", label: "人物", icon: "person"),
    EntryTypeDef(id: "location", label: "地点", icon: "mappin"),
    EntryTypeDef(id: "faction", label: "势力组织", icon: "flag"),
    EntryTypeDef(id: "item", label: "物品道具", icon: "shippingbox"),
    EntryTypeDef(id: "world", label: "世界观", icon: "globe.asia.australia"),
    EntryTypeDef(id: "history", label: "历史事件", icon: "calendar"),
    EntryTypeDef(id: "idea", label: "灵感", icon: "lightbulb"),
    EntryTypeDef(id: "note", label: "笔记", icon: "note.text"),
    EntryTypeDef(id: "other", label: "其他", icon: "square.grid.2x2"),
]

func entryTypeLabel(_ id: String) -> String {
    ENTRY_TYPES.first { $0.id == id }?.label ?? "其他"
}

/// 设定条目（世界书）：keywords 为触发关键词（参考 SillyTavern 世界书机制），
/// 写作/对话时命中关键词的条目会自动注入上下文；pinned 则始终注入。
struct Entry: Identifiable {
    let id: UUID
    let novelID: UUID
    var type: String
    var title: String
    var content: String
    var keywords: String
    var pinned: Bool
    let createdAt: Date
    var updatedAt: Date
}

/// 章节之外的可扩展创作结构；kind 区分卷、场景、情节点、时间线、伏笔、关系、任务、审阅与批注。
struct StoryNode: Identifiable {
    let id: UUID
    let novelID: UUID
    var kind: String
    var title: String
    var content: String
    var status: String
    var parentID: UUID?
    var sortOrder: Int
    var metadataJSON: String
    let createdAt: Date
    var updatedAt: Date
}

struct StoryNodeKindDefinition: Identifiable, Hashable {
    let id: String
    let label: String
    let category: String
    let icon: String
}

let STORY_NODE_KINDS: [StoryNodeKindDefinition] = [
    .init(id: "volume", label: "卷纲", category: "架构", icon: "books.vertical"),
    .init(id: "act", label: "幕结构", category: "架构", icon: "rectangle.3.group"),
    .init(id: "outline_section", label: "大纲分段", category: "架构", icon: "list.bullet.indent"),
    .init(id: "premise", label: "故事前提", category: "架构", icon: "sparkles"),
    .init(id: "synopsis", label: "故事梗概", category: "架构", icon: "doc.text"),
    .init(id: "theme", label: "主题表达", category: "架构", icon: "theatermasks"),
    .init(id: "tone_style", label: "基调与文风", category: "架构", icon: "paintbrush"),
    .init(id: "target_reader", label: "目标读者", category: "架构", icon: "person.2"),
    .init(id: "scene", label: "场景卡", category: "剧情", icon: "film.stack"),
    .init(id: "plot_point", label: "情节点", category: "剧情", icon: "point.topleft.down.to.point.bottomright.curvepath"),
    .init(id: "plot_hook", label: "剧情钩子", category: "剧情", icon: "questionmark.circle"),
    .init(id: "conflict", label: "核心冲突", category: "剧情", icon: "bolt.horizontal"),
    .init(id: "suspense", label: "悬念", category: "剧情", icon: "eye"),
    .init(id: "foreshadow", label: "伏笔", category: "剧情", icon: "arrow.triangle.branch"),
    .init(id: "clue", label: "线索", category: "剧情", icon: "magnifyingglass"),
    .init(id: "mystery", label: "谜题", category: "剧情", icon: "questionmark.diamond"),
    .init(id: "twist", label: "反转", category: "剧情", icon: "arrow.triangle.2.circlepath"),
    .init(id: "climax", label: "高潮", category: "剧情", icon: "flame"),
    .init(id: "ending", label: "结局设计", category: "剧情", icon: "flag.checkered"),
    .init(id: "subplot", label: "支线剧情", category: "剧情", icon: "arrow.triangle.branch"),
    .init(id: "character_arc", label: "人物弧光", category: "人物", icon: "chart.line.uptrend.xyaxis"),
    .init(id: "relationship", label: "人物关系", category: "人物", icon: "person.2.wave.2"),
    .init(id: "dialogue_voice", label: "角色声线", category: "人物", icon: "quote.bubble"),
    .init(id: "timeline_event", label: "时间线事件", category: "管理", icon: "calendar.badge.clock"),
    .init(id: "task", label: "创作任务", category: "管理", icon: "checklist"),
    .init(id: "review", label: "审阅意见", category: "管理", icon: "checkmark.seal"),
    .init(id: "comment", label: "批注", category: "管理", icon: "text.bubble"),
    .init(id: "research", label: "研究资料", category: "管理", icon: "books.vertical.circle"),
    .init(id: "inspiration", label: "灵感卡", category: "管理", icon: "lightbulb")
]

func storyNodeKind(_ id: String) -> StoryNodeKindDefinition {
    STORY_NODE_KINDS.first { $0.id == id } ?? .init(id: id, label: id, category: "其他", icon: "rectangle.stack")
}

struct ContentRevision: Identifiable {
    let id: UUID
    let novelID: UUID
    let resourceType: String
    let resourceID: String
    let conversationID: UUID?
    let operation: String
    let snapshotJSON: String
    let createdAt: Date
}

struct Msg: Identifiable {
    let id: UUID
    let novelID: UUID
    let conversationID: UUID
    var role: String // user / assistant
    var content: String
    var skill: String
    var reasoning: String = ""
    var reasoningDuration: Double = 0
    let createdAt: Date
}

// MARK: - 模型输出分段

struct ParsedModelOutput {
    var reasoning: String
    var response: String
    var isThinking: Bool
}

enum ModelOutputParser {
    /// 兼容会把思考过程包在 <think> 或 <analysis> 中的 OpenAI 兼容模型。
    static func parse(_ raw: String) -> ParsedModelOutput {
        var remainder = raw
        var reasoningParts: [String] = []
        var responseParts: [String] = []
        var hasOpenBlock = false

        while true {
            let rawCandidates = [
                ("<think>", "</think>", remainder.range(of: "<think>", options: .caseInsensitive)),
                ("<analysis>", "</analysis>", remainder.range(of: "<analysis>", options: .caseInsensitive)),
            ]
            let candidates: [(String, String, Range<String.Index>)] = rawCandidates.compactMap { candidate in
                guard let range = candidate.2 else { return nil }
                return (candidate.0, candidate.1, range)
            }

            guard let block = candidates.min(by: { $0.2.lowerBound < $1.2.lowerBound }) else {
                responseParts.append(remainder)
                break
            }

            responseParts.append(String(remainder[..<block.2.lowerBound]))
            let bodyStart = block.2.upperBound
            guard let closeRange = remainder.range(of: block.1,
                                                   options: .caseInsensitive,
                                                   range: bodyStart..<remainder.endIndex) else {
                reasoningParts.append(String(remainder[bodyStart...]))
                hasOpenBlock = true
                remainder = ""
                break
            }
            reasoningParts.append(String(remainder[bodyStart..<closeRange.lowerBound]))
            remainder = String(remainder[closeRange.upperBound...])
        }

        return ParsedModelOutput(
            reasoning: reasoningParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines),
            response: responseParts.joined().trimmingCharacters(in: .whitespacesAndNewlines),
            isThinking: hasOpenBlock
        )
    }
}

// MARK: - 会话

/// 聊天会话：一个作品下可开多个独立对话，各自维护历史
struct Conversation: Identifiable {
    let id: UUID
    let novelID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
}

/// 独立会话的后台 Agent 运行状态；与当前 UI 选择解耦并持久化到 SQLite。
struct ConversationRun: Identifiable {
    var id: UUID { conversationID }
    let conversationID: UUID
    let novelID: UUID
    var status: String       // queued / running / completed / needs_attention / failed / cancelled
    var prompt: String
    var agentID: UUID?
    var skillID: String
    var partialText: String
    var error: String
    var reservedCorePercent: Int
    var reservedMemoryMB: Int
    var startedAt: Date?
    var updatedAt: Date
}

// MARK: - Agent（自定义系统提示词）
/// Agent 配置：名称/头像、提示词、模型、参数（温度/top-p/输出上限）、
/// 工具权限、固定/按需技能、知识库（设定库挂载）、AI 自动生成。
struct Agent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String          // emoji 或 SF Symbol 名
    var avatarPath: String? = nil // 自定义本地头像；为空时使用 icon
    var systemPrompt: String
    // 模型与参数覆盖（nil = 跟随全局设置）
    var model: String?
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    // 能力
    var tools: [String]?      // 工具白名单：nil = 跟随全局开关；[] = 禁用；[名称] = 仅这些
    var skills: [String]?     // 旧版兼容字段；新架构统一索引完整技能库
    var fixedSkillID: String? = nil // 固定 Skill：每轮随 Agent 注入；nil = 不固定
    var loreEntryIDs: [UUID]? // 知识库：挂载的设定库条目（按作品，跨作品自动忽略不匹配项）
    var isBuiltin: Bool
}

/// 头像渲染：emoji 直接显示，否则视为 SF Symbol
struct AgentIconView: View {
    let icon: String
    var avatarPath: String? = nil
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let avatarPath,
               FileManager.default.fileExists(atPath: avatarPath),
               let image = agentAvatarThumbnail(atPath: avatarPath, size: size) {
                Image(nsImage: image)
            } else if icon.unicodeScalars.count == 1 || icon.containsEmoji {
                Text(icon)
            } else {
                Image(systemName: icon)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

/// 先把头像绘制为控件所需的实际尺寸，规避 macOS Menu 标签按原图尺寸溢出绘制。
private func agentAvatarThumbnail(atPath path: String, size: CGFloat) -> NSImage? {
    guard size > 0, let source = NSImage(contentsOfFile: path) else { return nil }
    let sourceSize = source.size
    guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

    let cropSide = min(sourceSize.width, sourceSize.height)
    let sourceRect = NSRect(x: (sourceSize.width - cropSide) / 2,
                            y: (sourceSize.height - cropSide) / 2,
                            width: cropSide,
                            height: cropSide)
    let targetSize = NSSize(width: size, height: size)
    let target = NSImage(size: targetSize)
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let targetRect = NSRect(origin: .zero, size: targetSize)
    NSBezierPath(ovalIn: targetRect).addClip()
    source.draw(in: targetRect,
                from: sourceRect,
                operation: .copy,
                fraction: 1)
    target.unlockFocus()
    return target
}

extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmoji }
    }
}

let AGENT_ICON_CHOICES = ["🤖", "🧙", "✍️", "🎭", "📚", "🖋️", "💡", "🔍", "⚔️", "🌌", "🕵️", "🔥",
                          "❄️", "🌸", "🐉", "🦊", "👻", "🧛", "🗡️", "🏰", "⚓️", "🧪", "💎", "👑",
                          "sparkles", "pencil.circle", "bolt.fill", "globe.asia.australia", "book.fill", "wand.and.stars"]

private func builtinAgentAvatarPath(_ name: String) -> String? {
    Bundle.main.path(forResource: name, ofType: "png", inDirectory: "AgentAvatars")
}

let BUILTIN_AGENTS: [Agent] = [
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          name: "创作助手", icon: "🤖", avatarPath: builtinAgentAvatarPath("creative-assistant"),
          systemPrompt: "你是一位资深的中文长篇小说作家与编辑，文笔细腻、结构严谨，擅长网文与严肃文学。"
            + "与用户围绕当前作品进行创作：讨论剧情、人设、世界观时严格基于参考设定；需要创作时直接给出高质量中文文本；回答简洁有条理。",
          model: nil, temperature: nil, topP: nil, maxTokens: nil,
          tools: nil, skills: nil, loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          name: "严苛编辑", icon: "🖋️", avatarPath: builtinAgentAvatarPath("strict-editor"),
          systemPrompt: "你是一位极为挑剔的资深文学编辑，眼毒、嘴毒、心善。"
            + "指出作品在节奏、逻辑、人物动机、语言上的问题，不留情面但给出具体可操作的修改建议；"
            + "点评要短句有力，避免空话套话。",
          model: nil, temperature: 0.6, topP: nil, maxTokens: nil,
          tools: nil, skills: ["consistency", "polish", "chat"], loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          name: "网文速写师", icon: "⚡", avatarPath: builtinAgentAvatarPath("web-fiction-writer"),
          systemPrompt: "你擅长商业网文创作，深谙黄金三章、爽点节奏、钩子设计。"
            + "行文快节奏、强冲突、画面感强；每章结尾必有钩子；对话简洁有张力；适当使用短段落。",
          model: nil, temperature: 0.9, topP: nil, maxTokens: nil,
          tools: nil, skills: ["continue", "scene", "chat"], loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
          name: "世界构建师", icon: "🌍", avatarPath: builtinAgentAvatarPath("world-builder"),
          systemPrompt: "你是严谨的世界观架构师，擅长设定推演与逻辑自洽。"
            + "构建力量体系、地理、势力、历史时注重因果链与细节闭环；发现设定矛盾时直接指出并给出修补方案。",
          model: nil, temperature: 0.7, topP: nil, maxTokens: nil,
          tools: ["search_database", "read_chapter", "list_chapters", "get_outline"],
          skills: ["worldbuilding", "location", "faction", "item", "consistency", "chat"],
          loreEntryIDs: nil, isBuiltin: true),
]

enum AgentStore {
    static let url = AppPaths.dataDir.appendingPathComponent("agents.json")

    /// 内置 + 自定义，自定义优先
    static func load() -> [Agent] {
        var agents = BUILTIN_AGENTS
        if let d = try? Data(contentsOf: url),
           let custom = try? JSONDecoder().decode([Agent].self, from: d) {
            agents.append(contentsOf: custom)
        }
        return agents
    }

    static func save(_ all: [Agent]) {
        let custom = all.filter { !$0.isBuiltin }
        if let d = try? JSONEncoder().encode(custom) {
            try? d.write(to: url, options: .atomic)
        }
    }
}

// MARK: - 模型配置

enum ContextCompressionLevel: String, CaseIterable, Identifiable, Codable {
    case conservative
    case balanced
    case aggressive
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conservative: return "保守（目标压缩 30%）"
        case .balanced: return "均衡（目标压缩 50%）"
        case .aggressive: return "强力（目标压缩 70%）"
        case .custom: return "自定义"
        }
    }

    /// 仅在上下文超出安全输入预算时生效；受保护内容可能使实际保留率更高。
    var targetRetentionRatio: Double {
        switch self {
        case .conservative: return 0.70
        case .balanced: return 0.50
        case .aggressive: return 0.30
        case .custom: return 0.75
        }
    }

    var redundancyThreshold: Double {
        switch self {
        case .conservative: return 0.94
        case .balanced: return 0.82
        case .aggressive: return 0.70
        case .custom: return 0.82
        }
    }
}

struct ModelConfig: Codable {
    var provider = "deepseek"
    var baseURL = "https://api.deepseek.com/v1"
    var apiKey = ""
    var model = "deepseek-chat"
    var temperature = 0.8
    var topP = 1.0                // 采样 top-p
    var maxTokens = 4096          // 最大输出 tokens
    var contextWindow = 32768     // 输入上下文窗口（tokens）
    var enableContextCompression = true
    var contextCompressionLevel: ContextCompressionLevel = .balanced
    var contextCompressionCustomRatio = 0.75
    var enableTools = true        // 写作工具（Tool Use）
    /// 后台 Agent 主要等待网络响应；这里是调度预算，不是 CPU 亲和性或强制绑核。
    var automaticBackgroundScheduling = true
    var backgroundCoreBudget = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
    var backgroundTasksPerCore = 2
    var backgroundMemoryBudgetMB = 2048
    /// 手动模式下分配给每一个会话任务的资源；自动模式会按模型和上下文覆盖它们。
    var conversationCorePercent = 25
    var conversationMemoryMB = 512
    var favoriteSkills: [String] = ["chat", "continue", "outline", "polish"]
    var backgroundOpacity = 0.64  // 默认背景可见度
    var backgroundMediaPath = "" // 用户选择的本地图片或视频（复制到应用数据目录）
    var themeHue = 0.75           // 界面强调色色相
    var themeBrightness = 0.90    // 界面强调色明亮度

    enum CodingKeys: String, CodingKey {
        case provider, baseURL, apiKey, model, temperature, topP, maxTokens, contextWindow
        case enableContextCompression, contextCompressionLevel, contextCompressionCustomRatio
        case enableTools, automaticBackgroundScheduling, backgroundCoreBudget, backgroundTasksPerCore, backgroundMemoryBudgetMB
        case conversationCorePercent, conversationMemoryMB
        case favoriteSkills, backgroundOpacity, backgroundMediaPath, themeHue, themeBrightness, themeColor
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? "deepseek"
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com/v1"
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? "deepseek-chat"
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.8
        topP = try values.decodeIfPresent(Double.self, forKey: .topP) ?? 1.0
        maxTokens = try values.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow) ?? 32768
        enableContextCompression = try values.decodeIfPresent(Bool.self, forKey: .enableContextCompression) ?? true
        contextCompressionLevel = try values.decodeIfPresent(ContextCompressionLevel.self, forKey: .contextCompressionLevel) ?? .balanced
        contextCompressionCustomRatio = try values.decodeIfPresent(Double.self, forKey: .contextCompressionCustomRatio) ?? 0.75
        enableTools = try values.decodeIfPresent(Bool.self, forKey: .enableTools) ?? true
        automaticBackgroundScheduling = try values.decodeIfPresent(Bool.self, forKey: .automaticBackgroundScheduling) ?? true
        let savedCoreBudget = try values.decodeIfPresent(Int.self, forKey: .backgroundCoreBudget)
            ?? min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
        backgroundCoreBudget = max(1, min(savedCoreBudget, ProcessInfo.processInfo.activeProcessorCount))
        let savedTasksPerCore = try values.decodeIfPresent(Int.self, forKey: .backgroundTasksPerCore) ?? 2
        backgroundTasksPerCore = max(1, min(savedTasksPerCore, 8))
        let savedMemoryBudget = try values.decodeIfPresent(Int.self, forKey: .backgroundMemoryBudgetMB) ?? 2048
        backgroundMemoryBudgetMB = max(256, min(savedMemoryBudget, ModelConfig.availableMemoryMB))
        conversationCorePercent = max(10, min(try values.decodeIfPresent(Int.self, forKey: .conversationCorePercent) ?? 25, 400))
        conversationMemoryMB = max(128, min(try values.decodeIfPresent(Int.self, forKey: .conversationMemoryMB) ?? 512,
                                             ModelConfig.availableMemoryMB))
        favoriteSkills = try values.decodeIfPresent([String].self, forKey: .favoriteSkills) ?? ["chat", "continue", "outline", "polish"]
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.64
        backgroundMediaPath = try values.decodeIfPresent(String.self, forKey: .backgroundMediaPath) ?? ""
        let legacyTheme = try values.decodeIfPresent(String.self, forKey: .themeColor)
        let legacyHue: Double = {
            switch legacyTheme {
            case "blue": return 0.60
            case "pink": return 0.92
            case "green": return 0.36
            case "orange": return 0.08
            default: return 0.75
            }
        }()
        themeHue = try values.decodeIfPresent(Double.self, forKey: .themeHue) ?? legacyHue
        themeBrightness = try values.decodeIfPresent(Double.self, forKey: .themeBrightness) ?? 0.90
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(provider, forKey: .provider)
        try values.encode(baseURL, forKey: .baseURL)
        try values.encode(apiKey, forKey: .apiKey)
        try values.encode(model, forKey: .model)
        try values.encode(temperature, forKey: .temperature)
        try values.encode(topP, forKey: .topP)
        try values.encode(maxTokens, forKey: .maxTokens)
        try values.encode(contextWindow, forKey: .contextWindow)
        try values.encode(enableContextCompression, forKey: .enableContextCompression)
        try values.encode(contextCompressionLevel, forKey: .contextCompressionLevel)
        try values.encode(contextCompressionCustomRatio, forKey: .contextCompressionCustomRatio)
        try values.encode(enableTools, forKey: .enableTools)
        try values.encode(automaticBackgroundScheduling, forKey: .automaticBackgroundScheduling)
        try values.encode(backgroundCoreBudget, forKey: .backgroundCoreBudget)
        try values.encode(backgroundTasksPerCore, forKey: .backgroundTasksPerCore)
        try values.encode(backgroundMemoryBudgetMB, forKey: .backgroundMemoryBudgetMB)
        try values.encode(conversationCorePercent, forKey: .conversationCorePercent)
        try values.encode(conversationMemoryMB, forKey: .conversationMemoryMB)
        try values.encode(favoriteSkills, forKey: .favoriteSkills)
        try values.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try values.encode(backgroundMediaPath, forKey: .backgroundMediaPath)
        try values.encode(themeHue, forKey: .themeHue)
        try values.encode(themeBrightness, forKey: .themeBrightness)
    }
}

extension ModelConfig {
    static var availableLogicalCores: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }
    static var availableMemoryMB: Int { max(512, Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)) }

    var estimatedConversationContextMemoryMB: Int {
        max(32, max(0, contextWindow) * 64 / 1_000_000)
    }

    /// 包括梯形目录、最多四个已加载叶组、工具参数/结果以及下一轮请求副本。
    var estimatedConversationToolMemoryMB: Int { enableTools ? 96 : 24 }

    var estimatedConversationOutputMemoryMB: Int {
        max(16, max(0, maxTokens) * 32 / 1_000_000)
    }

    /// 每个会话独立持有的保守工作集，多个并行会话按此数值累加。
    var estimatedBackgroundTaskMemoryMB: Int {
        min(4096, 48 + estimatedConversationContextMemoryMB
            + estimatedConversationToolMemoryMB + estimatedConversationOutputMemoryMB)
    }

    /// 每个会话在调度器中独立保留的 CPU 份额，100 表示一个逻辑核心。
    var plannedConversationCorePercent: Int {
        automaticBackgroundScheduling
            ? (provider == "ollama" ? 100 : (enableTools ? 30 : 20))
            : max(10, min(conversationCorePercent, 400))
    }

    /// 每个会话独立保留的工作集，不是整个应用共用的单个任务预算。
    var plannedConversationMemoryMB: Int {
        automaticBackgroundScheduling ? estimatedBackgroundTaskMemoryMB : max(128, min(conversationMemoryMB, Self.availableMemoryMB))
    }

    /// 为避免挤占编辑器和系统，后台会话池最多使用约 80% CPU 份额与 50% 物理内存。
    var backgroundCoreCapacityPercent: Int { max(100, Self.availableLogicalCores * 80) }
    var backgroundMemoryCapacityMB: Int { max(512, Self.availableMemoryMB / 2) }

    /// 网络型 Agent 可在一个核心预算上挂多个等待中的任务，最终仍由 macOS 调度实际线程。
    var backgroundConcurrencyLimit: Int {
        let processorLimit = max(1, backgroundCoreCapacityPercent / plannedConversationCorePercent)
        let memoryLimit = max(1, backgroundMemoryCapacityMB / plannedConversationMemoryMB)
        return min(64, processorLimit, memoryLimit)
    }

    var tintColor: Color {
        Color(hue: themeHue, saturation: 0.78, brightness: themeBrightness)
    }
}

// MARK: - 消息与工具调用（Tool Use）

struct ToolCall: Identifiable {
    var id: String
    var name: String
    var arguments: String   // JSON 字符串（流式分片累积）
}

struct ChatMsg {
    var role: String            // user / assistant / tool
    var content: String
    var toolCallID: String?     // role == "tool" 时回填
    var toolCalls: [ToolCall]?  // role == "assistant" 且调用工具时
}

struct ProviderPreset {
    let label: String
    let baseURL: String
    let models: [String]
}

struct ProviderSection: Identifiable {
    let id: String
    let title: String
    let providerIDs: [String]
}

let PROVIDERS: [String: ProviderPreset] = [
    // 国产厂商（均使用 OpenAI 兼容接口）
    "deepseek": ProviderPreset(label: "DeepSeek 深度求索", baseURL: "https://api.deepseek.com",
                               models: ["deepseek-v4-flash", "deepseek-v4-pro"]),
    "dashscope": ProviderPreset(label: "阿里云百炼 · 通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                                models: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen3-coder-plus"]),
    "moonshot": ProviderPreset(label: "月之暗面 · Kimi", baseURL: "https://api.moonshot.cn/v1",
                               models: ["kimi-k2.5", "kimi-k2-turbo-preview", "moonshot-v1-128k", "moonshot-v1-32k"]),
    "zhipu": ProviderPreset(label: "智谱 AI · GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
                            models: ["glm-5", "glm-4.7", "glm-4.5-air", "glm-4-flash"]),
    "qianfan": ProviderPreset(label: "百度千帆 · 文心", baseURL: "https://qianfan.baidubce.com/v2",
                              models: ["ernie-4.5-turbo-20260402", "deepseek-v4-flash", "glm-5"]),
    "hunyuan": ProviderPreset(label: "腾讯混元", baseURL: "https://api.hunyuan.cloud.tencent.com/v1",
                              models: ["hunyuan-turbos-latest", "hunyuan-t1-latest", "hunyuan-a13b"]),
    "volcengine": ProviderPreset(label: "火山方舟 · 豆包", baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                                 models: ["doubao-seed-2-0-lite-260215", "doubao-seed-2-0-pro-260215", "doubao-seed-1-6-flash-250828"]),
    "minimax": ProviderPreset(label: "MiniMax", baseURL: "https://api.minimaxi.com/v1",
                              models: ["MiniMax-M2.7", "MiniMax-M2.7-highspeed", "MiniMax-M2.5", "MiniMax-M2.5-highspeed"]),

    // 海外厂商
    "openai": ProviderPreset(label: "OpenAI", baseURL: "https://api.openai.com/v1",
                             models: ["gpt-5.4", "gpt-5.4-mini", "gpt-5.2", "gpt-4.1", "gpt-4.1-mini"]),
    "anthropic": ProviderPreset(label: "Anthropic Claude", baseURL: "https://api.anthropic.com",
                                models: ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]),
    "gemini": ProviderPreset(label: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                             models: ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-flash-latest"]),
    "mistral": ProviderPreset(label: "Mistral AI", baseURL: "https://api.mistral.ai/v1",
                              models: ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest", "codestral-latest"]),
    "xai": ProviderPreset(label: "xAI · Grok", baseURL: "https://api.x.ai/v1",
                          models: ["grok-4", "grok-4-fast", "grok-3"]),
    "groq": ProviderPreset(label: "GroqCloud", baseURL: "https://api.groq.com/openai/v1",
                           models: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.6-27b", "groq/compound"]),
    "cohere": ProviderPreset(label: "Cohere", baseURL: "https://api.cohere.ai/compatibility/v1",
                             models: ["command-a-03-2025", "command-r-plus-08-2024", "command-r-08-2024"]),
    "openrouter": ProviderPreset(label: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                                 models: ["openrouter/auto", "openai/gpt-5.4", "anthropic/claude-sonnet-4.6", "google/gemini-3.7-flash"]),

    // 本地与自定义
    "ollama": ProviderPreset(label: "Ollama 本地", baseURL: "http://127.0.0.1:11434/v1", models: []),
    "custom": ProviderPreset(label: "自定义（OpenAI 兼容）", baseURL: "", models: []),
]

let PROVIDER_SECTIONS: [ProviderSection] = [
    ProviderSection(id: "domestic", title: "国产厂商", providerIDs: [
        "deepseek", "dashscope", "moonshot", "zhipu", "qianfan", "hunyuan", "volcengine", "minimax",
    ]),
    ProviderSection(id: "overseas", title: "海外厂商", providerIDs: [
        "openai", "anthropic", "gemini", "mistral", "xai", "groq", "cohere", "openrouter",
    ]),
    ProviderSection(id: "local", title: "本地与自定义", providerIDs: ["ollama", "custom"]),
]

final class ConfigStore {
    static func load() -> ModelConfig {
        if let d = try? Data(contentsOf: AppPaths.configURL),
           let c = try? JSONDecoder().decode(ModelConfig.self, from: d) {
            return c
        }
        return ModelConfig()
    }
    static func save(_ c: ModelConfig) {
        if let d = try? JSONEncoder().encode(c) {
            try? d.write(to: AppPaths.configURL, options: .atomic)
        }
    }
}
