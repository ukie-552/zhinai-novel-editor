// skills.cpp
#include "skills.h"
#include "platform.h"
#include <filesystem>
#include <fstream>
#include <sstream>

namespace zhinai::skills {

static std::filesystem::path skillsRoot() {
    auto p = platform::dataDir() / "skills";
    std::error_code ec;
    std::filesystem::create_directories(p, ec);
    return p;
}

std::vector<Skill> list() {
    std::vector<Skill> out;
    auto root = skillsRoot();
    if (!std::filesystem::exists(root)) return out;
    for (auto& entry : std::filesystem::directory_iterator(root)) {
        if (!entry.is_directory()) continue;
        auto md = entry.path() / "SKILL.md";
        if (!std::filesystem::exists(md)) continue;
        Skill s;
        s.name = entry.path().filename().string();
        s.path = md.string();
        std::ifstream f(md);
        std::stringstream ss; ss << f.rdbuf();
        auto text = ss.str();
        // 第一行非空内容作为 summary
        std::stringstream lineStream(text);
        std::string line;
        while (std::getline(lineStream, line)) {
            if (line.empty()) continue;
            // 去掉 markdown 标题前缀
            if (line[0] == '#') {
                size_t i = 0;
                while (i < line.size() && (line[i] == '#' || line[i] == ' ')) ++i;
                s.summary = line.substr(i);
            } else {
                s.summary = line;
            }
            break;
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

}  // namespace zhinai::skills
