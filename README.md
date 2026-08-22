# 📚 织奈编辑器

织奈编辑器是一款 macOS 小说写作工具，用于管理作品、章节和设定资料，也可以连接常用模型协助写作。作品数据默认保存在本机喵～

## 下载与安装

从 [Releases](https://github.com/ukie-552/zhinai-novel-editor/releases) 下载最新的 Intel DMG，打开后将「织奈编辑器」拖入「Applications」。当前版本面向 Intel Mac，最低系统版本为 macOS 13。

当前公开版本未经过 Apple 公证。首次运行时，请在 Finder 中右键点击应用，选择「打开」，再确认一次。请只从本仓库下载，并可使用 Release 中提供的 SHA-256 文件核对安装包。

## 功能

- 管理多部作品、章节正文和大纲。
- 保存人物、地点、世界观和其他设定资料。
- 连接模型进行对话、续写、润色和内容检查。
- 创建不同用途的 Agent，并为 Agent 固定一个技能。
- 管理本地 Markdown 技能，由 Agent 根据任务按需读取。
- 支持全文搜索、多个对话和本地向量资料库。

## 使用

1. 打开 `build/织奈编辑器.app`（可拖入「应用程序」）
2. ⚙️ 设置 → 选模型商、填 API Key、模型 → 测试连接
3. 在 Agent 编辑页配置提示词、模型、工具权限和一个固定技能
4. 侧栏建作品 → 编辑区写大纲 → 设定库建人物/世界观（填触发关键词）
5. 编辑区「AI 操作」直接续写/润色当前章节；右键章节排序；⌘N/⌘⇧N/⌘S/⌘⏎/⌘,

## 数据

`~/Library/Application Support/ZhinaiNovelEditor/`（`novels.db` + `config.json` + `agents.json`，全部本机）。首次启动会自动迁移旧版数据。

## 构建、打包与自检

```bash
./macos/build_app.sh        # 需要 Xcode 命令行工具
./macos/build_dmg.sh 1.0.0  # 生成 Intel DMG 与 SHA-256 文件
# 无头全链路自检（19 项）：
swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 \
  macos/Models.swift macos/DB.swift macos/LLM.swift macos/Skills.swift macos/SelfTest.swift \
  -o /tmp/selftest -lsqlite3 && node tools/mock_llm.js & \
  AINOVEL_DATA_DIR=/tmp/t AINOVEL_TEST_BASEURL=http://127.0.0.1:19001/v1 /tmp/selftest
```

## 后续

向量库保存在 `~/Library/Application Support/ZhinaiNovelEditor/vectors.db`。侧边栏「向量库」可导入 TXT，并对章节正文分块建立本地向量索引。
