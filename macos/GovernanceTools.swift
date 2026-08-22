import Foundation

/// 工具系统自身的可查询边界，以及通用创作结构、版本和安全导入能力。
@MainActor
enum GovernanceTools {
    typealias JSON = [String: Any]
    static let storyKinds = STORY_NODE_KINDS.map(\.id)
    static let catalog: [(String, String)] = [
        ("describe_tool_domains", "列出工具域与梯形目录"),
        ("get_workspace_schema", "读取工作区资源模型"),
        ("get_tool_boundaries", "读取工具权限和安全边界"),
        ("get_permission_scope", "读取当前 Agent 的工具权限"),
        ("get_tool_coverage", "读取对象与操作覆盖矩阵"),
        ("list_resource_locks", "列出跨会话写资源占用"),
        ("list_authorized_import_files", "列出授权导入区文件"),
        ("delete_authorized_import_file", "删除授权导入区文件"),
        ("list_story_nodes", "列出卷、场景、情节等结构对象"),
        ("get_story_node", "读取创作结构对象"),
        ("create_story_node", "创建创作结构对象"),
        ("batch_create_story_nodes", "批量创建创作结构对象"),
        ("update_story_node", "修改创作结构对象"),
        ("delete_story_node", "删除创作结构对象"),
        ("list_content_revisions", "列出内容版本快照"),
        ("get_content_revision", "读取版本快照"),
        ("compare_content_revisions", "比较两个版本快照"),
        ("restore_content_revision", "恢复内容版本")
    ]

    private static func definition(_ name: String, _ description: String, _ properties: JSON = [:], required: [String] = []) -> JSON {
        var schema: JSON = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["type": "function", "function": ["name": name, "description": description, "parameters": schema]]
    }
    private static func string(_ description: String = "") -> JSON { ["type": "string", "description": description] }
    private static func integer(_ description: String = "") -> JSON { ["type": "integer", "description": description] }
    private static func strings(_ description: String = "") -> JSON { ["type": "array", "description": description, "items": ["type": "string"]] }

    static let definitions: [[String: Any]] = [
        definition("describe_tool_domains", "返回根域、子域、叶组、工具数量和加载规则"),
        definition("get_workspace_schema", "返回书籍、章节、设定、创作结构、会话、Agent、Skill、向量库、版本和文件的字段及关系"),
        definition("get_tool_boundaries", "返回只读/写入/删除边界、路径边界、分页限制、会话隔离和禁止访问项"),
        definition("get_permission_scope", "返回当前 Agent 的详细工具白名单与可见域"),
        definition("get_tool_coverage", "按资源类型返回 CRUD、批量、版本、搜索和冲突能力覆盖"),
        definition("list_resource_locks", "列出当前写资源锁、占用会话和资源键"),
        definition("list_authorized_import_files", "列出应用 Imports 授权目录内可供导入的文件"),
        definition("delete_authorized_import_file", "从 Imports 授权目录删除文件，必须准确复述文件名", [
            "filename": string(), "expected_filename": string()], required: ["filename", "expected_filename"]),
        definition("list_story_nodes", "列出指定书籍的全部创作卡片，包括架构、剧情、人物、世界与管理类卡片", [
            "book_id": string("省略使用当前书籍"), "kind": ["type": "string", "enum": storyKinds],
            "parent_id": string("可选父对象 UUID")]),
        definition("get_story_node", "读取一个完整创作结构对象", ["node_id": string()], required: ["node_id"]),
        definition("create_story_node", "创建创作结构对象", storyProperties(includeID: false), required: ["kind", "title"]),
        definition("batch_create_story_nodes", "一次创建多个创作结构对象", [
            "book_id": string("省略使用当前书籍"), "nodes": ["type": "array", "items": ["type": "object", "properties": storyProperties(includeID: false), "required": ["kind", "title"]]]], required: ["nodes"]),
        definition("update_story_node", "修改创作结构对象；省略字段保持不变", storyProperties(includeID: true), required: ["node_id"]),
        definition("delete_story_node", "删除创作结构对象；必须准确复述标题", [
            "node_id": string(), "expected_title": string()], required: ["node_id", "expected_title"]),
        definition("list_content_revisions", "列出书籍内容版本，可按资源类型和 ID 过滤", [
            "book_id": string(), "resource_type": string("book/chapter/lore/story_node"), "resource_id": string(), "limit": integer()]),
        definition("get_content_revision", "读取一个版本的完整 JSON 快照", ["revision_id": string()], required: ["revision_id"]),
        definition("compare_content_revisions", "比较两个版本快照，返回大小和首个差异位置", [
            "left_revision_id": string(), "right_revision_id": string()], required: ["left_revision_id", "right_revision_id"]),
        definition("restore_content_revision", "恢复版本；必须准确提供资源 ID，恢复前会再次生成快照", [
            "revision_id": string(), "expected_resource_id": string()], required: ["revision_id", "expected_resource_id"])
    ]

