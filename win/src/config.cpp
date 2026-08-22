// config.cpp
#include "config.h"
#include "platform.h"
#include <fstream>
#include <sstream>

namespace zhinai::config {

static nlohmann::json readJson(const std::filesystem::path& p) {
    std::ifstream f(p);
    if (!f) return nlohmann::json::object();
    try {
        return nlohmann::json::parse(f);
    } catch (...) {
        return nlohmann::json::object();
    }
}

static void writeJson(const std::filesystem::path& p, const nlohmann::json& j) {
    std::error_code ec;
    std::filesystem::create_directories(p.parent_path(), ec);
    std::ofstream f(p, std::ios::trunc);
    f << j.dump(2);
}

nlohmann::json loadConfig() { return readJson(platform::configPath()); }
void saveConfig(const nlohmann::json& j) { writeJson(platform::configPath(), j); }

nlohmann::json loadAgents() { return readJson(platform::agentsPath()); }
void saveAgents(const nlohmann::json& j) { writeJson(platform::agentsPath(), j); }

}  // namespace zhinai::config
