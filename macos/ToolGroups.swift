import Foundation

/// 可递归的梯形工具目录：根域 → 子域 → 操作叶子 → 详细 Function Schema。
enum ToolGroups {
    struct Node {
        let id: String
        let parentID: String?
        let label: String
        let description: String
        let toolNames: Set<String>
        var loaderName: String { "open_tools_" + id.replacingOccurrences(of: ".", with: "_") }
        var isLeaf: Bool { !toolNames.isEmpty }
    }

    private static func branch(_ id: String, _ parent: String?, _ label: String, _ description: String) -> Node {
        Node(id: id, parentID: parent, label: label, description: description, toolNames: [])
    }
    private static func leaf(_ id: String, _ parent: String, _ label: String, _ description: String, _ names: [String]) -> Node {
        Node(id: id, parentID: parent, label: label, description: description, toolNames: Set(names))
    }

    static let nodes: [Node] = [
        branch("content", nil, "创作内容", "书籍、章节、正文结构与交换文件。"),
        branch("knowledge", nil, "知识与设定", "世界观设定、资料检索与写法参考库。"),
        branch("workflow", nil, "创作工作流", "多会话、Agent 与 Markdown Skills。"),
        branch("workspace", nil, "工作区管理", "全局状态、跨书检索与非敏感偏好。"),

        branch("content.books", "content", "书籍", "书库、统计、资料和生命周期。"),
        branch("content.chapters", "content", "章节", "章节读取、写作、编辑和结构调整。"),
        branch("content.files", "content", "导入导出", "书籍交换文件与 Exports 目录。"),
        branch("content.structure", "content", "书籍规划卡片", "大纲架构、剧情推进、人物弧光与创作管理卡片；作品事实统一归设定库。"),
        branch("content.revisions", "content", "版本与恢复", "内容快照、比较和安全恢复。"),
        leaf("content.books.read", "content.books", "浏览与统计", "列书、资料、大纲和篇幅统计。",
             ["list_books", "get_book", "get_story_stats", "get_outline"]),
        leaf("content.books.write", "content.books", "创建与修改", "创建书籍或修改基础资料。",
             ["create_book", "update_book"]),
        leaf("content.books.delete", "content.books", "删除书籍", "带标题校验的整书级联删除。", ["delete_book"]),
        leaf("content.chapters.read", "content.chapters", "读取章节", "列出章节或读取正文。",
             ["list_chapters", "read_chapter"]),
        leaf("content.chapters.write", "content.chapters", "创建与续写", "单章、批量写章、替换或追加正文。",
             ["create_chapter", "batch_create_chapters", "update_chapter"]),
        leaf("content.chapters.patch", "content.chapters", "局部编辑", "使用唯一原文锚点精准修改。", ["replace_chapter_text"]),
        leaf("content.chapters.structure", "content.chapters", "章节结构", "复制、移动、拆分和合并。",
             ["move_chapter", "duplicate_chapter", "split_chapter", "merge_chapters"]),
        leaf("content.chapters.delete", "content.chapters", "删除章节", "带标题校验删除章节。", ["delete_chapter"]),
        leaf("content.files.exchange", "content.files", "书籍交换", "导入或导出 .zhinovel.json。",
             ["export_book_file", "import_book_file"]),
        leaf("content.files.manage", "content.files", "导出文件管理", "列出和删除专用 Exports 文件。",
             ["list_exported_files", "delete_exported_file"]),
        leaf("content.files.authorized", "content.files", "授权导入区", "仅浏览或删除 Imports 授权目录文件。",
             ["list_authorized_import_files", "delete_authorized_import_file"]),
        leaf("content.structure.read", "content.structure", "读取结构", "列出或读取全部创作结构种类。",
             ["list_story_nodes", "get_story_node"]),
        leaf("content.structure.write", "content.structure", "维护结构", "创建、批量创建或修改创作结构。",
             ["create_story_node", "batch_create_story_nodes", "update_story_node"]),
        leaf("content.structure.delete", "content.structure", "删除结构", "带标题校验删除创作结构。", ["delete_story_node"]),
        leaf("content.revisions.read", "content.revisions", "浏览与比较", "列出、读取或比较内容版本。",
             ["list_content_revisions", "get_content_revision", "compare_content_revisions"]),
        leaf("content.revisions.restore", "content.revisions", "恢复版本", "带资源 ID 校验恢复内容版本。", ["restore_content_revision"]),

        branch("knowledge.lore", "knowledge", "设定库", "人物、地点、势力、物品、世界与历史事实的唯一数据源。"),
        branch("knowledge.vectors", "knowledge", "写法向量库", "写法资料的检索、编辑和索引。"),
        leaf("knowledge.lore.read", "knowledge.lore", "检索与读取", "搜索、列出和读取完整设定。",
             ["search_database", "list_lore_entries", "read_lore_entry"]),
        leaf("knowledge.lore.write", "knowledge.lore", "创建与修改", "创建或修改设定。",
             ["create_lore_entry", "update_lore_entry"]),
        leaf("knowledge.lore.delete", "knowledge.lore", "删除设定", "带标题校验删除设定。", ["delete_lore_entry"]),
        leaf("knowledge.vectors.read", "knowledge.vectors", "浏览与检索", "浏览、语义检索和写法画像。",
             ["list_vector_libraries", "get_vector_library", "search_vector_library", "list_vector_chapters", "read_vector_chapter", "get_style_profile"]),
        leaf("knowledge.vectors.write", "knowledge.vectors", "导入与编辑", "导入 TXT、编辑并重建索引。",
             ["import_vector_txt", "update_vector_library", "update_vector_chapter"]),
        leaf("knowledge.vectors.delete", "knowledge.vectors", "删除向量库", "带标题校验删除向量库。", ["delete_vector_library"]),

        branch("workflow.conversations", "workflow", "多会话", "会话记录与生命周期。"),
        branch("workflow.agents", "workflow", "Agent 工作室", "Agent 配置与权限。"),
        branch("workflow.skills", "workflow", "Markdown Skills", "技能指令与本地文件。"),
        leaf("workflow.conversations.read", "workflow.conversations", "浏览会话", "列出和读取记录。",
             ["list_conversations", "read_conversation", "list_all_conversations", "get_conversation_run", "wait_conversations"]),
        leaf("workflow.conversations.write", "workflow.conversations", "创建与重命名", "创建或重命名会话。",
             ["create_conversation", "rename_conversation", "send_message_to_conversation"]),
        leaf("workflow.conversations.delete", "workflow.conversations", "清空与删除", "带标题校验清空或删除。",
             ["clear_conversation", "delete_conversation", "cancel_conversation_run"]),
        leaf("workflow.agents.read", "workflow.agents", "浏览 Agent", "列出和读取 Agent。", ["list_agents", "get_agent"]),
        leaf("workflow.agents.write", "workflow.agents", "创建与修改", "创建、修改或复制 Agent。",
             ["create_agent", "update_agent", "duplicate_agent"]),
        leaf("workflow.agents.delete", "workflow.agents", "删除 Agent", "带名称校验删除自定义 Agent。", ["delete_agent"]),
        leaf("workflow.skills.read", "workflow.skills", "浏览 Skills", "列出和读取 Skills。", ["list_skills", "get_skill"]),
        leaf("workflow.skills.write", "workflow.skills", "创建与修改", "创建或修改 Markdown Skill。",
             ["create_skill", "update_skill"]),
        leaf("workflow.skills.delete", "workflow.skills", "删除 Skill", "带名称校验删除 Skill。", ["delete_skill"]),

        leaf("workspace.inspect", "workspace", "状态与跨书搜索", "读取状态或跨书搜索。",
             ["get_workspace_state", "search_workspace"]),
        leaf("workspace.preferences", "workspace", "非敏感偏好", "读取或修改不含 API Key 的偏好。",
             ["get_workspace_preferences", "update_workspace_preferences"]),
        branch("workspace.governance", "workspace", "能力与边界", "工具域、Schema、权限、覆盖和会话资源锁。"),
        leaf("workspace.governance.describe", "workspace.governance", "目录与 Schema", "查询机器可读的工具和数据模型。",
             ["describe_tool_domains", "get_workspace_schema", "get_tool_coverage"]),
        leaf("workspace.governance.security", "workspace.governance", "权限与安全", "查询权限边界和资源锁。",
             ["get_tool_boundaries", "get_permission_scope", "list_resource_locks"]),
    ]

