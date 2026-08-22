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
};

std::vector<Skill> list();
std::string read(const std::string& name);  // 返回 SKILL.md 全文
nlohmann::json listAsJson();

}  // namespace zhinai::skills
