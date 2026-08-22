// vector_store.cpp - 极简版本地向量库 (词频倒排, 无 embedding)
// 第一版: 内存 + JSON 持久化, 后续可换 sqlite-vss / hnswlib.
#include "vector_store.h"
#include "platform.h"
#include <algorithm>
#include <cctype>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace zhinai::vector {

namespace {

struct Chunk {
    std::string source;
    std::string snippet;       // 第一段作为 snippet
    std::map<std::string, int> tf;  // 词 -> 频
};

std::vector<Chunk> g_chunks;
std::mutex g_mtx;
std::string g_indexPath() { return (platform::dataDir() / "vectors" / "index.json").string(); }

std::string normalize(const std::string& w) {
    std::string s;
    for (char c : w) {
        if (std::isalnum((unsigned char)c)) s.push_back(std::tolower((unsigned char)c));
    }
    return s;
}

std::vector<std::string> tokenize(const std::string& text) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : text) {
        if (std::isalnum((unsigned char)c)) {
            cur.push_back(c);
        } else {
            if (!cur.empty()) {
                auto n = normalize(cur);
                if (!n.empty()) out.push_back(n);
                cur.clear();
            }
        }
    }
    if (!cur.empty()) {
        auto n = normalize(cur);
        if (!n.empty()) out.push_back(n);
    }
    return out;
}

std::map<std::string, int> computeTf(const std::string& text) {
    std::map<std::string, int> tf;
    for (auto& t : tokenize(text)) tf[t]++;
    return tf;
}

void loadFromDisk() {
    g_chunks.clear();
    std::ifstream f(g_indexPath());
    if (!f) return;
    try {
        nlohmann::json j;
        f >> j;
        if (!j.is_array()) return;
        for (auto& item : j) {
            Chunk c;
            c.source = item.value("source", "");
            c.snippet = item.value("snippet", "");
            if (item.contains("tf") && item["tf"].is_object()) {
                for (auto it = item["tf"].begin(); it != item["tf"].end(); ++it) {
                    c.tf[it.key()] = it.value().get<int>();
                }
            }
            g_chunks.push_back(std::move(c));
        }
    } catch (...) { /* 损坏就当空 */ }
}

void saveToDisk() {
    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(g_indexPath()).parent_path(), ec);
    nlohmann::json arr = nlohmann::json::array();
    for (auto& c : g_chunks) {
        nlohmann::json tf = nlohmann::json::object();
        for (auto& [k, v] : c.tf) tf[k] = v;
        arr.push_back({{"source", c.source}, {"snippet", c.snippet}, {"tf", tf}});
    }
    std::ofstream f(g_indexPath(), std::ios::trunc);
    f << arr.dump();
}

}  // namespace

void importText(const std::string& source, const std::string& text) {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_chunks.empty()) loadFromDisk();
    // 按 ~500 字一段分块
    const size_t kChunkSize = 500;
    for (size_t i = 0; i < text.size(); i += kChunkSize) {
        size_t end = std::min(text.size(), i + kChunkSize);
        std::string sub = text.substr(i, end - i);
        Chunk c;
        c.source = source + "#" + std::to_string(i / kChunkSize);
        c.snippet = sub.substr(0, std::min<size_t>(sub.size(), 120));
        c.tf = computeTf(sub);
        g_chunks.push_back(std::move(c));
    }
    saveToDisk();
}

std::vector<Hit> search(const std::string& query, int topK) {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_chunks.empty()) loadFromDisk();
    auto qtf = computeTf(query);
    std::vector<Hit> hits;
    for (auto& c : g_chunks) {
        double score = 0;
        for (auto& [w, cnt] : qtf) {
            auto it = c.tf.find(w);
            if (it != c.tf.end()) score += (double)cnt * it->second;
        }
        if (score > 0) {
            Hit h;
            h.source = c.source;
            h.snippet = c.snippet;
            h.score = score;
            hits.push_back(std::move(h));
        }
    }
    std::sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b) { return a.score > b.score; });
    if ((int)hits.size() > topK) hits.resize(topK);
    return hits;
}

nlohmann::json stats() {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_chunks.empty()) loadFromDisk();
    return {
        {"chunks", (int)g_chunks.size()},
        {"index", g_indexPath()}
    };
}

}  // namespace zhinai::vector
