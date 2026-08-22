# 织奈书籍格式（v2）

织奈编辑器使用 UTF-8 编码的 `.zhinovel.json` 交换完整书籍项目。v2 借鉴 InkOS 的分层原则：书籍身份、创作配置、长期控制文档、正文和设定分别存放，避免把所有信息混成一段提示词。

## 顶层结构

```json
{
  "format": "zhinai-novel",
  "version": 2,
  "exportedAt": "2026-08-22T00:00:00Z",
  "book": {
    "title": "雾城来信",
    "author": "林岚",
    "description": "一部发生在雾城的悬疑小说。",
    "outline": "兼容 v1 的卷纲字段"
  },
  "config": {
    "subtitle": "十年前的回声",
    "authors": ["林岚"],
    "penName": "",
    "genre": "悬疑",
    "tags": ["都市", "调查"],
    "platform": "other",
    "status": "outlining",
    "language": "zh",
    "targetChapters": 80,
    "chapterWordCount": 3000,
    "reviewMode": "manual",
    "styleLibraryID": null,
    "styleStrength": 0.65
  },
  "story": {
    "authorIntent": "写一部以记忆可靠性为核心的悬疑故事。",
    "currentFocus": "接下来三章揭示旧报社与失踪案的联系，但不揭晓寄信人。",
    "storyFrame": "核心前提、主线冲突、世界底色与关键关系……",
    "volumeOutline": "第一卷：来信……",
    "bookRules": "不得使用超自然解释；主角不能凭空获得线索。"
  },
  "publishing": {
    "seriesName": "雾城档案",
    "seriesNumber": "1",
    "targetAudience": "成人",
    "contentRating": "16+",
    "isbn": "",
    "publisher": "",
    "publicationDate": "",
    "rights": "Copyright © 林岚",
    "source": ""
  },
  "chapters": [
    { "number": 1, "title": "没有寄件人的信", "content": "正文……" }
  ],
  "lore": [
    {
      "type": "character",
      "title": "林雾",
      "content": "二十四岁，旧报社记者。",
      "keywords": ["林雾", "记者"],
      "pinned": false
    }
  ]
}
```

## 分层含义

- `book`：用于书架显示与 v1 兼容的基本身份。
- `config`：写作运行参数。`status` 可为 `incubating`、`outlining`、`active`、`paused`、`completed`、`dropped`；`reviewMode` 可为 `manual` 或 `auto`。
- `config.styleLibraryID`：本机绑定的写法向量库 ID；交换到另一台设备后可重新选择。`styleStrength` 控制抽象写法画像的影响强度。
- `story.authorIntent`：长期作者意图。
- `story.currentFocus`：未来 1–3 章的当前焦点，其优先级高于卷纲。
- `story.storyFrame`：故事框架、世界底色、主线冲突与关键关系。
- `story.volumeOutline`：分卷及阶段性规划。
- `story.bookRules`：不可违反的硬规则、数值上限、禁用桥段和文风约束。
- `publishing`：可选出版元数据，不参与故事事实判断。
- `chapters`：按 `number` 排序的正文。
- `lore`：人物、地点、势力、物品、世界观等可触发的事实条目。

聊天记录、API Key、模型、Agent 与界面状态属于作者个人工作环境，不写入书籍文件。章节数和当前字数由正文实时计算，也不重复存储。

写法向量库的参考原文不会嵌入书籍交换文件。应用只向 AI 注入句长、段落、对话比例、叙事人称和标点张力等匿名化统计画像，并明确禁止复用参考原句、专名、设定与情节。

应用仍可导入 v1 文件。导入会生成新的内部 ID，不覆盖同名书籍。
