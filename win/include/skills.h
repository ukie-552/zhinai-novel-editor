// skills.h - 本地 Markdown 技能管理, 对应原 macos/Skills.swift
// 技能是 %APPDATA%/ZhinaiNovelEditor/skills/<name>/SKILL.md
#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace zhinai::skills {

struct Skill {
    std::string name;
    std::string path;
    std::string summary;
    std::string body;       // frontmatter 之后的正文
};

std::vector<Skill> list();
std::string read(const std::string& name);  // 返回 SKILL.md 全文
nlohmann::json listAsJson();

// 保存 Markdown 技能 (创建或覆盖). 返回是否成功.
bool save(const std::string& name, const std::string& desc, const std::string& category,
          const std::string& icon, bool needsText, int chapters, const std::string& markdown);

// 删除整个技能目录.
bool remove(const std::string& name);

}  // namespace zhinai::skills
