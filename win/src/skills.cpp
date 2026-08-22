// skills.cpp - 本地 Markdown 技能管理, 跟 macOS SkillStore 对齐
// .md 文件 frontmatter YAML: id / name / description / category / icon / needs_text / chapters
#include "skills.h"
#include "platform.h"
#include <filesystem>
#include <fstream>
#include <sstream>
#include <map>
#include <regex>
#include <set>

namespace zhinai::skills {

namespace fs = std::filesystem;

static fs::path skillsRoot() {
    auto p = platform::dataDir() / "skills";
    std::error_code ec;
    fs::create_directories(p, ec);
    return p;
}

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

static std::map<std::string, std::string> parseFrontmatter(const std::string& raw, std::string& body) {
    std::map<std::string, std::string> meta;
    body = raw;
    if (raw.compare(0, 4, "---\n") != 0) return meta;
    auto end = raw.find("\n---", 4);
    if (end == std::string::npos) return meta;
    std::string front = raw.substr(4, end - 4);
    body = trim(raw.substr(end + 4));
    std::stringstream ls(front);
    std::string line;
    while (std::getline(ls, line)) {
        auto c = line.find(':');
        if (c == std::string::npos) continue;
        std::string k = trim(line.substr(0, c));
        std::string v = trim(line.substr(c + 1));
        // 去引号
        if (v.size() >= 2 && (v.front() == '"' || v.front() == '\'') && v.back() == v.front()) {
            v = v.substr(1, v.size() - 2);
        }
        meta[k] = v;
    }
    return meta;
}

static std::string buildFrontmatter(const std::map<std::string, std::string>& meta) {
    std::string out = "---\n";
    static const std::vector<std::string> order = {
        "id", "name", "description", "category", "icon", "needs_text", "chapters"
    };
    std::set<std::string> written;
    for (const auto& k : order) {
        auto it = meta.find(k);
        if (it == meta.end()) continue;
        out += k + ": " + it->second + "\n";
        written.insert(k);
    }
    for (const auto& [k, v] : meta) {
        if (written.count(k)) continue;
        out += k + ": " + v + "\n";
    }
    out += "---\n\n";
    return out;
}

std::vector<Skill> list() {
    std::vector<Skill> out;
    auto root = skillsRoot();
    if (!fs::exists(root)) return out;
    for (auto& entry : fs::directory_iterator(root)) {
        if (!entry.is_directory()) continue;
        auto md = entry.path() / "SKILL.md";
        if (!fs::exists(md)) continue;
        Skill s;
        s.name = entry.path().filename().string();
        s.path = md.string();
        std::ifstream f(md);
        std::stringstream ss; ss << f.rdbuf();
        auto text = ss.str();
        std::string body;
        auto meta = parseFrontmatter(text, body);
        s.summary = meta.count("description") ? meta["description"] : "";
        s.body = body;
        if (!s.summary.empty()) s.summary = trim(s.summary);
        // summary: 用第一行作为简介
        if (s.summary.empty()) {
            std::stringstream lineStream(body);
            std::string line;
            while (std::getline(lineStream, line)) {
                if (line.empty()) continue;
                if (line[0] == '#') {
                    size_t i = 0;
                    while (i < line.size() && (line[i] == '#' || line[i] == ' ')) ++i;
                    s.summary = line.substr(i);
                } else {
                    s.summary = line;
                }
                break;
            }
        }
        out.push_back(std::move(s));
    }
    return out;
}

std::string read(const std::string& name) {
    auto p = skillsRoot() / name / "SKILL.md";
    std::ifstream f(p);
    if (!f) return {};
    std::stringstream ss; ss << f.rdbuf();
    return ss.str();
}

nlohmann::json listAsJson() {
    auto ls = list();
    nlohmann::json arr = nlohmann::json::array();
    for (auto& s : ls) {
        arr.push_back({{"name", s.name}, {"path", s.path}, {"summary", s.summary}});
    }
    return arr;
}

bool save(const std::string& name, const std::string& desc, const std::string& category,
          const std::string& icon, bool needsText, int chapters, const std::string& markdown) {
    auto dir = skillsRoot() / name;
    std::error_code ec;
    fs::create_directories(dir, ec);
    std::map<std::string, std::string> meta = {
        {"id", name},
        {"name", name},
        {"description", desc},
        {"category", category},
        {"icon", icon},
        {"needs_text", needsText ? "true" : "false"},
        {"chapters", std::to_string(chapters)},
    };
    auto text = buildFrontmatter(meta) + markdown;
    std::ofstream f(dir / "SKILL.md", std::ios::trunc | std::ios::binary);
    if (!f) return false;
    f << text;
    return f.good();
}

bool remove(const std::string& name) {
    auto dir = skillsRoot() / name;
    if (!fs::exists(dir)) return false;
    std::error_code ec;
    fs::remove_all(dir, ec);
    return !ec;
}

}  // namespace zhinai::skills
