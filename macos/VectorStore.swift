import Foundation
import SQLite3

struct VectorLibrary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let sourcePath: String
    let author: String
    let category: String
    let summary: String
    let externalID: String
    let wordCount: Int
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
    let externalID: String
    let wordCount: Int
    let chapters: [Chapter]
}

enum NovelTextParser {
    struct Metadata {
        let title: String
        let author: String
        let summary: String
        let externalID: String
        let wordCount: Int
    }

    static func metadata(url: URL) -> Metadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 128 * 1024),
              let header = String(data: data, encoding: .utf8) else { return nil }
        let preface = header.components(separatedBy: "————————————————").first ?? header
        return Metadata(title: field("书名", in: preface) ?? url.deletingPathExtension().lastPathComponent,
                        author: field("作者", in: preface) ?? "",
                        summary: summaryFromPreface(preface, fallback: ""),
                        externalID: field("书籍 ID", in: preface) ?? field("书籍ID", in: preface) ?? field("书籍id", in: preface) ?? "",
                        wordCount: parseWordCount(field("字数", in: preface) ?? ""))
    }

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
        let externalID = field("书籍 ID", in: preface) ?? field("书籍ID", in: preface) ?? field("书籍id", in: preface) ?? ""
        let wordCount = parseWordCount(field("字数", in: preface) ?? "")
        let summary = summaryFromPreface(preface, fallback: chapters.first?.content ?? "")
        return ParsedNovelText(title: title, author: author, summary: summary,
                               externalID: externalID, wordCount: wordCount, chapters: chapters)
    }

    private static func field(_ name: String, in text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("\(name)：") || $0.hasPrefix("\(name):") }
            .map { line in
                String(line.drop(while: { $0 != "：" && $0 != ":" }).dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private static func summaryFromPreface(_ text: String, fallback: String) -> String {
        var candidate = ""
        if let marker = text.range(of: "【简介】") {
            let following = text[marker.upperBound...]
            let divider = following.range(of: "————————————————")?.lowerBound ?? following.endIndex
            candidate = String(following[..<divider])
        } else {
            candidate = text.split(separator: "\n")
                .map(String.init)
                .filter { line in
                    let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !clean.isEmpty && !clean.hasPrefix("书名：") && !clean.hasPrefix("书名:")
                        && !clean.hasPrefix("作者：") && !clean.hasPrefix("作者:")
                        && !clean.allSatisfy { "—-=─".contains($0) }
                }
                .joined(separator: "\n")
        }
        if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { candidate = fallback }
        let clean = candidate.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(600))
    }

    private static func parseWordCount(_ raw: String) -> Int {
        let normalized = raw.replacingOccurrences(of: "字", with: "")
            .replacingOccurrences(of: " ", with: "")
        let multiplier: Double = normalized.contains("万") ? 10_000 : 1
        let number = normalized.replacingOccurrences(of: "万", with: "")
        return Int(((Double(number) ?? 0) * multiplier).rounded())
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
        query("SELECT id,title,source_path,author,category,summary,external_id,word_count,chapter_count,chunk_count,created_at FROM vector_libraries ORDER BY created_at DESC") { stmt in
            VectorLibrary(
                id: UUID(uuidString: text(stmt, 0) ?? "")!,
                title: text(stmt, 1) ?? "未命名小说",
                sourcePath: text(stmt, 2) ?? "",
                author: text(stmt, 3) ?? "",
                category: text(stmt, 4) ?? "",
                summary: text(stmt, 5) ?? "",
                externalID: text(stmt, 6) ?? "",
                wordCount: int(stmt, 7),
                chapterCount: int(stmt, 8),
                chunkCount: int(stmt, 9),
                createdAt: Date(timeIntervalSince1970: real(stmt, 10))
            )
        }
    }

    func searchLibraries(_ searchText: String) -> [VectorLibrary] {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return libraries() }
        let columns = "l.id,l.title,l.source_path,l.author,l.category,l.summary,l.external_id,l.word_count,l.chapter_count,l.chunk_count,l.created_at"
        let rows: [VectorLibrary]
        if clean.count >= 3 {
            var indexed = query("""
                SELECT \(columns) FROM vector_libraries_fts f
                JOIN vector_libraries l ON l.rowid=f.rowid
                WHERE vector_libraries_fts MATCH ? ORDER BY rank LIMIT 100
                """, [ftsPhrase(clean)], map: library(from:))
            let categoryMatches = query("""
                SELECT \(columns) FROM vector_libraries l
                WHERE category LIKE ? OR external_id LIKE ? ORDER BY created_at DESC LIMIT 100
                """, ["\(clean)%", "\(clean)%"], map: library(from:))
            let existing = Set(indexed.map(\.id))
            indexed.append(contentsOf: categoryMatches.filter { !existing.contains($0.id) })
            rows = indexed
        } else {
            let pattern = "%\(clean)%"
            rows = query("""
                SELECT \(columns) FROM vector_libraries l
                WHERE title LIKE ? OR author LIKE ? OR category LIKE ? OR summary LIKE ? OR external_id LIKE ?
                ORDER BY created_at DESC LIMIT 100
                """, [pattern, pattern, pattern, pattern, pattern], map: library(from:))
        }
        return rows
    }

    @discardableResult
    func updateLibrary(_ library: VectorLibrary, title: String, author: String, category: String, summary: String) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        exec("BEGIN IMMEDIATE TRANSACTION")
        let changed = run("UPDATE vector_libraries SET title=?,author=?,category=?,summary=? WHERE id=?",
                          cleanTitle, cleanAuthor, cleanCategory, cleanSummary, library.id.uuidString) > 0
        if changed {
            run("DELETE FROM vector_libraries_fts WHERE rowid=(SELECT rowid FROM vector_libraries WHERE id=?)", library.id.uuidString)
            run("""
                INSERT INTO vector_libraries_fts(rowid,library_id,title,author,summary)
                SELECT rowid,id,title,author,summary FROM vector_libraries WHERE id=?
                """, library.id.uuidString)
        }
        exec("COMMIT")
        return changed
    }

    @discardableResult
    func refreshLibraryMetadata(_ library: VectorLibrary) -> Bool {
        guard let metadata = NovelTextParser.metadata(url: URL(fileURLWithPath: library.sourcePath)) else { return false }
        exec("BEGIN IMMEDIATE TRANSACTION")
        let changed = run("UPDATE vector_libraries SET title=?,author=?,summary=?,external_id=?,word_count=? WHERE id=?",
                          metadata.title, metadata.author, metadata.summary, metadata.externalID,
                          metadata.wordCount, library.id.uuidString) > 0
        if changed {
            run("DELETE FROM vector_libraries_fts WHERE rowid=(SELECT rowid FROM vector_libraries WHERE id=?)", library.id.uuidString)
            run("""
                INSERT INTO vector_libraries_fts(rowid,library_id,title,author,summary)
                SELECT rowid,id,title,author,summary FROM vector_libraries WHERE id=?
                """, library.id.uuidString)
        }
        exec("COMMIT")
        return changed
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
        if !parsed.externalID.isEmpty,
           let existing = libraries().first(where: { $0.externalID == parsed.externalID }) {
            delete(existing)
        }

        let library = VectorLibrary(id: UUID(), title: parsed.title, sourcePath: url.path,
                                    author: parsed.author, category: "", summary: parsed.summary,
                                    externalID: parsed.externalID, wordCount: parsed.wordCount,
                                    chapterCount: parsed.chapters.count, chunkCount: 0, createdAt: Date())
        let chunks = parsed.chapters.flatMap { chapter in
            split(chapter.content).enumerated().map { index, content in
                (chapter.no, chapter.title, index + 1, content)
            }
        }

        exec("BEGIN IMMEDIATE TRANSACTION")
        defer { exec("COMMIT") }
        run("INSERT INTO vector_libraries(id,title,source_path,author,summary,external_id,word_count,chapter_count,chunk_count,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",
            library.id.uuidString, library.title, library.sourcePath, parsed.author, parsed.summary,
            parsed.externalID, parsed.wordCount,
            library.chapterCount, chunks.count, library.createdAt.timeIntervalSince1970)
        run("""
            INSERT INTO vector_libraries_fts(rowid,library_id,title,author,summary)
            SELECT rowid,id,title,author,summary FROM vector_libraries WHERE id=?
            """, library.id.uuidString)

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
        }
        return VectorLibrary(id: library.id, title: library.title, sourcePath: library.sourcePath,
                             author: library.author, category: library.category, summary: library.summary,
                             externalID: library.externalID, wordCount: library.wordCount,
                             chapterCount: library.chapterCount, chunkCount: chunks.count, createdAt: library.createdAt)
    }

    func delete(_ library: VectorLibrary) {
        run("DELETE FROM vector_libraries_fts WHERE rowid=(SELECT rowid FROM vector_libraries WHERE id=?)", library.id.uuidString)
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
        run("DELETE FROM vector_chunks WHERE library_id=? AND chapter_no=?", chapter.libraryID.uuidString, chapter.no)
        for (index, piece) in pieces.enumerated() {
            let id = UUID()
            run("INSERT INTO vector_chunks(id,library_id,chapter_no,chapter_title,chunk_no,content,embedding,created_at) VALUES(?,?,?,?,?,?,?,?)",
                id.uuidString, chapter.libraryID.uuidString, chapter.no, cleanTitle, index + 1, piece,
                embedding(piece), now.timeIntervalSince1970)
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
        let columns = "c.id,c.chapter_no,c.chapter_title,c.chunk_no,c.content,c.embedding"
        var rows: [(UUID, Int, String, Int, String, Data)] = []
        if queryText.count >= 3 {
            rows = query("""
                SELECT \(columns) FROM vector_chunks_fts f
                JOIN vector_chunks c ON c.rowid=f.rowid
                WHERE vector_chunks_fts MATCH ? AND c.library_id=?
                ORDER BY rank LIMIT 800
                """, [ftsPhrase(queryText), libraryID.uuidString], map: vectorRow(from:))
        }
        // 短词或无全文命中时只取一个有界候选集，避免大库搜索时整表载入内存。
        if rows.isEmpty {
            rows = query("""
                SELECT \(columns) FROM vector_chunks c WHERE c.library_id=?
                ORDER BY c.chapter_no ASC,c.chunk_no ASC LIMIT 2000
                """, [libraryID.uuidString], map: vectorRow(from:))
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

    /// 从本地正文提取抽象写法画像。返回值不包含原句、专名或情节片段。
    func styleProfile(libraryID: UUID) -> String? {
        let texts: [String] = query(
            "SELECT content FROM vector_chapters WHERE library_id=? ORDER BY no ASC LIMIT 160",
            [libraryID.uuidString]
        ) { text($0, 0) ?? "" }
        let corpus = String(texts.joined(separator: "\n").prefix(600_000))
        guard corpus.count >= 200 else { return nil }

        let sentences = corpus.components(separatedBy: CharacterSet(charactersIn: "。！？!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let paragraphs = corpus.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty, !paragraphs.isEmpty else { return nil }

        let sentenceLengths = sentences.map(\.count)
        let averageSentence = Double(sentenceLengths.reduce(0, +)) / Double(sentenceLengths.count)
        let shortRatio = Double(sentenceLengths.filter { $0 <= 14 }.count) / Double(sentenceLengths.count)
        let averageParagraph = Double(paragraphs.map(\.count).reduce(0, +)) / Double(paragraphs.count)
        let dialoguePattern = try? NSRegularExpression(pattern: "[“「『][^”」』]{1,500}[”」』]")
        let corpusRange = NSRange(corpus.startIndex..., in: corpus)
        let dialogueCharacters = dialoguePattern?.matches(in: corpus, range: corpusRange)
            .reduce(0) { $0 + $1.range.length } ?? 0
        let visibleCount = max(1, corpus.filter { !$0.isWhitespace }.count)
        let dialogueRatio = min(1, Double(dialogueCharacters) / Double(visibleCount))
        let questionRate = Double(corpus.filter { $0 == "？" || $0 == "?" }.count) * 1000 / Double(visibleCount)
        let exclamationRate = Double(corpus.filter { $0 == "！" || $0 == "!" }.count) * 1000 / Double(visibleCount)
        let firstPerson = corpus.filter { $0 == "我" }.count
        let thirdPerson = corpus.filter { $0 == "他" || $0 == "她" }.count
        let viewpoint = firstPerson > thirdPerson * 2 ? "第一人称倾向" : (thirdPerson > firstPerson * 2 ? "第三人称倾向" : "人称混合或不明显")
        let rhythm = shortRatio >= 0.45 ? "短句密集、推进偏快" : (shortRatio <= 0.22 ? "长句较多、铺陈偏充分" : "长短句交替、节奏中等")
        let paragraphStyle = averageParagraph <= 55 ? "段落短促" : (averageParagraph >= 130 ? "段落较长" : "段落长度适中")
        let dialogueStyle = dialogueRatio >= 0.38 ? "对话驱动明显" : (dialogueRatio <= 0.15 ? "叙述与描写占主导" : "对话与叙述较均衡")

        return """
        【写法向量画像｜仅学习技法，不得复用原句、专名或情节】
        - 句法节奏：平均句长约 \(Int(averageSentence.rounded())) 字；短句占比约 \(Int((shortRatio * 100).rounded()))%；\(rhythm)。
        - 段落组织：平均每段约 \(Int(averageParagraph.rounded())) 字；\(paragraphStyle)。
        - 叙述构成：对话文本约占 \(Int((dialogueRatio * 100).rounded()))%；\(dialogueStyle)；\(viewpoint)。
        - 标点张力：每千字约 \(String(format: "%.1f", questionRate)) 个问号、\(String(format: "%.1f", exclamationRate)) 个感叹号。
        - 执行边界：只迁移上述抽象节奏与组织习惯；禁止复现参考库中的连续措辞、人物、地点、设定、事件和标志性表达。
        """
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS vector_libraries(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, source_path TEXT NOT NULL, author TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT '',
          summary TEXT NOT NULL DEFAULT '', external_id TEXT NOT NULL DEFAULT '', word_count INTEGER NOT NULL DEFAULT 0,
          chapter_count INTEGER NOT NULL, chunk_count INTEGER NOT NULL,
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
        CREATE INDEX IF NOT EXISTS vector_chapters_updated_index ON vector_chapters(library_id, updated_at DESC);
        CREATE INDEX IF NOT EXISTS vector_chunks_library_index ON vector_chunks(library_id, chapter_no, chunk_no);
        CREATE UNIQUE INDEX IF NOT EXISTS vector_libraries_source_index ON vector_libraries(source_path);
        CREATE INDEX IF NOT EXISTS vector_libraries_created_index ON vector_libraries(created_at DESC);
        CREATE VIRTUAL TABLE IF NOT EXISTS vector_libraries_fts USING fts5(
          library_id UNINDEXED, title, author, summary, tokenize='trigram'
        );
        """)
        // 老版本数据库没有分类列；重复执行时 SQLite 会忽略 duplicate column 错误。
        exec("ALTER TABLE vector_libraries ADD COLUMN category TEXT NOT NULL DEFAULT ''")
        exec("ALTER TABLE vector_libraries ADD COLUMN external_id TEXT NOT NULL DEFAULT ''")
        exec("ALTER TABLE vector_libraries ADD COLUMN word_count INTEGER NOT NULL DEFAULT 0")
        exec("CREATE INDEX IF NOT EXISTS vector_libraries_category_index ON vector_libraries(category)")
        exec("CREATE INDEX IF NOT EXISTS vector_libraries_external_id_index ON vector_libraries(external_id)")
        configureChunkSearchIndex()
        // 为升级前已经存在的书籍补建目录全文索引。
        exec("""
        INSERT INTO vector_libraries_fts(rowid,library_id,title,author,summary)
        SELECT l.rowid,l.id,l.title,l.author,l.summary FROM vector_libraries l
        WHERE NOT EXISTS(SELECT 1 FROM vector_libraries_fts f WHERE f.rowid=l.rowid);
        """)
    }

    /// 使用 external-content FTS：索引只保存倒排信息，正文仍以 vector_chunks 为唯一副本。
    private func configureChunkSearchIndex() {
        let existing: String = query(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='vector_chunks_fts'"
        ) { text($0, 0) ?? "" }.first ?? ""
        let isExternal = existing.contains("content='vector_chunks'") || existing.contains("content=\"vector_chunks\"")
        if !existing.isEmpty && !isExternal {
            exec("DROP TABLE vector_chunks_fts")
        }
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS vector_chunks_fts USING fts5(
          content, chapter_title, content='vector_chunks', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS vector_chunks_fts_insert AFTER INSERT ON vector_chunks BEGIN
          INSERT INTO vector_chunks_fts(rowid,content,chapter_title) VALUES(new.rowid,new.content,new.chapter_title);
        END;
        CREATE TRIGGER IF NOT EXISTS vector_chunks_fts_delete AFTER DELETE ON vector_chunks BEGIN
          INSERT INTO vector_chunks_fts(vector_chunks_fts,rowid,content,chapter_title)
          VALUES('delete',old.rowid,old.content,old.chapter_title);
        END;
        CREATE TRIGGER IF NOT EXISTS vector_chunks_fts_update AFTER UPDATE ON vector_chunks BEGIN
          INSERT INTO vector_chunks_fts(vector_chunks_fts,rowid,content,chapter_title)
          VALUES('delete',old.rowid,old.content,old.chapter_title);
          INSERT INTO vector_chunks_fts(rowid,content,chapter_title) VALUES(new.rowid,new.content,new.chapter_title);
        END;
        """)
        if !isExternal {
            exec("INSERT INTO vector_chunks_fts(vector_chunks_fts) VALUES('rebuild')")
        }
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
        // 新数据使用 UInt8 量化，单片段由 1024B 降至 256B；读取端仍兼容旧 Float32 数据。
        return Data(values.map { UInt8(max(0, min(255, Int(($0 * 255).rounded())))) })
    }

    private func vector(from data: Data) -> [Float]? {
        if data.count == Self.dimensions {
            return data.map { Float($0) / 255 }
        }
        guard data.count == Self.dimensions * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    private func library(from stmt: OpaquePointer?) -> VectorLibrary {
        VectorLibrary(id: UUID(uuidString: text(stmt, 0) ?? "")!,
                      title: text(stmt, 1) ?? "未命名小说", sourcePath: text(stmt, 2) ?? "",
                      author: text(stmt, 3) ?? "", category: text(stmt, 4) ?? "",
                      summary: text(stmt, 5) ?? "", externalID: text(stmt, 6) ?? "", wordCount: int(stmt, 7),
                      chapterCount: int(stmt, 8), chunkCount: int(stmt, 9),
                      createdAt: Date(timeIntervalSince1970: real(stmt, 10)))
    }

    private func vectorRow(from stmt: OpaquePointer?) -> (UUID, Int, String, Int, String, Data) {
        (UUID(uuidString: text(stmt, 0) ?? "")!, int(stmt, 1), text(stmt, 2) ?? "",
         int(stmt, 3), text(stmt, 4) ?? "", data(stmt, 5) ?? Data())
    }

    private func ftsPhrase(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
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
