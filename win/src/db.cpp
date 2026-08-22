// db.cpp - SQLite 封装
#ifdef ZHINAI_HAS_SQLITE
#include "db.h"
#include "platform.h"
#include <sqlite3.h>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <sstream>
#include <stdexcept>

namespace zhinai::db {

namespace {
sqlite3* g_db = nullptr;
std::mutex g_mtx;

long long nowSec() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

void exec(const char* sql) {
    char* err = nullptr;
    if (sqlite3_exec(g_db, sql, nullptr, nullptr, &err) != SQLITE_OK) {
        std::string msg = err ? err : "unknown";
        sqlite3_free(err);
        platform::log("ERROR", std::string("SQL exec failed: ") + msg + " | sql=" + sql);
    }
}

void bindText(sqlite3_stmt* st, int idx, const std::string& v) {
    sqlite3_bind_text(st, idx, v.c_str(), (int)v.size(), SQLITE_TRANSIENT);
}

std::string colText(sqlite3_stmt* st, int idx) {
    const unsigned char* p = sqlite3_column_text(st, idx);
    if (!p) return {};
    return std::string(reinterpret_cast<const char*>(p));
}

struct ScopedStmt {
    sqlite3_stmt* p = nullptr;
    ~ScopedStmt() { if (p) sqlite3_finalize(p); }
};

#define PREP(sql)                                          \
    ScopedStmt st;                                         \
    if (sqlite3_prepare_v2(g_db, sql, -1, &st.p, nullptr)  \
        != SQLITE_OK) {                                    \
        platform::log("ERROR", "prepare failed: " sql);    \
        return {};                                         \
    }

const char* kSchema = R"sql(
CREATE TABLE IF NOT EXISTS books (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    author TEXT,
    summary TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS chapters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id INTEGER NOT NULL,
    order_index INTEGER NOT NULL DEFAULT 0,
    title TEXT NOT NULL,
    content TEXT,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_chapters_book ON chapters(book_id, order_index);
CREATE TABLE IF NOT EXISTS lore (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    content TEXT,
    keywords TEXT,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS agents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    prompt TEXT,
    model TEXT,
    skill TEXT,
    tool_groups TEXT
);
CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    agent_id INTEGER,
    book_id INTEGER,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conv_id INTEGER NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (conv_id) REFERENCES conversations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conv_id, created_at);
)sql";

// 增量迁移: 给 books 加 metadata 列 (platform, target_chapters, chapter_word_count, genres)
static void migrateBooksMetadata(sqlite3* db) {
    auto hasColumn = [&](const char* col) -> bool {
        sqlite3_stmt* st = nullptr;
        if (sqlite3_prepare_v2(db, "PRAGMA table_info(books)", -1, &st, nullptr) != SQLITE_OK) return false;
        bool found = false;
        while (sqlite3_step(st) == SQLITE_ROW) {
            const unsigned char* name = sqlite3_column_text(st, 1);
            if (name && std::string(reinterpret_cast<const char*>(name)) == col) { found = true; break; }
        }
        sqlite3_finalize(st);
        return found;
    };
    if (!hasColumn("platform"))        sqlite3_exec(db, "ALTER TABLE books ADD COLUMN platform TEXT", nullptr, nullptr, nullptr);
    if (!hasColumn("target_chapters")) sqlite3_exec(db, "ALTER TABLE books ADD COLUMN target_chapters INTEGER", nullptr, nullptr, nullptr);
    if (!hasColumn("chapter_word_count")) sqlite3_exec(db, "ALTER TABLE books ADD COLUMN chapter_word_count INTEGER", nullptr, nullptr, nullptr);
    if (!hasColumn("genres"))          sqlite3_exec(db, "ALTER TABLE books ADD COLUMN genres TEXT", nullptr, nullptr, nullptr);
}

// 增量迁移: 给 agents 加 icon / lore_ids
static void migrateAgents(sqlite3* db) {
    auto hasColumn = [&](const char* col) -> bool {
        sqlite3_stmt* st = nullptr;
        if (sqlite3_prepare_v2(db, "PRAGMA table_info(agents)", -1, &st, nullptr) != SQLITE_OK) return false;
        bool found = false;
        while (sqlite3_step(st) == SQLITE_ROW) {
            const unsigned char* name = sqlite3_column_text(st, 1);
            if (name && std::string(reinterpret_cast<const char*>(name)) == col) { found = true; break; }
        }
        sqlite3_finalize(st);
        return found;
    };
    if (!hasColumn("icon"))      sqlite3_exec(db, "ALTER TABLE agents ADD COLUMN icon TEXT", nullptr, nullptr, nullptr);
    if (!hasColumn("lore_ids"))   sqlite3_exec(db, "ALTER TABLE agents ADD COLUMN lore_ids TEXT", nullptr, nullptr, nullptr);
}

}  // namespace

