// skills_catalog.cpp - 内置技能 (跟 macOS Skills.swift 的 ALL_SKILLS 对齐)
#include "skills_catalog.h"

namespace zhinai::skills_catalog {

const std::vector<Skill>& builtIn() {
    static const std::vector<Skill> kBuiltIn = {
        // ── 创作 ──
        { "chat", "普通对话", "💬", "只使用当前 Agent, 不附加任务指令",
          "write", "", false, 1, true, "" },

        { "continue", "续写正文", "✍", "紧接最新章节继续写作",
          "write",
          "任务: 紧接前文最后一章续写新的章节正文 (1000-2500 字). 要求: 人物口吻与文风和前文一致; 推进剧情或深化冲突; 结尾留悬念. 直接输出正文, 不要输出解释.",
          false, 2, true, "" },

        { "outline", "生成大纲", "🗺", "生成分章故事大纲",
          "write",
          "任务: 为当前作品生成完整的分章故事大纲. 要求: 先给出核心创意 (一句话) 与主线/支线概述, 再分章列出每章要点 (章节号+标题+事件与钩子); 世界观, 人物, 已有剧情必须严格符合参考设定; 使用 Markdown 输出.",
          false, 0, true, "" },

        { "polish", "润色改写", "✨", "润色选中文本或最新章节",
          "write",
          "任务: 对给定文本进行润色改写. 要求: 保留原意与情节推进, 不得擅自增删关键剧情; 提升文笔, 节奏与可读性, 修正语病与逻辑瑕疵; 先输出润色后的全文, 再附简短「修改说明」.",
          true, 0, true, "" },

        { "scene", "场景创作", "🎬", "为当前剧情创作一段场景描写",
          "write",
          "任务: 围绕用户指定的剧情节点/场景创作一段场景正文 (600-1500 字). 要求: 五感描写, 氛围营造, 人物动作与对话自然; 与设定和前文一致; 直接输出正文.",
          false, 1, true, "" },

        // ── 设定 ──
        { "character", "人物设计", "👤", "生成完整人物卡",
          "world",
          "任务: 设计一个小说人物卡. 要求: 包含姓名, 年龄, 外貌, 性格, 背景故事, 动机与目标, 弱点, 与其他角色的关系, 成长弧光; 人物贴合作品世界观; 使用 Markdown 输出.",
          false, 0, true, "" },

        { "worldbuilding", "世界观设定", "🌏", "完善力量体系, 地理, 势力, 历史",
          "world",
          "任务: 完善作品的世界观设定. 要求: 围绕用户提出的方向输出核心规则, 力量体系/科技, 地理, 势力分布, 历史脉络, 日常细节, 禁忌与冲突点; 逻辑自洽且与已有参考设定一致; 使用 Markdown 输出.",
          false, 0, true, "" },

        { "location", "地点设计", "📍", "设计场景地点: 地理, 氛围, 功能",
          "world",
          "任务: 设计一个小说地点/场景设定. 要求: 包含地理位置, 外观与布局, 氛围与色调, 功能与秘密, 适合发生的情节类型, 注意事项 (与世界观一致的约束); 使用 Markdown 输出.",
          false, 0, true, "" },

        { "faction", "势力设计", "🏳", "设计组织势力: 结构, 目标, 关系网",
          "world",
          "任务: 设计一个小说势力/组织设定. 要求: 包含宗旨与目标, 组织结构与关键人物, 资源与地盘, 与其他势力的关系, 内部矛盾, 对主角的影响; 与已有设定一致; 使用 Markdown 输出.",
          false, 0, true, "" },

        { "item", "物品道具设计", "📦", "设计神器/物品: 来历, 能力, 代价",
          "world",
          "任务: 设计一个小说物品/道具设定. 要求: 包含外观, 来历与传说, 能力与规则 (明确边界), 使用代价或限制, 在剧情中的作用; 与世界观力量体系自洽; 使用 Markdown 输出.",
          false, 0, true, "" },

        // ── 分析 ──
        { "consistency", "一致性检查", "✅", "检查前文与设定的矛盾",
          "analyze",
          "任务: 检查前文与参考设定之间的人物, 时间线, 能力, 地点, 细节一致性. 要求: 逐条列出矛盾点 (引用原文位置) 并给出修改建议; 无矛盾时说明「未发现明显矛盾」; 使用 Markdown 输出.",
          false, 2, true, "" },

        { "inspire", "灵感脑暴", "💡", "围绕主题生成 5-10 个剧情创意",
          "analyze",
          "任务: 围绕用户给出的主题进行头脑风暴. 要求: 给出 5-10 个新颖, 可落地的剧情灵感/转折/设定创意, 每个 2-3 句话说明价值, 并标注最推荐的一个; 使用 Markdown 输出.",
          false, 0, true, "" },
    };
    return kBuiltIn;
}

std::string composeSystemPrompt(const Skill& s, const std::string& loreContext) {
    std::string sys = s.system;
    if (!loreContext.empty()) {
        if (!sys.empty()) sys += "\n\n";
        sys += "参考设定:\n" + loreContext;
    }
    return sys;
}

const Skill* findById(const std::string& id, const std::vector<Skill>& userSkills) {
    for (const auto& s : builtIn()) {
        if (s.id == id) return &s;
    }
    for (const auto& s : userSkills) {
        if (s.id == id) return &s;
    }
    return nullptr;
}

}  // namespace zhinai::skills_catalog
