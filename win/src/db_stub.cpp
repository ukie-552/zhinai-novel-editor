// db_stub.cpp - 没有 SQLite amalgamation 时的占位实现
// 编译开关: CMakeLists.txt 找不到 third_party/sqlite/sqlite3.c 时链接本文件代替 db.cpp.
#include "db.h"
#include <vector>

namespace zhinai::db {

bool init() { return false; }
void shutdown() {}

std::vector<Book> listBooks() { return {}; }
std::optional<Book> getBook(long long) { return std::nullopt; }
long long createBook(const std::string&, const std::string&, const std::string&) { return 0; }
bool updateBook(long long, const std::string&, const std::string&, const std::string&) { return false; }
bool deleteBook(long long) { return false; }

std::vector<Chapter> listChapters(long long) { return {}; }
std::optional<Chapter> getChapter(long long) { return std::nullopt; }
long long createChapter(long long, int, const std::string&) { return 0; }
bool updateChapterContent(long long, const std::string&) { return false; }
bool updateChapterTitle(long long, const std::string&) { return false; }
bool reorderChapters(long long, const std::vector<long long>&) { return false; }
bool deleteChapter(long long) { return false; }

std::vector<LoreEntry> listLore() { return {}; }
std::optional<LoreEntry> getLore(long long) { return std::nullopt; }
long long createLore(const std::string&, const std::string&, const std::string&, const std::string&) { return 0; }
bool updateLore(long long, const std::string&, const std::string&, const std::string&, const std::string&) { return false; }
bool deleteLore(long long) { return false; }
std::vector<LoreEntry> findLoreByKeywords(const std::string&) { return {}; }

std::vector<Agent> listAgents() { return {}; }
std::optional<Agent> getAgent(long long) { return std::nullopt; }
long long upsertAgent(const Agent&) { return 0; }
bool deleteAgent(long long) { return false; }

std::vector<Conversation> listConversions() { return {}; }
std::optional<Conversation> getConversation(long long) { return std::nullopt; }
long long createConversation(const std::string&, long long, long long) { return 0; }
bool deleteConversation(long long) { return false; }
std::vector<Message> listMessages(long long) { return {}; }
long long appendMessage(long long, const std::string&, const std::string&) { return 0; }

}  // namespace zhinai::db
