import Foundation
import SQLite3

struct VectorLibrary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let sourcePath: String
    let chapterCount: Int
    let chunkCount: Int
    let createdAt: Date
}

struct VectorChapter: Identifiable, Hashable {
    let id: UUID
    let libraryID: UUID
    let no: Int
    var title: String
    var content: String
    var updatedAt: Date
}

struct VectorSearchResult: Identifiable, Hashable {
    let id: UUID
    let libraryID: UUID
    let chapterNo: Int
    let chapterTitle: String
    let chunkNo: Int
    let content: String
    let score: Double
}

struct ParsedNovelText {
    struct Chapter: Hashable {
        let no: Int
        let title: String
        let content: String
    }

    let title: String
    let author: String
    let summary: String
    let chapters: [Chapter]
}

enum NovelTextParser {
    static func parse(url: URL) throws -> ParsedNovelText {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw VectorStoreError.unsupportedEncoding
        }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let pattern = "(?m)^第\\s*([0-9]+)\\s*章\\s*[：:]?\\s*(.+?)\\s*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { throw VectorStoreError.noChapters }

        var chapters: [ParsedNovelText.Chapter] = []
        for (index, match) in matches.enumerated() {
            guard let noRange = Range(match.range(at: 1), in: text),
                  let titleRange = Range(match.range(at: 2), in: text),
                  let contentStart = Range(match.range, in: text)?.upperBound else {
                throw VectorStoreError.invalidChapterFormat
            }
            let number = Int(text[noRange]) ?? 0
            let title = text[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let contentEnd: String.Index
            if index + 1 < matches.count, let next = Range(matches[index + 1].range, in: text) {
                contentEnd = next.lowerBound
            } else {
                contentEnd = text.endIndex
            }
            let content = text[contentStart..<contentEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            guard number == index + 1, !title.isEmpty, !content.isEmpty else {
                throw VectorStoreError.invalidChapterFormat
            }
            chapters.append(.init(no: number, title: title, content: content))
        }

        let prefaceEnd = Range(matches[0].range, in: text)?.lowerBound ?? text.startIndex
        let preface = String(text[..<prefaceEnd])
        let title = field("书名", in: preface) ?? url.deletingPathExtension().lastPathComponent
        let author = field("作者", in: preface) ?? ""
        let summary = summaryFromPreface(preface)
        return ParsedNovelText(title: title, author: author, summary: summary, chapters: chapters)
    }

    private static func field(_ name: String, in text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(name)：") || $0.hasPrefix("\(name):") }
            .map { line in
                String(line.drop(while: { $0 != "：" && $0 != ":" }).dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private static func summaryFromPreface(_ text: String) -> String {
        guard let marker = text.range(of: "【简介】") else { return "" }
        let following = text[marker.upperBound...]
        let divider = following.range(of: "————————————————")?.lowerBound ?? following.endIndex
        return String(following[..<divider]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VectorStoreError: LocalizedError {
    case unsupportedEncoding
    case noChapters
    case invalidChapterFormat
    case unexpectedChapterCount(expected: Int, actual: Int)
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: return "仅支持 UTF-8 TXT 文件"
        case .noChapters: return "未识别到“第N章：标题”格式的章节"
        case .invalidChapterFormat: return "章节编号不连续，或存在空标题/空正文"
        case let .unexpectedChapterCount(expected, actual): return "章节数校验失败：应为 \(expected) 章，实际解析到 \(actual) 章"
        case .databaseUnavailable: return "无法打开本地向量数据库"
        }
    }
}

/// 独立 SQLite 向量库：将章节分块后保存为本地 256 维字符 n-gram 向量。
/// 该方案无需上传正文；后续可平滑替换为远程 embedding，同时保留表结构与检索接口。
final class VectorStore {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let dimensions = 256
    private var db: OpaquePointer?

    init() {
        var handle: OpaquePointer?
        if sqlite3_open(AppPaths.vectorDBURL.path, &handle) == SQLITE_OK {
            db = handle
            migrate()
        }
    }

    deinit { sqlite3_close(db) }

    func libraries() -> [VectorLibrary] {
        query("SELECT id,title,source_path,chapter_count,chunk_count,created_at FROM vector_libraries ORDER BY created_at DESC") { stmt in
            VectorLibrary(
                id: UUID(uuidString: text(stmt, 0) ?? "")!,
                title: text(stmt, 1) ?? "未命名小说",
                sourcePath: text(stmt, 2) ?? "",
                chapterCount: int(stmt, 3),
                chunkCount: int(stmt, 4),
                createdAt: Date(timeIntervalSince1970: real(stmt, 5))
            )
        }
    }

    func chapters(libraryID: UUID) -> [VectorChapter] {
        query("SELECT id,library_id,no,title,content,updated_at FROM vector_chapters WHERE library_id=? ORDER BY no ASC",
              [libraryID.uuidString]) { stmt in
            VectorChapter(id: UUID(uuidString: text(stmt, 0) ?? "")!,
                          libraryID: UUID(uuidString: text(stmt, 1) ?? "")!,
                          no: int(stmt, 2), title: text(stmt, 3) ?? "",
                          content: text(stmt, 4) ?? "",
                          updatedAt: Date(timeIntervalSince1970: real(stmt, 5)))
        }
    }

    @discardableResult
    func importTXT(url: URL, expectedChapterCount: Int? = nil) throws -> VectorLibrary {
        guard db != nil else { throw VectorStoreError.databaseUnavailable }
        let parsed = try NovelTextParser.parse(url: url)
        if let expectedChapterCount, parsed.chapters.count != expectedChapterCount {
            throw VectorStoreError.unexpectedChapterCount(expected: expectedChapterCount, actual: parsed.chapters.count)
        }
        if let existing = libraries().first(where: { $0.sourcePath == url.path }) {
            delete(existing)
        }

        let library = VectorLibrary(id: UUID(), title: parsed.title, sourcePath: url.path,
                                    chapterCount: parsed.chapters.count, chunkCount: 0, createdAt: Date())
        let chunks = parsed.chapters.flatMap { chapter in
            split(chapter.content).enumerated().map { index, content in
                (chapter.no, chapter.title, index + 1, content)
            }
        }

        exec("BEGIN IMMEDIATE TRANSACTION")
        defer { exec("COMMIT") }
        run("INSERT INTO vector_libraries(id,title,source_path,author,summary,chapter_count,chunk_count,created_at) VALUES(?,?,?,?,?,?,?,?)",
            library.id.uuidString, library.title, library.sourcePath, parsed.author, parsed.summary,
            library.chapterCount, chunks.count, library.createdAt.timeIntervalSince1970)

        for chapter in parsed.chapters {
            run("INSERT INTO vector_chapters(id,library_id,no,title,content,updated_at) VALUES(?,?,?,?,?,?)",
                UUID().uuidString, library.id.uuidString, chapter.no, chapter.title, chapter.content,
                library.createdAt.timeIntervalSince1970)
        }

        for (chapterNo, chapterTitle, chunkNo, content) in chunks {
            let id = UUID()
            let vector = embedding(content)
            run("INSERT INTO vector_chunks(id,library_id,chapter_no,chapter_title,chunk_no,content,embedding,created_at) VALUES(?,?,?,?,?,?,?,?)",
                id.uuidString, library.id.uuidString, chapterNo, chapterTitle, chunkNo, content, vector,
                library.createdAt.timeIntervalSince1970)
            run("INSERT INTO vector_chunks_fts(rowid,content,chapter_title) SELECT rowid,content,chapter_title FROM vector_chunks WHERE id=?", id.uuidString)
        }
        return VectorLibrary(id: library.id, title: library.title, sourcePath: library.sourcePath,
                             chapterCount: library.chapterCount, chunkCount: chunks.count, createdAt: library.createdAt)
    }

    func delete(_ library: VectorLibrary) {
        run("DELETE FROM vector_chunks_fts WHERE rowid IN (SELECT rowid FROM vector_chunks WHERE library_id=?)", library.id.uuidString)
        run("DELETE FROM vector_chunks WHERE library_id=?", library.id.uuidString)
        run("DELETE FROM vector_chapters WHERE library_id=?", library.id.uuidString)
        run("DELETE FROM vector_libraries WHERE id=?", library.id.uuidString)
    }

    @discardableResult
    func updateChapter(_ chapter: VectorChapter, title: String, content: String) -> VectorChapter? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanContent.isEmpty else { return nil }
        let now = Date()
        let pieces = split(cleanContent)

        exec("BEGIN IMMEDIATE TRANSACTION")
        run("UPDATE vector_chapters SET title=?,content=?,updated_at=? WHERE id=?",
            cleanTitle, cleanContent, now.timeIntervalSince1970, chapter.id.uuidString)
        run("DELETE FROM vector_chunks_fts WHERE rowid IN (SELECT rowid FROM vector_chunks WHERE library_id=? AND chapter_no=?)",
            chapter.libraryID.uuidString, chapter.no)
        run("DELETE FROM vector_chunks WHERE library_id=? AND chapter_no=?", chapter.libraryID.uuidString, chapter.no)
        for (index, piece) in pieces.enumerated() {
            let id = UUID()
            run("INSERT INTO vector_chunks(id,library_id,chapter_no,chapter_title,chunk_no,content,embedding,created_at) VALUES(?,?,?,?,?,?,?,?)",
                id.uuidString, chapter.libraryID.uuidString, chapter.no, cleanTitle, index + 1, piece,
                embedding(piece), now.timeIntervalSince1970)
            run("INSERT INTO vector_chunks_fts(rowid,content,chapter_title) SELECT rowid,content,chapter_title FROM vector_chunks WHERE id=?",
                id.uuidString)
        }
        run("UPDATE vector_libraries SET chunk_count=(SELECT COUNT(*) FROM vector_chunks WHERE library_id=?) WHERE id=?",
            chapter.libraryID.uuidString, chapter.libraryID.uuidString)
        exec("COMMIT")
        return VectorChapter(id: chapter.id, libraryID: chapter.libraryID, no: chapter.no,
                             title: cleanTitle, content: cleanContent, updatedAt: now)
    }

    func search(libraryID: UUID, queryText: String, limit: Int = 12) -> [VectorSearchResult] {
        let queryText = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { return [] }
        let target = embedding(queryText)
        let rows: [(UUID, Int, String, Int, String, Data)] = query(
            "SELECT id,chapter_no,chapter_title,chunk_no,content,embedding FROM vector_chunks WHERE library_id=?",
            [libraryID.uuidString]
        ) { stmt in
            (UUID(uuidString: text(stmt, 0) ?? "")!, int(stmt, 1), text(stmt, 2) ?? "",
             int(stmt, 3), text(stmt, 4) ?? "", data(stmt, 5) ?? Data())
        }
        return rows.compactMap { row in
            guard let source = vector(from: row.5) else { return nil }
            return VectorSearchResult(id: row.0, libraryID: libraryID, chapterNo: row.1,
                                      chapterTitle: row.2, chunkNo: row.3, content: row.4,
                                      score: cosine(target, source))
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .filter { $0.score > 0 }
        .map { $0 }
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS vector_libraries(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, source_path TEXT NOT NULL, author TEXT NOT NULL DEFAULT '',
          summary TEXT NOT NULL DEFAULT '', chapter_count INTEGER NOT NULL, chunk_count INTEGER NOT NULL,
          created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS vector_chunks(
          id TEXT PRIMARY KEY, library_id TEXT NOT NULL REFERENCES vector_libraries(id) ON DELETE CASCADE,
          chapter_no INTEGER NOT NULL, chapter_title TEXT NOT NULL, chunk_no INTEGER NOT NULL,
          content TEXT NOT NULL, embedding BLOB NOT NULL, created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS vector_chapters(
          id TEXT PRIMARY KEY, library_id TEXT NOT NULL REFERENCES vector_libraries(id) ON DELETE CASCADE,
          no INTEGER NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL, updated_at REAL NOT NULL,
          UNIQUE(library_id, no)
        );
        CREATE INDEX IF NOT EXISTS vector_chapters_library_index ON vector_chapters(library_id, no);
        CREATE INDEX IF NOT EXISTS vector_chunks_library_index ON vector_chunks(library_id, chapter_no, chunk_no);
        CREATE VIRTUAL TABLE IF NOT EXISTS vector_chunks_fts USING fts5(content, chapter_title, tokenize='trigram');
        """)
    }

    private func split(_ text: String, size: Int = 720, overlap: Int = 120) -> [String] {
        let characters = Array(text)
        guard characters.count > size else { return [text] }
        var result: [String] = []
        var start = 0
        while start < characters.count {
            let end = min(start + size, characters.count)
            var cut = end
            if end < characters.count {
                let lower = max(start + size / 2, end - 100)
                if let punctuation = (lower..<end).reversed().first(where: { "。！？\n".contains(characters[$0]) }) {
                    cut = punctuation + 1
                }
            }
            let part = String(characters[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { result.append(part) }
            if cut >= characters.count { break }
            start = max(cut - overlap, start + 1)
        }
        return result
    }

    private func embedding(_ text: String) -> Data {
        var values = [Float](repeating: 0, count: Self.dimensions)
        let scalars = Array(text.unicodeScalars.filter {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        })
        for scalar in scalars {
            let index = Int((scalar.value &* 2_654_435_761) % UInt32(Self.dimensions))
            values[index] += 1
        }
        if scalars.count > 1 {
            for index in 0..<(scalars.count - 1) {
                let hash = scalars[index].value &* 16_777_619 ^ scalars[index + 1].value
                values[Int(hash % UInt32(Self.dimensions))] += 1.5
            }
        }
        let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
        if norm > 0 { values = values.map { $0 / norm } }
        return values.withUnsafeBytes { Data($0) }
    }

    private func vector(from data: Data) -> [Float]? {
        guard data.count == Self.dimensions * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    private func cosine(_ lhs: Data, _ rhs: [Float]) -> Double {
        guard let left = vector(from: lhs), left.count == rhs.count else { return 0 }
        return Double(zip(left, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 })
    }

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: value)
    }
    private func data(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, index)))
    }
    private func int(_ stmt: OpaquePointer?, _ index: Int32) -> Int { Int(sqlite3_column_int64(stmt, index)) }
    private func real(_ stmt: OpaquePointer?, _ index: Int32) -> Double { sqlite3_column_double(stmt, index) }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: Any?) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        switch value {
        case let value as String: sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        case let value as Int: sqlite3_bind_int64(stmt, index, Int64(value))
        case let value as Double: sqlite3_bind_double(stmt, index, value)
        case let value as Data:
            _ = value.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), Self.transient)
            }
        default: sqlite3_bind_null(stmt, index)
        }
    }

    @discardableResult
    private func run(_ sql: String, _ values: Any?...) -> Int { run(sql, values) }
    @discardableResult
    private func run(_ sql: String, _ values: [Any?]) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        for (offset, value) in values.enumerated() { bind(stmt, Int32(offset + 1), value) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return Int(sqlite3_changes(db))
    }
    private func query<T>(_ sql: String, _ values: [Any?] = [], map: (OpaquePointer?) -> T) -> [T] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (offset, value) in values.enumerated() { bind(stmt, Int32(offset + 1), value) }
        var result: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(map(stmt)) }
        return result
    }
}
