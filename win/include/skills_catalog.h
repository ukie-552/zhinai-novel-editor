// skills_catalog.h - 内置技能 (跟 macOS Skills.swift 的 ALL_SKILLS 对齐)
#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace zhinai::skills_catalog {

struct Skill {
    std::string id;
    std::string name;
    std::string icon;        // 简易字符串 (sparkles, square.and.pencil...), 前端用 unicode emoji 替代
    std::string desc;
    std::string category;    // write / world / analyze
    std::string system;      // 任务指令, 拼到 LLM 的 system prompt
    bool needsText = false;  // 是否需要选中文本/章节内容
    int chapters = 0;        // 注入前文章节数 (0-10)
    bool builtIn = true;     // 内置 vs Markdown 用户技能
    std::string filePath;    // Markdown 技能的文件路径 (内置为空)
};

// 跟 macOS 的 ALL_SKILLS 一一对应
const std::vector<Skill>& builtIn();

// 拼装最终 system prompt: skill.system  +  (skill.chapters > 0 ? "\n\n参考前文最近 N 章." : "")
std::string composeSystemPrompt(const Skill& s, const std::string& loreContext);

// 按 id 找 skill (在 builtIn + 用户 markdown 里查)
const Skill* findById(const std::string& id, const std::vector<Skill>& userSkills);

}  // namespace zhinai::skills_catalog