    static var roots: [Node] { nodes.filter { $0.parentID == nil } }
    static func children(of id: String) -> [Node] { nodes.filter { $0.parentID == id } }
    static func node(forLoader name: String) -> Node? { nodes.first { $0.loaderName == name } }

    static func descendantToolNames(of nodeID: String) -> Set<String> {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return [] }
        if node.isLeaf { return node.toolNames }
        return children(of: nodeID).reduce(into: Set<String>()) { result, child in
            result.formUnion(descendantToolNames(of: child.id))
        }
    }

    static func visibleNodes(parentID: String?, allowedNames: Set<String>?) -> [Node] {
        let candidates = parentID.map(children(of:)) ?? roots
        guard let allowedNames else { return candidates }
        return candidates.filter { !descendantToolNames(of: $0.id).isDisjoint(with: allowedNames) }
    }

    static func loaderDefinitions(for nodes: [Node]) -> [[String: Any]] {
        nodes.map { node in
            ["type": "function", "function": [
                "name": node.loaderName,
                "description": node.isLeaf
                    ? "加载【\(node.label)】详细工具：\(node.description)"
                    : "展开【\(node.label)】下一层目录：\(node.description)",
                "parameters": ["type": "object", "properties": [:]]
            ]]
        }
    }

    static func detailedDefinitions(for leaf: Node, allDefinitions: [[String: Any]], allowedNames: Set<String>?) -> [[String: Any]] {
        let permitted = allowedNames.map { leaf.toolNames.intersection($0) } ?? leaf.toolNames
        return allDefinitions.filter { definition in
            guard let fn = definition["function"] as? [String: Any], let name = fn["name"] as? String else { return false }
            return permitted.contains(name)
        }
    }

    static func breadcrumb(for node: Node) -> [Node] {
        var result = [node]
        var parent = node.parentID
        while let id = parent, let found = nodes.first(where: { $0.id == id }) {
            result.insert(found, at: 0); parent = found.parentID
        }
        return result
    }
}
