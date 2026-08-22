// config.h - 配置持久化 (config.json + agents.json), 对应原 ~/Library/.../config.json
#pragma once
#include <nlohmann/json.hpp>
#include <string>

namespace zhinai::config {

// 加载 / 保存 config.json (LLM 模型商, API key 等)
nlohmann::json loadConfig();
void saveConfig(const nlohmann::json& j);

// 加载 / 保存 agents.json
nlohmann::json loadAgents();
void saveAgents(const nlohmann::json& j);

}  // namespace zhinai::config