bool init() {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_db) return true;
    auto path = platform::dbPath().string();
    int rc = sqlite3_open(path.c_str(), &g_db);
    if (rc != SQLITE_OK) {
        platform::log("ERROR", std::string("sqlite3_open failed: ") + sqlite3_errmsg(g_db));
        if (g_db) { sqlite3_close(g_db); g_db = nullptr; }
        return false;
    }
    exec("PRAGMA foreign_keys = ON;");
    exec("PRAGMA journal_mode = WAL;");
    exec(kSchema);
    migrateBooksMetadata(g_db);
    migrateAgents(g_db);
    platform::log("INFO", "db.init: " + path);
    return true;
}

void shutdown() {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_db) {
        sqlite3_close(g_db);
        g_db = nullptr;
    }
}

// ---- Book ----
static void fillBookFromStmt(Book& b, sqlite3_stmt* st) {
    b.id = sqlite3_column_int64(st, 0);
    b.title = colText(st, 1);
    b.author = colText(st, 2);
    b.summary = colText(st, 3);
    b.platform = colText(st, 4);
    b.targetChapters = sqlite3_column_int(st, 5);
    b.chapterWordCount = sqlite3_column_int(st, 6);
    b.genres = colText(st, 7);
    b.createdAt = sqlite3_column_int64(st, 8);
    b.updatedAt = sqlite3_column_int64(st, 9);
}

std::vector<Book> listBooks() {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<Book> out;
    PREP("SELECT id,title,author,summary,platform,target_chapters,chapter_word_count,genres,created_at,updated_at FROM books ORDER BY id DESC")
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        Book b; fillBookFromStmt(b, st.p); out.push_back(std::move(b));
    }
    return out;
}

std::optional<Book> getBook(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("SELECT id,title,author,summary,platform,target_chapters,chapter_word_count,genres,created_at,updated_at FROM books WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    if (sqlite3_step(st.p) == SQLITE_ROW) {
        Book b; fillBookFromStmt(b, st.p); return b;
    }
    return std::nullopt;
}

long long createBook(const std::string& title, const std::string& author, const std::string& summary,
                     const std::string& platform, int targetChapters, int chapterWordCount,
                     const std::string& genres) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("INSERT INTO books(title,author,summary,platform,target_chapters,chapter_word_count,genres,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)")
    bindText(st.p, 1, title);
    bindText(st.p, 2, author);
    bindText(st.p, 3, summary);
    bindText(st.p, 4, platform);
    sqlite3_bind_int(st.p, 5, targetChapters);
    sqlite3_bind_int(st.p, 6, chapterWordCount);
    bindText(st.p, 7, genres);
    auto t = nowSec();
    sqlite3_bind_int64(st.p, 8, t);
    sqlite3_bind_int64(st.p, 9, t);
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