    private static func storyProperties(includeID: Bool) -> JSON {
        var properties: JSON = [
            "book_id": string("省略使用当前书籍"),
            "kind": ["type": "string", "enum": storyKinds], "title": string(), "content": string(),
            "status": string("draft/active/resolved/archived"), "parent_id": string(),
            "clear_parent": ["type": "boolean"], "sort_order": integer(),
            "metadata": ["type": "object", "description": "自由 JSON 元数据"]
        ]
        if includeID { properties["node_id"] = string() }
        return properties
    }

    static var importsDirectory: URL {
        let url = AppPaths.dataDir.appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    static func authorizedImportURL(_ rawPath: String) -> URL? {
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let exports = AppPaths.dataDir.appendingPathComponent("Exports", isDirectory: true).standardizedFileURL
        let roots = [importsDirectory, exports].map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        guard roots.contains(where: { url.path.hasPrefix($0) }), !url.lastPathComponent.hasPrefix(".") else { return nil }
        return url
    }

    static func execute(_ call: ToolCall, app: AppState) -> String? {
        guard catalog.contains(where: { $0.0 == call.name }) else { return nil }
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? JSON ?? [:]
        switch call.name {
        case "describe_tool_domains": return describeDomains()
        case "get_workspace_schema": return workspaceSchema
        case "get_tool_boundaries": return boundaries
        case "get_permission_scope": return permissionScope(app)
        case "get_tool_coverage": return coverage
        case "list_resource_locks": return listLocks(app)
        case "list_authorized_import_files": return listImports()
        case "delete_authorized_import_file": return deleteImport(args)
        case "list_story_nodes": return listNodes(args, app)
        case "get_story_node": return getNode(args, app)
        case "create_story_node": return createNode(args, app)
        case "batch_create_story_nodes": return batchCreateNodes(args, app)
        case "update_story_node": return updateNode(args, app)
        case "delete_story_node": return deleteNode(args, app)
        case "list_content_revisions": return listRevisions(args, app)
        case "get_content_revision": return getRevision(args, app)
        case "compare_content_revisions": return compareRevisions(args, app)
        case "restore_content_revision": return restoreRevision(args, app)
        default: return nil
        }
    }

    private static func describeDomains() -> String {
        ToolGroups.nodes.map { node in
            let count = ToolGroups.descendantToolNames(of: node.id).count
            return "\(node.parentID == nil ? "根域" : (node.isLeaf ? "叶组" : "分支")) · \(node.id) · \(node.label) · \(count) 工具 · loader: \(node.loaderName)"
        }.joined(separator: "\n")
    }

    private static let workspaceSchema = """
    book → chapters / lore / story_nodes / conversations / revisions
    book: id,title,description,outline,metadata(作者、题材、平台、目标、规则、出版等)
    chapter: id,book_id,number,title,content,created_at,updated_at
    lore: id,book_id,type,title,content,keywords,pinned
    story_node: id,book_id,kind((STORY_NODE_KINDS.count) planning kinds),title,content,status,parent_id,sort_order,metadata
    boundary: character/location/faction/item/world/history facts are canonical lore entries, not duplicated story nodes
    conversation: id,book_id,title,messages,run(status,resource reservation)
    agent: prompt/model/sampling/tool whitelist/skill whitelist/lore bindings
    skill: Markdown instruction/category/context chapters
    vector_library → vector_chapters / chunks
    revision: resource_type,resource_id,conversation_id,operation,snapshot,created_at
    file: only Imports authorization area and Exports exchange area
    """

    private static let boundaries = """
    读取：仅限应用管理的 SQLite、向量库、Imports 与 Exports；长内容必须分页。
    写入：必须绑定明确资源 ID 或当前书籍；跨会话资源锁阻止静默覆盖。
    删除：要求准确复述标题、名称或文件名；支持的内容会在永久操作前生成版本。
    文件：禁止访问任意文件系统路径；导入路径必须位于应用 Imports/Exports 管理目录。
    密钥：永不返回 API Key；工具不能修改模型商、Base URL 或 API Key。
    执行：不提供终端、进程执行、任意网络请求、浏览器控制或操作系统设置。
    权限：Agent 工具名白名单在目录和详细 Schema 可见之前生效。
    """

    private static let coverage = """
    books: CRUD + metadata + stats + exchange + revisions
    chapters: CRUD + batch create + precise patch + structure + pagination + revisions + locks
    lore: CRUD + search + revisions + locks
    story_nodes: (STORY_NODE_KINDS.count) planning kinds + CRUD + batch create + hierarchy + revisions + locks + shared UI cards
    lore: canonical character/location/faction/item/world/history facts, also projected into the book workspace
    conversations: CRUD + dispatch + status + wait + cancel + resource isolation
    agents/skills: CRUD + duplication/permissions
    vectors: import/read/search/update/delete/reindex-on-update
    files: authorized Imports + managed Exports; arbitrary filesystem intentionally excluded
    governance: schema + domains + boundaries + permissions + coverage + locks
    """

    private static func permissionScope(_ app: AppState) -> String {
        let agent = app.currentAgent
        let names = agent.tools ?? AppState.writingTools.compactMap { ($0["function"] as? JSON)?["name"] as? String }
        return "Agent: \(agent.name) [\(agent.id.uuidString)]\n工具权限: \(agent.tools == nil ? "全部已启用工具" : "白名单")\n可见工具数: \(names.count)\n\(names.sorted().joined(separator: ", "))\n禁止项: API Key、任意文件系统、终端、任意网络"
    }

    private static func listLocks(_ app: AppState) -> String {
        if app.workspaceResourceOwners.isEmpty { return "当前没有跨会话写资源锁" }
        return app.workspaceResourceOwners.sorted { $0.key < $1.key }.map { "\($0.key) · owner_conversation_id: \($0.value.uuidString)" }.joined(separator: "\n")
    }

    private static func listImports() -> String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: importsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return urls.isEmpty ? "Imports 授权目录为空：\(importsDirectory.path)" : urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return "\(url.lastPathComponent) · \(size) bytes · \(url.path)"
        }.joined(separator: "\n")
    }

    private static func deleteImport(_ args: JSON) -> String {
        guard let name = args["filename"] as? String, args["expected_filename"] as? String == name,
              name == URL(fileURLWithPath: name).lastPathComponent,
              let url = authorizedImportURL(importsDirectory.appendingPathComponent(name).path) else { return "错误：文件名校验失败" }
        do { try FileManager.default.removeItem(at: url); return "已删除授权导入文件 \(name)" }
        catch { return "错误：\(error.localizedDescription)" }
    }

    private static func bookID(_ args: JSON, _ app: AppState) -> UUID? {
        if let raw = args["book_id"] as? String, let id = UUID(uuidString: raw), app.novels.contains(where: { $0.id == id }) { return id }
        return app.currentNovelID
    }
    private static func node(_ raw: Any?, _ app: AppState) -> StoryNode? {
        guard let raw = raw as? String, let id = UUID(uuidString: raw) else { return nil }
        for novel in app.novels { if let value = DB.shared.storyNodes(novelID: novel.id).first(where: { $0.id == id }) { return value } }
        return nil
    }
    private static func nodeLine(_ n: StoryNode) -> String { "\(n.kind) · \(n.title) · node_id: \(n.id.uuidString) · status: \(n.status) · parent: \(n.parentID?.uuidString ?? "none") · order: \(n.sortOrder)" }
    private static func listNodes(_ args: JSON, _ app: AppState) -> String {
        guard let id = bookID(args, app) else { return "错误：找不到书籍" }
        let values = DB.shared.storyNodes(novelID: id, kind: args["kind"] as? String).filter { n in
            guard let raw = args["parent_id"] as? String else { return true }; return n.parentID?.uuidString == raw
        }
        return values.isEmpty ? "没有匹配的创作结构对象" : values.map(nodeLine).joined(separator: "\n")
    }
    private static func getNode(_ args: JSON, _ app: AppState) -> String {
        guard let n = node(args["node_id"], app) else { return "错误：找不到对象" }
        return "\(nodeLine(n))\nmetadata: \(n.metadataJSON)\n\(n.content)"
    }
    private static func metadataJSON(_ value: Any?) -> String {
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    private static func createNode(_ args: JSON, _ app: AppState) -> String {
        guard let id = bookID(args, app), let kind = args["kind"] as? String, storyKinds.contains(kind),
              let title = args["title"] as? String, !title.isEmpty else { return "错误：书籍、类型或标题无效" }
        let parent = (args["parent_id"] as? String).flatMap(UUID.init(uuidString:))
        let n = DB.shared.createStoryNode(novelID: id, kind: kind, title: title, content: args["content"] as? String ?? "",
                                          status: args["status"] as? String ?? "draft", parentID: parent,
                                          sortOrder: args["sort_order"] as? Int ?? 0, metadataJSON: metadataJSON(args["metadata"]))
        refreshNodes(id, app)
        return "已创建 \(kind)《\(title)》\nnode_id: \(n.id.uuidString)"
    }
    private static func batchCreateNodes(_ args: JSON, _ app: AppState) -> String {
        guard let id = bookID(args, app), let rows = args["nodes"] as? [JSON], !rows.isEmpty else { return "错误：缺少 nodes" }
        var created: [StoryNode] = []
        for row in rows.prefix(200) {
            guard let kind = row["kind"] as? String, storyKinds.contains(kind), let title = row["title"] as? String, !title.isEmpty else { continue }
            created.append(DB.shared.createStoryNode(novelID: id, kind: kind, title: title, content: row["content"] as? String ?? "",
                                                     status: row["status"] as? String ?? "draft",
                                                     parentID: (row["parent_id"] as? String).flatMap(UUID.init(uuidString:)),
                                                     sortOrder: row["sort_order"] as? Int ?? 0, metadataJSON: metadataJSON(row["metadata"])))
        }
        refreshNodes(id, app)
        return "已批量创建 \(created.count) 个创作结构对象\n" + created.map(nodeLine).joined(separator: "\n")
    }
    private static func updateNode(_ args: JSON, _ app: AppState) -> String {
        guard let n = node(args["node_id"], app) else { return "错误：找不到对象" }
        let kind = args["kind"] as? String
        if let kind, !storyKinds.contains(kind) { return "错误：kind 无效" }
        DB.shared.updateStoryNode(id: n.id, kind: kind, title: args["title"] as? String, content: args["content"] as? String,
                                  status: args["status"] as? String,
                                  parentID: (args["parent_id"] as? String).flatMap(UUID.init(uuidString:)),
                                  setParent: args["parent_id"] != nil || args["clear_parent"] as? Bool == true,
                                  sortOrder: args["sort_order"] as? Int,
                                  metadataJSON: args["metadata"] == nil ? nil : metadataJSON(args["metadata"]))
        refreshNodes(n.novelID, app)
        return "已更新 \(n.kind)《\(args["title"] as? String ?? n.title)》"
    }
    private static func deleteNode(_ args: JSON, _ app: AppState) -> String {
        guard let n = node(args["node_id"], app), args["expected_title"] as? String == n.title else { return "错误：对象或标题校验失败" }
        DB.shared.deleteStoryNode(id: n.id)
        refreshNodes(n.novelID, app)
        return "已删除 \(n.kind)《\(n.title)》"
    }

    private static func refreshNodes(_ novelID: UUID, _ app: AppState) {
        if app.currentNovelID == novelID { app.storyNodes = DB.shared.storyNodes(novelID: novelID) }
    }

    private static func revision(_ raw: Any?, _ app: AppState) -> ContentRevision? {
        guard let raw = raw as? String, let id = UUID(uuidString: raw) else { return nil }
        for novel in app.novels { if let r = DB.shared.revisions(novelID: novel.id, limit: 500).first(where: { $0.id == id }) { return r } }
        return nil
    }
    private static func listRevisions(_ args: JSON, _ app: AppState) -> String {
        guard let id = bookID(args, app) else { return "错误：找不到书籍" }
        let values = DB.shared.revisions(novelID: id, resourceType: args["resource_type"] as? String,
                                         resourceID: args["resource_id"] as? String, limit: args["limit"] as? Int ?? 100)
        return values.isEmpty ? "没有内容版本" : values.map { "\($0.resourceType):\($0.resourceID) · \($0.operation) · revision_id: \($0.id.uuidString) · \($0.createdAt)" }.joined(separator: "\n")
    }
    private static func getRevision(_ args: JSON, _ app: AppState) -> String {
        guard let r = revision(args["revision_id"], app) else { return "错误：找不到版本" }
        return "revision_id: \(r.id.uuidString)\nresource: \(r.resourceType):\(r.resourceID)\noperation: \(r.operation)\nconversation_id: \(r.conversationID?.uuidString ?? "none")\n\(r.snapshotJSON)"
    }
    private static func compareRevisions(_ args: JSON, _ app: AppState) -> String {
        guard let l = revision(args["left_revision_id"], app), let r = revision(args["right_revision_id"], app) else { return "错误：找不到版本" }
        let a = Array(l.snapshotJSON), b = Array(r.snapshotJSON); let count = min(a.count, b.count)
        let first = (0..<count).first { a[$0] != b[$0] } ?? (a.count == b.count ? -1 : count)
        return "左版本 \(a.count) 字符，右版本 \(b.count) 字符；首个差异位置：\(first < 0 ? "无差异" : String(first))\n左片段：\(String(a.dropFirst(max(0, first)).prefix(300)))\n右片段：\(String(b.dropFirst(max(0, first)).prefix(300)))"
    }
    private static func restoreRevision(_ args: JSON, _ app: AppState) -> String {
        guard let r = revision(args["revision_id"], app), args["expected_resource_id"] as? String == r.resourceID,
              let data = r.snapshotJSON.data(using: .utf8), let snap = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return "错误：版本或资源 ID 校验失败" }
        switch r.resourceType {
        case "chapter":
            guard let id = UUID(uuidString: r.resourceID), let title = snap["title"] as? String, let content = snap["content"] as? String else { return "错误：章节快照无效" }
            DB.shared.addRevision(novelID: r.novelID, resourceType: "chapter", resourceID: r.resourceID, conversationID: app.currentConversationID, operation: "before_restore", snapshotJSON: currentChapterSnapshot(id, novelID: r.novelID) ?? "{}")
            DB.shared.restoreChapter(id: id, novelID: r.novelID, number: snap["number"] as? Int ?? 1, title: title, content: content)
            if app.currentNovelID == r.novelID { app.chapters = DB.shared.chapters(novelID: r.novelID) }
        case "lore":
            guard let id = UUID(uuidString: r.resourceID) else { return "错误：设定快照无效" }
            DB.shared.restoreEntry(id: id, novelID: r.novelID, type: snap["type"] as? String ?? "note", title: snap["title"] as? String ?? "",
                                   content: snap["content"] as? String ?? "", keywords: snap["keywords"] as? String ?? "", pinned: snap["pinned"] as? Bool ?? false)
            if app.currentNovelID == r.novelID { app.entries = DB.shared.entries(novelID: r.novelID) }
        case "story_node":
            guard let id = UUID(uuidString: r.resourceID) else { return "错误：结构快照无效" }
            DB.shared.restoreStoryNode(id: id, novelID: r.novelID, snapshot: snap)
            refreshNodes(r.novelID, app)
        case "book":
            guard let id = UUID(uuidString: r.resourceID), app.novels.contains(where: { $0.id == id }) else { return "错误：书籍不存在，暂不支持整书重建" }
            var metadata = BookMetadata()
            if let raw = snap["metadata"] as? String, let d = raw.data(using: .utf8), let decoded = try? JSONDecoder().decode(BookMetadata.self, from: d) { metadata = decoded }
            DB.shared.updateNovel(id: id, title: snap["title"] as? String, desc: snap["description"] as? String,
                                  outline: snap["outline"] as? String, metadata: metadata)
            app.novels = DB.shared.novels()
        default: return "错误：暂不支持恢复 \(r.resourceType)"
        }
        return "已恢复版本 \(r.id.uuidString) 到 \(r.resourceType):\(r.resourceID)"
    }

    private static func currentChapterSnapshot(_ id: UUID, novelID: UUID) -> String? {
        guard let c = DB.shared.chapters(novelID: novelID).first(where: { $0.id == id }) else { return nil }
        return json(["id": c.id.uuidString, "number": c.no, "title": c.title, "content": c.content])
    }
    static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
