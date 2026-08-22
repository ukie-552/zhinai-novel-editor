import Foundation

/// 织奈书籍交换格式。聊天与模型配置属于个人工作环境，不写入书籍文件。
struct ZhinaiBookDocument: Codable {
    static let formatName = "zhinai-novel"
    static let currentVersion = 2

    var format: String
    var version: Int
    var exportedAt: Date
    var book: BookInfo
    var config: BookConfigInfo?
    var story: StoryContext?
    var publishing: PublishingInfo?
    var chapters: [BookChapter]
    var lore: [BookLoreEntry]

    struct BookInfo: Codable {
        var title: String
        var author: String?
        var description: String
        var outline: String
        /// v1/v2 早期兼容字段；新版写出时为 nil。
        var metadata: BookMetadata?
    }

    struct BookConfigInfo: Codable {
        var subtitle: String
        var authors: [String]
        var penName: String
        var genre: String
        var tags: [String]
        var platform: String
        var status: String
        var language: String
        var targetChapters: Int
        var chapterWordCount: Int
        var reviewMode: String
        var styleLibraryID: String?
        var styleStrength: Double?
    }

    struct StoryContext: Codable {
        var authorIntent: String
        var currentFocus: String
        var storyFrame: String
        var volumeOutline: String
        var bookRules: String
    }

    struct PublishingInfo: Codable {
        var seriesName: String
        var seriesNumber: String
        var targetAudience: String
        var contentRating: String
        var isbn: String
        var publisher: String
        var publicationDate: String
        var rights: String
        var source: String
    }

    struct BookChapter: Codable {
        var number: Int
        var title: String
        var content: String
    }

    struct BookLoreEntry: Codable {
        var type: String
        var title: String
        var content: String
        var keywords: [String]
        var pinned: Bool
    }

    init(novel: Novel, chapters: [Chapter], entries: [Entry]) {
        format = Self.formatName
        version = Self.currentVersion
        exportedAt = Date()
        let meta = novel.metadata
        book = BookInfo(title: novel.title, author: meta.authors.first,
                        description: novel.desc, outline: novel.outline, metadata: nil)
        config = BookConfigInfo(
            subtitle: meta.subtitle, authors: meta.authors, penName: meta.penName,
            genre: meta.genres.first ?? "", tags: meta.tags, platform: meta.platform,
            status: meta.status, language: meta.language, targetChapters: meta.targetChapters,
            chapterWordCount: meta.chapterWordCount, reviewMode: meta.reviewMode,
            styleLibraryID: nil, styleStrength: meta.styleStrength
        )
        story = StoryContext(
            authorIntent: meta.authorIntent, currentFocus: meta.currentFocus,
            storyFrame: meta.storyFrame, volumeOutline: novel.outline, bookRules: meta.bookRules
        )
        publishing = PublishingInfo(
            seriesName: meta.seriesName, seriesNumber: meta.seriesNumber,
            targetAudience: meta.targetAudience, contentRating: meta.contentRating,
            isbn: meta.isbn, publisher: meta.publisher, publicationDate: meta.publicationDate,
            rights: meta.rights, source: meta.source
        )
        self.chapters = chapters.sorted(by: { $0.no < $1.no }).map {
            BookChapter(number: $0.no, title: $0.title, content: $0.content)
        }
        lore = entries.map {
            BookLoreEntry(
                type: $0.type,
                title: $0.title,
                content: $0.content,
                keywords: $0.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                pinned: $0.pinned
            )
        }
    }

    static func read(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Self.self, from: data)
        guard document.format == formatName else { throw BookFileError.unsupportedFormat }
        guard document.version <= currentVersion else { throw BookFileError.newerVersion(document.version) }
        guard !document.book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookFileError.missingTitle
        }
        return document
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func suggestedFilename(for title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safe = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safe.isEmpty ? "未命名书籍" : safe).zhinovel.json"
    }
}

enum BookFileError: LocalizedError {
    case unsupportedFormat
    case newerVersion(Int)
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "这不是织奈书籍文件（format 应为 zhinai-novel）。"
        case .newerVersion(let version): return "书籍格式版本 \(version) 高于当前应用支持的版本。"
        case .missingTitle: return "书籍信息缺少书名。"
        }
    }
}
