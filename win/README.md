# 织奈编辑器 · Windows 移植版

C++ + WebView2 的 Windows 桌面版，对应原 [macOS 版 (SwiftUI + WebKit)](../macos/)。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  织奈编辑器.exe                                             │
│  ┌──────────────────────┐   ┌──────────────────────────┐   │
│  │ WebView2 (Edge 内核)  │   │ cpp-httplib (本机 server) │   │
│  │ 加载 127.0.0.1:PORT   │◄──┤ 监听 127.0.0.1           │   │
│  │ web/index.html        │   │ REST API + 静态资源       │   │
│  └──────────────────────┘   └──────────────────────────┘   │
│            │ postMessage              ▲ fetch               │
│            ▼                          │                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 业务模块: db / llm / skills / vector_store / config    │  │
│  └──────────────────────────────────────────────────────┘  │
│            │                                               │
│            ▼                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ SQLite  (novels.db)    WinHTTP  (LLM HTTP)            │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

前端是单页应用 (HTML + TailwindCSS CDN + 原生 JS), 通过:
- **WebView2 桥**: `window.chrome.webview.postMessage(...)` → C++ `dispatch()` → 本地 server
- **REST 直连**: 浏览器调试时直接 `fetch('/api/...')` (同源)

## 编译

### 一次性环境

用 **管理员 PowerShell** 跑:

```powershell
# 1) MSVC Build Tools 2022 + C++ workload
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended"

# 2) cmake
winget install --id Kitware.CMake -e
```

### 拉单头文件依赖

启动 [VS 2022 Developer PowerShell] 或 [x64 Native Tools Command Prompt for VS 2022] 后:

```powershell
cd win\scripts
.\fetch_deps.ps1
```

把以下单头文件拉到 `win/third_party/`:

- `cpp-httplib/httplib.h`  — [yhirose/cpp-httplib](https://github.com/yhirose/cpp-httplib) v0.15+
- `nlohmann/json.hpp`     — [nlohmann/json](https://github.com/nlohmann/json) v3.11+
- `webview/webview.h`     — [nicbarker/webview](https://github.com/nicbarker/webview) (Windows 后端用 WebView2)
- `sqlite/sqlite3.c` + `sqlite3.h` — [SQLite Amalgamation](https://www.sqlite.org/amalgamation.html) (推荐 3.46+)

### 编译 + 打包

```powershell
cd win
.\build.ps1
# 产物: win\build\Release\织奈编辑器.exe
# 同时把 web/ 复制到 EXE 同目录
```

直接双击 EXE 即可运行, 无需额外 DLL (WebView2 Runtime Win10 1803+ 自带).

## 数据

- 作品 / 章节 / 设定 / Agent / 对话: `%APPDATA%\ZhinaiNovelEditor\novels.db`
- LLM 配置: `%APPDATA%\ZhinaiNovelEditor\config.json`
- 技能 (Markdown): `%APPDATA%\ZhinaiNovelEditor\skills\<name>\SKILL.md`
- 向量索引: `%APPDATA%\ZhinaiNovelEditor\vectors\index.json`

## 已实现

- [x] 作品 / 章节 CRUD + 拖拽排序
- [x] 章节编辑器 + 自动保存
- [x] 设定库 (人物/地点/世界观/物品/其他) + 关键词触发
- [x] LLM 对话 (OpenAI 兼容协议, 同步)
- [x] AI 续写 (自动注入命中设定)
- [x] 多对话 + 多 Agent
- [x] 本地 Markdown 技能列表
- [x] 本地向量库 (词频倒排, 后续可换 embedding)
- [x] 设置 / 测试连接

## 后续

- [ ] SSE 真流式 (现在 /api/llm/chat/stream 是一次返回)
- [ ] Tool calling (Function call) + 工具权限
- [ ] 全文搜索 (SQLite FTS5)
- [ ] Embedding 接入 (OpenAI text-embedding-3 / 本地 bge-small)
- [ ] Markdown 实时预览
- [ ] 导出 EPUB / DOCX
- [ ] 多窗口 / 多标签

## 调试

- 直接用浏览器打开 `win/web/index.html` — 前端会 fallback 到 fetch 直连 server, 但 C++ 桥不存在, `__nativeCall` 调用会失败. 用于调 UI.
- 启动后看 `%APPDATA%\ZhinaiNovelEditor\logs\app.log`.
- WebView2 DevTools: `w.set_title(title)` 上右键 → Inspect, 或在 `webview/webview.h` 里 `webview w(true, nullptr)` 第二参数开调试.
