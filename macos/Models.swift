import Foundation
import SwiftUI

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

struct Msg: Identifiable {
    let id: UUID
    let novelID: UUID
    let conversationID: UUID
    var role: String // user / assistant
    var content: String
    var skill: String
    let createdAt: Date
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

// MARK: - Agent（自定义系统提示词）
/// Agent 配置：名称/头像、提示词、模型、参数（温度/top-p/输出上限）、
/// 工具权限、技能绑定、知识库（设定库挂载）、AI 自动生成。
struct Agent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String          // emoji 或 SF Symbol 名
    var systemPrompt: String
    // 模型与参数覆盖（nil = 跟随全局设置）
    var model: String?
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    // 能力
    var tools: [String]?      // 工具白名单：nil = 跟随全局开关；[] = 禁用；[名称] = 仅这些
    var skills: [String]?     // 技能白名单：nil = 全部技能；[id] = 仅这些
    var loreEntryIDs: [UUID]? // 知识库：挂载的设定库条目（按作品，跨作品自动忽略不匹配项）
    var isBuiltin: Bool
}

/// 头像渲染：emoji 直接显示，否则视为 SF Symbol
struct AgentIconView: View {
    let icon: String
    var body: some View {
        if icon.unicodeScalars.count == 1 || icon.containsEmoji {
            Text(icon)
        } else {
            Image(systemName: icon)
        }
    }
}

extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmoji }
    }
}

let AGENT_ICON_CHOICES = ["🤖", "🧙", "✍️", "🎭", "📚", "🖋️", "💡", "🔍", "⚔️", "🌌", "🕵️", "🔥",
                          "❄️", "🌸", "🐉", "🦊", "👻", "🧛", "🗡️", "🏰", "⚓️", "🧪", "💎", "👑",
                          "sparkles", "pencil.circle", "bolt.fill", "globe.asia.australia", "book.fill", "wand.and.stars"]

let BUILTIN_AGENTS: [Agent] = [
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          name: "创作助手", icon: "🤖",
          systemPrompt: "你是一位资深的中文长篇小说作家与编辑，文笔细腻、结构严谨，擅长网文与严肃文学。"
            + "与用户围绕当前作品进行创作：讨论剧情、人设、世界观时严格基于参考设定；需要创作时直接给出高质量中文文本；回答简洁有条理。",
          model: nil, temperature: nil, topP: nil, maxTokens: nil,
          tools: nil, skills: nil, loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          name: "严苛编辑", icon: "🖋️",
          systemPrompt: "你是一位极为挑剔的资深文学编辑，眼毒、嘴毒、心善。"
            + "指出作品在节奏、逻辑、人物动机、语言上的问题，不留情面但给出具体可操作的修改建议；"
            + "点评要短句有力，避免空话套话。",
          model: nil, temperature: 0.6, topP: nil, maxTokens: nil,
          tools: nil, skills: ["consistency", "polish", "chat"], loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          name: "网文速写师", icon: "⚡",
          systemPrompt: "你擅长商业网文创作，深谙黄金三章、爽点节奏、钩子设计。"
            + "行文快节奏、强冲突、画面感强；每章结尾必有钩子；对话简洁有张力；适当使用短段落。",
          model: nil, temperature: 0.9, topP: nil, maxTokens: nil,
          tools: nil, skills: ["continue", "scene", "chat"], loreEntryIDs: nil, isBuiltin: true),
    Agent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
          name: "世界构建师", icon: "🌍",
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

struct ModelConfig: Codable {
    var provider = "deepseek"
    var baseURL = "https://api.deepseek.com/v1"
    var apiKey = ""
    var model = "deepseek-chat"
    var temperature = 0.8
    var topP = 1.0                // 采样 top-p
    var maxTokens = 4096          // 最大输出 tokens
    var contextWindow = 32768     // 输入上下文窗口（tokens）
    var enableTools = true        // 写作工具（Tool Use）
    var favoriteSkills: [String] = ["chat", "continue", "outline", "polish"]
    var backgroundOpacity = 0.64  // 默认背景可见度
    var themeHue = 0.75           // 界面强调色色相
    var themeBrightness = 0.90    // 界面强调色明亮度

    enum CodingKeys: String, CodingKey {
        case provider, baseURL, apiKey, model, temperature, topP, maxTokens, contextWindow
        case enableTools, favoriteSkills, backgroundOpacity, themeHue, themeBrightness, themeColor
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
        enableTools = try values.decodeIfPresent(Bool.self, forKey: .enableTools) ?? true
        favoriteSkills = try values.decodeIfPresent([String].self, forKey: .favoriteSkills) ?? ["chat", "continue", "outline", "polish"]
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.64
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
        try values.encode(enableTools, forKey: .enableTools)
        try values.encode(favoriteSkills, forKey: .favoriteSkills)
        try values.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try values.encode(themeHue, forKey: .themeHue)
        try values.encode(themeBrightness, forKey: .themeBrightness)
    }
}

extension ModelConfig {
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

let PROVIDERS: [String: ProviderPreset] = [
    "deepseek": ProviderPreset(label: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
                               models: ["deepseek-chat", "deepseek-reasoner"]),
    "openai": ProviderPreset(label: "OpenAI", baseURL: "https://api.openai.com/v1",
                             models: ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "o3-mini"]),
    "anthropic": ProviderPreset(label: "Anthropic Claude", baseURL: "https://api.anthropic.com",
                                models: ["claude-sonnet-4-5", "claude-sonnet-4-20250514", "claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"]),
    "ollama": ProviderPreset(label: "Ollama 本地", baseURL: "http://127.0.0.1:11434/v1", models: []),
    "openrouter": ProviderPreset(label: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                                 models: ["openrouter/auto"]),
    "moonshot": ProviderPreset(label: "Kimi 月之暗面", baseURL: "https://api.moonshot.cn/v1",
                               models: ["kimi-k2-0711-preview", "moonshot-v1-32k", "moonshot-v1-8k"]),
    "zhipu": ProviderPreset(label: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
                            models: ["glm-4-plus", "glm-4-air", "glm-4-flash"]),
    "custom": ProviderPreset(label: "自定义（OpenAI 兼容）", baseURL: "", models: []),
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
