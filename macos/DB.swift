import Foundation
import SQLite3

/// 原生 SQLite 封装：作品 / 章节 / 设定库（世界书）/ 对话记录，FTS5 中文全文搜索。
/// 数据文件：~/Library/Application Support/ZhinaiNovelEditor/novels.db
final class DB {
    static let shared = DB()

    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        var handle: OpaquePointer?
        if sqlite3_open(AppPaths.dbURL.path, &handle) == SQLITE_OK {
            db = handle
        }
        migrate()
    }

    deinit { sqlite3_close(db) }

    // MARK: - 建表与迁移

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS novels(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          outline TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chapters(
          id TEXT PRIMARY KEY, novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
          no INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries(
          id TEXT PRIMARY KEY, novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
          type TEXT NOT NULL DEFAULT 'note', title TEXT NOT NULL, content TEXT NOT NULL DEFAULT '',
          keywords TEXT NOT NULL DEFAULT '', pinned INTEGER NOT NULL DEFAULT 0,
          created_at REAL NOT NULL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS conversations(
          id TEXT PRIMARY KEY, novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
          title TEXT NOT NULL DEFAULT '新对话', created_at REAL NOT NULL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages(
          id TEXT PRIMARY KEY, novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
          conversation_id TEXT NOT NULL DEFAULT '',
          role TEXT NOT NULL, content TEXT NOT NULL DEFAULT '', skill TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL
        );
        """)
        // 兼容旧库：补 pinned / conversation_id 列
        if !columnExists(table: "entries", column: "pinned") {
            exec("ALTER TABLE entries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
        }
        if !columnExists(table: "messages", column: "conversation_id") {
            exec("ALTER TABLE messages ADD COLUMN conversation_id TEXT NOT NULL DEFAULT ''")
        }
        // 旧消息迁移：为每个有消息的作品建「对话 1」并归入
        let orphans = query("SELECT DISTINCT novel_id FROM messages WHERE conversation_id=''", []) { text($0, 0) }
            .compactMap { $0.flatMap(UUID.init(uuidString:)) }
        for nid in orphans {
            let c = Conversation(id: UUID(), novelID: nid, title: "对话 1", createdAt: Date(), updatedAt: Date())
            run("INSERT INTO conversations(id,novel_id,title,created_at,updated_at) VALUES(?,?,?,?,?)",
                c.id, c.novelID, c.title, c.createdAt, c.updatedAt)
            run("UPDATE messages SET conversation_id=? WHERE novel_id=? AND conversation_id=''", c.id, nid)
        }
        exec("CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(title, content, keywords, tokenize='trigram')")
        exec("CREATE VIRTUAL TABLE IF NOT EXISTS chapters_fts USING fts5(title, content, tokenize='trigram')")
    }

    private func columnExists(table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 1), name == column { return true }
        }
        return false
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - 通用访问器

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
    private func int(_ stmt: OpaquePointer?, _ idx: Int32) -> Int { Int(sqlite3_column_int64(stmt, idx)) }
    private func real(_ stmt: OpaquePointer?, _ idx: Int32) -> Double { sqlite3_column_double(stmt, idx) }
    private func uuid(_ stmt: OpaquePointer?, _ idx: Int32) -> UUID? {
        guard let s = text(stmt, idx), let u = UUID(uuidString: s) else { return nil }
        return u
    }
    private func date(_ stmt: OpaquePointer?, _ idx: Int32) -> Date { Date(timeIntervalSince1970: real(stmt, idx)) }

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Any?) {
        guard let v else { sqlite3_bind_null(stmt, idx); return }
        switch v {
        case let s as String: sqlite3_bind_text(stmt, idx, s, -1, DB.SQLITE_TRANSIENT)
        case let i as Int: sqlite3_bind_int64(stmt, idx, Int64(i))
        case let b as Bool: sqlite3_bind_int64(stmt, idx, b ? 1 : 0)
        case let d as Date: sqlite3_bind_double(stmt, idx, d.timeIntervalSince1970)
        case let u as UUID: sqlite3_bind_text(stmt, idx, u.uuidString, -1, DB.SQLITE_TRANSIENT)
        default: sqlite3_bind_null(stmt, idx)
        }
    }

    /// 执行带参数语句，返回 changes
    @discardableResult
    private func run(_ sql: String, _ args: Any?...) -> Int {
        runArray(sql, args)
    }

    @discardableResult
    private func runArray(_ sql: String, _ args: [Any?]) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        for (i, a) in args.enumerated() { bind(stmt, Int32(i + 1), a) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return Int(sqlite3_changes(db))
    }

    private func query<T>(_ sql: String, _ args: [Any?], _ map: (OpaquePointer?) -> T) -> [T] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (i, a) in args.enumerated() { bind(stmt, Int32(i + 1), a) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
        return out
    }

    // MARK: - 作品

    func novels() -> [Novel] {
        query("SELECT * FROM novels ORDER BY updated_at DESC", []) { s in
            Novel(id: uuid(s, 0)!, title: text(s, 1) ?? "", desc: text(s, 2) ?? "",
                  outline: text(s, 3) ?? "", createdAt: date(s, 4), updatedAt: date(s, 5))
        }
    }

    @discardableResult
    func createNovel(title: String, desc: String = "") -> Novel {
        let n = Novel(id: UUID(), title: title.isEmpty ? "未命名作品" : title, desc: desc,
                      outline: "", createdAt: Date(), updatedAt: Date())
        run("INSERT INTO novels(id,title,description,outline,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            n.id, n.title, n.desc, n.outline, n.createdAt, n.updatedAt)
        return n
    }

    func updateNovel(id: UUID, title: String? = nil, desc: String? = nil, outline: String? = nil) {
        var sql = "UPDATE novels SET updated_at=?"
        var args: [Any?] = [Date()]
        if let title { sql += ", title=?"; args.append(title) }
        if let desc { sql += ", description=?"; args.append(desc) }
        if let outline { sql += ", outline=?"; args.append(outline) }
        sql += " WHERE id=?"
        args.append(id)
        runArray(sql, args)
    }

    func deleteNovel(id: UUID) { run("DELETE FROM novels WHERE id=?", id) }

    // MARK: - 章节

    func chapters(novelID: UUID) -> [Chapter] {
        query("SELECT * FROM chapters WHERE novel_id=? ORDER BY no ASC, created_at ASC", [novelID]) { s in
            Chapter(id: uuid(s, 0)!, novelID: uuid(s, 1)!, no: int(s, 2), title: text(s, 3) ?? "",
                    content: text(s, 4) ?? "", createdAt: date(s, 5), updatedAt: date(s, 6))
        }
    }

    func lastChapters(novelID: UUID, count: Int) -> [Chapter] {
        let all = chapters(novelID: novelID)
        guard count > 0 else { return [] }
        return Array(all.suffix(count))
    }

    @discardableResult
    func createChapter(novelID: UUID, title: String = "", content: String = "") -> Chapter {
        let maxNo = query("SELECT COALESCE(MAX(no),0) AS m FROM chapters WHERE novel_id=?", [novelID]) { int($0, 0) }.first ?? 0
        let c = Chapter(id: UUID(), novelID: novelID, no: maxNo + 1, title: title, content: content,
                        createdAt: Date(), updatedAt: Date())
        run("INSERT INTO chapters(id,novel_id,no,title,content,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
            c.id, c.novelID, c.no, c.title, c.content, c.createdAt, c.updatedAt)
        syncChapterFTS(c.id)
        return c
    }

    func updateChapter(id: UUID, title: String? = nil, content: String? = nil, no: Int? = nil) {
        var sql = "UPDATE chapters SET updated_at=?"
        var args: [Any?] = [Date()]
        if let title { sql += ", title=?"; args.append(title) }
        if let content { sql += ", content=?"; args.append(content) }
        if let no { sql += ", no=?"; args.append(no) }
        sql += " WHERE id=?"
        args.append(id)
        runArray(sql, args)
        syncChapterFTS(id)
    }

    func deleteChapter(id: UUID) {
        run("DELETE FROM chapters_fts WHERE rowid IN (SELECT rowid FROM chapters WHERE id=?)", id)
        run("DELETE FROM chapters WHERE id=?", id)
    }

    // MARK: - 设定库（世界书）

    func entries(novelID: UUID) -> [Entry] {
        query("SELECT * FROM entries WHERE novel_id=? ORDER BY pinned DESC, updated_at DESC", [novelID]) { s in
            Entry(id: uuid(s, 0)!, novelID: uuid(s, 1)!, type: text(s, 2) ?? "note",
                  title: text(s, 3) ?? "", content: text(s, 4) ?? "", keywords: text(s, 5) ?? "",
                  pinned: int(s, 6) != 0, createdAt: date(s, 7), updatedAt: date(s, 8))
        }
    }

    @discardableResult
    func createEntry(novelID: UUID, type: String = "note", title: String, content: String = "", keywords: String = "", pinned: Bool = false) -> Entry {
        let e = Entry(id: UUID(), novelID: novelID, type: type, title: title, content: content,
                      keywords: keywords, pinned: pinned, createdAt: Date(), updatedAt: Date())
        run("INSERT INTO entries(id,novel_id,type,title,content,keywords,pinned,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
            e.id, e.novelID, e.type, e.title, e.content, e.keywords, e.pinned, e.createdAt, e.updatedAt)
        syncEntryFTS(e.id)
        return e
    }

    func updateEntry(id: UUID, type: String? = nil, title: String? = nil, content: String? = nil,
                     keywords: String? = nil, pinned: Bool? = nil) {
        var sql = "UPDATE entries SET updated_at=?"
        var args: [Any?] = [Date()]
        if let type { sql += ", type=?"; args.append(type) }
        if let title { sql += ", title=?"; args.append(title) }
        if let content { sql += ", content=?"; args.append(content) }
        if let keywords { sql += ", keywords=?"; args.append(keywords) }
        if let pinned { sql += ", pinned=?"; args.append(pinned) }
        sql += " WHERE id=?"
        args.append(id)
        runArray(sql, args)
        syncEntryFTS(id)
    }

    func deleteEntry(id: UUID) {
        run("DELETE FROM entries_fts WHERE rowid IN (SELECT rowid FROM entries WHERE id=?)", id)
        run("DELETE FROM entries WHERE id=?", id)
    }

    // MARK: - 会话

    func conversations(novelID: UUID) -> [Conversation] {
        query("SELECT * FROM conversations WHERE novel_id=? ORDER BY updated_at DESC", [novelID]) { s in
            Conversation(id: uuid(s, 0)!, novelID: uuid(s, 1)!, title: text(s, 2) ?? "新对话",
                         createdAt: date(s, 3), updatedAt: date(s, 4))
        }
    }

    @discardableResult
    func createConversation(novelID: UUID, title: String = "新对话") -> Conversation {
        let c = Conversation(id: UUID(), novelID: novelID, title: title, createdAt: Date(), updatedAt: Date())
        run("INSERT INTO conversations(id,novel_id,title,created_at,updated_at) VALUES(?,?,?,?,?)",
            c.id, c.novelID, c.title, c.createdAt, c.updatedAt)
        return c
    }

    func renameConversation(id: UUID, title: String) {
        run("UPDATE conversations SET title=?, updated_at=? WHERE id=?", title, Date(), id)
    }

    func touchConversation(id: UUID) {
        run("UPDATE conversations SET updated_at=? WHERE id=?", Date(), id)
    }

    func deleteConversation(id: UUID) {
        run("DELETE FROM messages WHERE conversation_id=?", id)
        run("DELETE FROM conversations WHERE id=?", id)
    }

    // MARK: - 对话记录

    func messages(novelID: UUID, conversationID: UUID, limit: Int = 200) -> [Msg] {
        query("""
            SELECT id, novel_id, conversation_id, role, content, skill, created_at
            FROM messages WHERE novel_id=? AND conversation_id=? ORDER BY created_at ASC LIMIT ?
            """, [novelID, conversationID, limit]) { s in
            Msg(id: uuid(s, 0)!, novelID: uuid(s, 1)!, conversationID: uuid(s, 2)!,
                role: text(s, 3) ?? "user", content: text(s, 4) ?? "",
                skill: text(s, 5) ?? "", createdAt: date(s, 6))
        }
    }

    @discardableResult
    func addMessage(novelID: UUID, conversationID: UUID, role: String, content: String, skill: String = "") -> Msg {
        let m = Msg(id: UUID(), novelID: novelID, conversationID: conversationID,
                    role: role, content: content, skill: skill, createdAt: Date())
        run("INSERT INTO messages(id,novel_id,conversation_id,role,content,skill,created_at) VALUES(?,?,?,?,?,?,?)",
            m.id, m.novelID, m.conversationID, m.role, m.content, m.skill, m.createdAt)
        touchConversation(id: conversationID)
        return m
    }

    func clearMessages(conversationID: UUID) { run("DELETE FROM messages WHERE conversation_id=?", conversationID) }

    // MARK: - 全文搜索

    func search(_ q: String, novelID: UUID) -> (entries: [Entry], chapters: [Chapter]) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return ([], []) }
        let entries: [Entry]
        let chapters: [Chapter]

        if q.count >= 3 {
            let safe = q.replacingOccurrences(of: "\"", with: " ").replacingOccurrences(of: "\\", with: " ")
            entries = query("""
                SELECT e.id,e.novel_id,e.type,e.title,e.content,e.keywords,e.pinned,e.created_at,e.updated_at
                FROM entries e JOIN entries_fts f ON f.rowid = e.rowid
                WHERE entries_fts MATCH ? AND e.novel_id = ? ORDER BY bm25(entries_fts) LIMIT 30
                """, [safe, novelID]) { self.entryFromRow($0) }
            chapters = query("""
                SELECT c.id,c.novel_id,c.no,c.title,c.content,c.created_at,c.updated_at
                FROM chapters c JOIN chapters_fts f ON f.rowid = c.rowid
                WHERE chapters_fts MATCH ? AND c.novel_id = ? ORDER BY bm25(chapters_fts) LIMIT 30
                """, [safe, novelID]) { self.chapterFromRow($0) }
        } else {
            let like = "%" + q.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            entries = query("""
                SELECT * FROM entries WHERE novel_id=?
                AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' OR keywords LIKE ? ESCAPE '\\')
                ORDER BY updated_at DESC LIMIT 30
                """, [novelID, like, like, like]) { self.entryFromRow($0) }
            chapters = query("""
                SELECT * FROM chapters WHERE novel_id=?
                AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')
                ORDER BY updated_at DESC LIMIT 30
                """, [novelID, like, like]) { self.chapterFromRow($0) }
        }
        return (entries, chapters)
    }

    private func entryFromRow(_ s: OpaquePointer?) -> Entry {
        Entry(id: uuid(s, 0)!, novelID: uuid(s, 1)!, type: text(s, 2) ?? "note",
              title: text(s, 3) ?? "", content: text(s, 4) ?? "", keywords: text(s, 5) ?? "",
              pinned: int(s, 6) != 0, createdAt: date(s, 7), updatedAt: date(s, 8))
    }
    private func chapterFromRow(_ s: OpaquePointer?) -> Chapter {
        Chapter(id: uuid(s, 0)!, novelID: uuid(s, 1)!, no: int(s, 2), title: text(s, 3) ?? "",
                content: text(s, 4) ?? "", createdAt: date(s, 5), updatedAt: date(s, 6))
    }

    // MARK: - FTS 同步

    private func syncEntryFTS(_ id: UUID) {
        run("DELETE FROM entries_fts WHERE rowid IN (SELECT rowid FROM entries WHERE id=?)", id)
        run("INSERT INTO entries_fts(rowid,title,content,keywords) SELECT rowid,title,content,keywords FROM entries WHERE id=?", id)
    }
    private func syncChapterFTS(_ id: UUID) {
        run("DELETE FROM chapters_fts WHERE rowid IN (SELECT rowid FROM chapters WHERE id=?)", id)
        run("INSERT INTO chapters_fts(rowid,title,content) SELECT rowid,title,content FROM chapters WHERE id=?", id)
    }
}