bool updateBook(long long id, const std::string& title, const std::string& author, const std::string& summary,
                const std::string& platform, int targetChapters, int chapterWordCount,
                const std::string& genres) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("UPDATE books SET title=?,author=?,summary=?,platform=?,target_chapters=?,chapter_word_count=?,genres=?,updated_at=? WHERE id=?")
    bindText(st.p, 1, title);
    bindText(st.p, 2, author);
    bindText(st.p, 3, summary);
    bindText(st.p, 4, platform);
    sqlite3_bind_int(st.p, 5, targetChapters);
    sqlite3_bind_int(st.p, 6, chapterWordCount);
    bindText(st.p, 7, genres);
    sqlite3_bind_int64(st.p, 8, nowSec());
    sqlite3_bind_int64(st.p, 9, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

bool deleteBook(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("DELETE FROM books WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

// ---- Chapter ----
std::vector<Chapter> listChapters(long long bookId) {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<Chapter> out;
    PREP("SELECT id,book_id,order_index,title,content,updated_at FROM chapters WHERE book_id=? ORDER BY order_index, id")
    sqlite3_bind_int64(st.p, 1, bookId);
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        Chapter c;
        c.id = sqlite3_column_int64(st.p, 0);
        c.bookId = sqlite3_column_int64(st.p, 1);
        c.orderIndex = sqlite3_column_int64(st.p, 2);
        c.title = colText(st.p, 3);
        c.content = colText(st.p, 4);
        c.updatedAt = sqlite3_column_int64(st.p, 5);
        out.push_back(std::move(c));
    }
    return out;
}

std::optional<Chapter> getChapter(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("SELECT id,book_id,order_index,title,content,updated_at FROM chapters WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    if (sqlite3_step(st.p) == SQLITE_ROW) {
        Chapter c;
        c.id = sqlite3_column_int64(st.p, 0);
        c.bookId = sqlite3_column_int64(st.p, 1);
        c.orderIndex = sqlite3_column_int64(st.p, 2);
        c.title = colText(st.p, 3);
        c.content = colText(st.p, 4);
        c.updatedAt = sqlite3_column_int64(st.p, 5);
        return c;
    }
    return std::nullopt;
}

long long createChapter(long long bookId, int orderIndex, const std::string& title) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("INSERT INTO chapters(book_id,order_index,title,content,updated_at) VALUES(?,?,?,'',?)")
    sqlite3_bind_int64(st.p, 1, bookId);
    sqlite3_bind_int64(st.p, 2, orderIndex);
    bindText(st.p, 3, title);
    sqlite3_bind_int64(st.p, 4, nowSec());
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

bool updateChapterContent(long long id, const std::string& content) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("UPDATE chapters SET content=?, updated_at=? WHERE id=?")
    bindText(st.p, 1, content);
    sqlite3_bind_int64(st.p, 2, nowSec());
    sqlite3_bind_int64(st.p, 3, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

bool updateChapterTitle(long long id, const std::string& title) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("UPDATE chapters SET title=?, updated_at=? WHERE id=?")
    bindText(st.p, 1, title);
    sqlite3_bind_int64(st.p, 2, nowSec());
    sqlite3_bind_int64(st.p, 3, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

bool reorderChapters(long long bookId, const std::vector<long long>& orderedIds) {
    std::lock_guard<std::mutex> lk(g_mtx);
    exec("BEGIN");
    bool ok = true;
    for (size_t i = 0; i < orderedIds.size(); ++i) {
        ScopedStmt st;
        if (sqlite3_prepare_v2(g_db, "UPDATE chapters SET order_index=? WHERE id=? AND book_id=?", -1, &st.p, nullptr) != SQLITE_OK) {
            ok = false; break;
        }
        sqlite3_bind_int64(st.p, 1, (long long)i);
        sqlite3_bind_int64(st.p, 2, orderedIds[i]);
        sqlite3_bind_int64(st.p, 3, bookId);
        if (sqlite3_step(st.p) != SQLITE_DONE) { ok = false; break; }
    }
    exec(ok ? "COMMIT" : "ROLLBACK");
    return ok;
}

bool deleteChapter(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("DELETE FROM chapters WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

// ---- Lore ----
std::vector<LoreEntry> listLore() {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<LoreEntry> out;
    PREP("SELECT id,kind,name,content,keywords,updated_at FROM lore ORDER BY kind, name")
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        LoreEntry e;
        e.id = sqlite3_column_int64(st.p, 0);
        e.kind = colText(st.p, 1);
        e.name = colText(st.p, 2);
        e.content = colText(st.p, 3);
        e.keywords = colText(st.p, 4);
        e.updatedAt = sqlite3_column_int64(st.p, 5);
        out.push_back(std::move(e));
    }
    return out;
}

std::optional<LoreEntry> getLore(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("SELECT id,kind,name,content,keywords,updated_at FROM lore WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    if (sqlite3_step(st.p) == SQLITE_ROW) {
        LoreEntry e;
        e.id = sqlite3_column_int64(st.p, 0);
        e.kind = colText(st.p, 1);
        e.name = colText(st.p, 2);
        e.content = colText(st.p, 3);
        e.keywords = colText(st.p, 4);
        e.updatedAt = sqlite3_column_int64(st.p, 5);
        return e;
    }
    return std::nullopt;
}

long long createLore(const std::string& kind, const std::string& name, const std::string& content, const std::string& keywords) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("INSERT INTO lore(kind,name,content,keywords,updated_at) VALUES(?,?,?,?,?)")
    bindText(st.p, 1, kind);
    bindText(st.p, 2, name);
    bindText(st.p, 3, content);
    bindText(st.p, 4, keywords);
    sqlite3_bind_int64(st.p, 5, nowSec());
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

bool updateLore(long long id, const std::string& kind, const std::string& name, const std::string& content, const std::string& keywords) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("UPDATE lore SET kind=?,name=?,content=?,keywords=?,updated_at=? WHERE id=?")
    bindText(st.p, 1, kind);
    bindText(st.p, 2, name);
    bindText(st.p, 3, content);
    bindText(st.p, 4, keywords);
    sqlite3_bind_int64(st.p, 5, nowSec());
    sqlite3_bind_int64(st.p, 6, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

bool deleteLore(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("DELETE FROM lore WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

std::vector<LoreEntry> findLoreByKeywords(const std::string& text) {
    std::vector<LoreEntry> all = listLore();
    std::vector<LoreEntry> hits;
    for (auto& e : all) {
        if (e.keywords.empty()) continue;
        std::stringstream ss(e.keywords);
        std::string kw;
        while (std::getline(ss, kw, ',')) {
            // trim
            size_t a = kw.find_first_not_of(" \t");
            size_t b = kw.find_last_not_of(" \t");
            if (a == std::string::npos) continue;
            kw = kw.substr(a, b - a + 1);
            if (!kw.empty() && text.find(kw) != std::string::npos) {
                hits.push_back(e);
                break;
            }
        }
    }
    return hits;
}

// ---- Agent ----
static void fillAgentFromStmt(Agent& a, sqlite3_stmt* st) {
    a.id = sqlite3_column_int64(st, 0);
    a.name = colText(st, 1);
    a.icon = colText(st, 2);
    a.prompt = colText(st, 3);
    a.model = colText(st, 4);
    a.skill = colText(st, 5);
    a.toolGroups = colText(st, 6);
    a.loreIds = colText(st, 7);
}

std::vector<Agent> listAgents() {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<Agent> out;
    PREP("SELECT id,name,icon,prompt,model,skill,tool_groups,lore_ids FROM agents ORDER BY id")
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        Agent a; fillAgentFromStmt(a, st.p); out.push_back(std::move(a));
    }
    return out;
}

std::optional<Agent> getAgent(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("SELECT id,name,icon,prompt,model,skill,tool_groups,lore_ids FROM agents WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    if (sqlite3_step(st.p) == SQLITE_ROW) {
        Agent a; fillAgentFromStmt(a, st.p); return a;
    }
    return std::nullopt;
}

long long upsertAgent(const Agent& a) {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (a.id > 0) {
        PREP("UPDATE agents SET name=?,icon=?,prompt=?,model=?,skill=?,tool_groups=?,lore_ids=? WHERE id=?")
        bindText(st.p, 1, a.name);
        bindText(st.p, 2, a.icon);
        bindText(st.p, 3, a.prompt);
        bindText(st.p, 4, a.model);
        bindText(st.p, 5, a.skill);
        bindText(st.p, 6, a.toolGroups);
        bindText(st.p, 7, a.loreIds);
        sqlite3_bind_int64(st.p, 8, a.id);
        sqlite3_step(st.p);
        return a.id;
    }
    PREP("INSERT INTO agents(name,icon,prompt,model,skill,tool_groups,lore_ids) VALUES(?,?,?,?,?,?,?)")
    bindText(st.p, 1, a.name);
    bindText(st.p, 2, a.icon);
    bindText(st.p, 3, a.prompt);
    bindText(st.p, 4, a.model);
    bindText(st.p, 5, a.skill);
    bindText(st.p, 6, a.toolGroups);
    bindText(st.p, 7, a.loreIds);
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

bool deleteAgent(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("DELETE FROM agents WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

// ---- Conversation / Message ----
std::vector<Conversation> listConversions() {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<Conversation> out;
    PREP("SELECT id,title,agent_id,book_id,created_at FROM conversations ORDER BY id DESC")
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        Conversation c;
        c.id = sqlite3_column_int64(st.p, 0);
        c.title = colText(st.p, 1);
        c.agentId = sqlite3_column_int64(st.p, 2);
        c.bookId = sqlite3_column_int64(st.p, 3);
        c.createdAt = sqlite3_column_int64(st.p, 4);
        out.push_back(std::move(c));
    }
    return out;
}

std::optional<Conversation> getConversation(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("SELECT id,title,agent_id,book_id,created_at FROM conversations WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    if (sqlite3_step(st.p) == SQLITE_ROW) {
        Conversation c;
        c.id = sqlite3_column_int64(st.p, 0);
        c.title = colText(st.p, 1);
        c.agentId = sqlite3_column_int64(st.p, 2);
        c.bookId = sqlite3_column_int64(st.p, 3);
        c.createdAt = sqlite3_column_int64(st.p, 4);
        return c;
    }
    return std::nullopt;
}

long long createConversation(const std::string& title, long long agentId, long long bookId) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("INSERT INTO conversations(title,agent_id,book_id,created_at) VALUES(?,?,?,?)")
    bindText(st.p, 1, title);
    sqlite3_bind_int64(st.p, 2, agentId);
    sqlite3_bind_int64(st.p, 3, bookId);
    sqlite3_bind_int64(st.p, 4, nowSec());
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

bool deleteConversation(long long id) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("DELETE FROM conversations WHERE id=?")
    sqlite3_bind_int64(st.p, 1, id);
    return sqlite3_step(st.p) == SQLITE_DONE;
}

std::vector<Message> listMessages(long long convId) {
    std::lock_guard<std::mutex> lk(g_mtx);
    std::vector<Message> out;
    PREP("SELECT id,conv_id,role,content,created_at FROM messages WHERE conv_id=? ORDER BY id")
    sqlite3_bind_int64(st.p, 1, convId);
    while (sqlite3_step(st.p) == SQLITE_ROW) {
        Message m;
        m.id = sqlite3_column_int64(st.p, 0);
        m.convId = sqlite3_column_int64(st.p, 1);
        m.role = colText(st.p, 2);
        m.content = colText(st.p, 3);
        m.createdAt = sqlite3_column_int64(st.p, 4);
        out.push_back(std::move(m));
    }
    return out;
}

long long appendMessage(long long convId, const std::string& role, const std::string& content) {
    std::lock_guard<std::mutex> lk(g_mtx);
    PREP("INSERT INTO messages(conv_id,role,content,created_at) VALUES(?,?,?,?)")
    sqlite3_bind_int64(st.p, 1, convId);
    bindText(st.p, 2, role);
    bindText(st.p, 3, content);
    sqlite3_bind_int64(st.p, 4, nowSec());
    if (sqlite3_step(st.p) != SQLITE_DONE) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

}  // namespace zhinai::db
#endif  // ZHINAI_HAS_SQLITE
