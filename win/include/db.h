// db.h - SQLite 封装, 对应原 macos/DB.swift
#pragma once
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <vector>

struct sqlite3;

namespace zhinai::db {

// 初始化: 打开/创建 DB, 跑迁移.
bool init();

// 关闭
void shutdown();

// ---- 作品 (Book) ----
struct Book {
    long long id = 0;
    std::string title;
    std::string author;
    std::string summary;
    std::string platform;            // tomato/qidian/feilu/other
    int targetChapters = 0;
    int chapterWordCount = 0;
    std::string genres;              // 逗号分隔
    long long createdAt = 0;
    long long updatedAt = 0;
};
std::vector<Book> listBooks();
std::optional<Book> getBook(long long id);
long long createBook(const std::string& title, const std::string& author, const std::string& summary,
                     const std::string& platform = "", int targetChapters = 0, int chapterWordCount = 0,
                     const std::string& genres = "");
bool updateBook(long long id, const std::string& title, const std::string& author, const std::string& summary,
                const std::string& platform = "", int targetChapters = 0, int chapterWordCount = 0,
                const std::string& genres = "");
bool deleteBook(long long id);

// ---- 章节 (Chapter) ----
struct Chapter {
    long long id = 0;
    long long bookId = 0;
    int orderIndex = 0;
    std::string title;
    std::string content;
    long long updatedAt = 0;
};
std::vector<Chapter> listChapters(long long bookId);
std::optional<Chapter> getChapter(long long id);
long long createChapter(long long bookId, int orderIndex, const std::string& title);
bool updateChapterContent(long long id, const std::string& content);
bool updateChapterTitle(long long id, const std::string& title);
bool reorderChapters(long long bookId, const std::vector<long long>& orderedIds);
bool deleteChapter(long long id);

// ---- 设定 (Lore): 人物/地点/世界观/其他 ----
struct LoreEntry {
    long long id = 0;
    std::string kind;       // character | location | world | item | other
    std::string name;
    std::string content;
    std::string keywords;   // 逗号分隔触发关键词
    long long updatedAt = 0;
};
std::vector<LoreEntry> listLore();
std::optional<LoreEntry> getLore(long long id);
long long createLore(const std::string& kind, const std::string& name, const std::string& content, const std::string& keywords);
bool updateLore(long long id, const std::string& kind, const std::string& name, const std::string& content, const std::string& keywords);
bool deleteLore(long long id);

// 关键词命中检索, 给 LLM 续写时拼上下文用
std::vector<LoreEntry> findLoreByKeywords(const std::string& text);

// ---- Agent (简易: 名字 + 提示词 + 模型 + 固定技能) ----
struct Agent {
    long long id = 0;
    std::string name;
    std::string prompt;
    std::string model;
    std::string skill;  // 单一技能名
    std::string toolGroups;  // 逗号分隔: read,write,llm...
};
std::vector<Agent> listAgents();
std::optional<Agent> getAgent(long long id);
long long upsertAgent(const Agent& a);
bool deleteAgent(long long id);

// ---- 对话 (Conversation + Message) ----
struct Message {
    long long id = 0;
    long long convId = 0;
    std::string role;      // user / assistant / system
    std::string content;
    long long createdAt = 0;
};
struct Conversation {
    long long id = 0;
    std::string title;
    long long agentId = 0;
    long long bookId = 0;  // 0 = 不绑定
    long long createdAt = 0;
};
std::vector<Conversation> listConversions();
std::optional<Conversation> getConversation(long long id);
long long createConversation(const std::string& title, long long agentId, long long bookId);
bool deleteConversation(long long id);
std::vector<Message> listMessages(long long convId);
long long appendMessage(long long convId, const std::string& role, const std::string& content);

}  // namespace zhinai::db
