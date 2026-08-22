// main.cpp - 织奈编辑器 Windows 入口
// 流程:
//   1) 解析 EXE 同目录的 web/
//   2) 启本地 HTTP server (cpp-httplib)
//   3) 把 server 逻辑通过 webview bind 暴露给前端 (异步 RPC)
//   4) WebView2 加载 http://127.0.0.1:PORT/
//   5) 用户关窗口 -> 停 server -> 退出

// 顺序: winsock2 必须在 windows.h 之前, 否则 ws2tcpip.h 缺 IP_MSFILTER 等
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mstcpip.h>
#include <windows.h>

#include "platform.h"
#include "http_server.h"
#include "webview_app.h"
#include "db.h"
#include "llm.h"
#include "config.h"
#include "skills.h"
#include "vector_store.h"

#include <httplib.h>
#include <nlohmann/json.hpp>
#include <csignal>
#include <iostream>
#include <string>

namespace {

zhinai::http::Server g_server;
std::atomic<bool> g_shuttingDown{false};

void installSignalHandlers() {
    auto handler = +[](int sig) {
        if (g_shuttingDown.exchange(true)) return;
        zhinai::platform::log("INFO", "signal " + std::to_string(sig) + ", shutting down");
        zhinai::http::stop(g_server);
        std::_Exit(0);
    };
    std::signal(SIGINT, handler);
    std::signal(SIGTERM, handler);
}

// 前端 -> C++ 的 RPC:
//   前端发: {"method":"books.list", "params":{...}, "id":"..."}
//   C++ 回: {"id":"...", "ok":true, "data":...} 或 {"id":"...", "ok":false, "error":"..."}
//
// 我们把 method + params 重新 HTTP POST 到本地 server 的 /api/_native/<method> 路径,
// 然后把 server 的响应透传回去. 这样业务逻辑全在 http_server.cpp, 避免重复.
std::string dispatch(const std::string& reqJson) {
    using nlohmann::json;
    json req;
    try {
        req = json::parse(reqJson);
    } catch (const std::exception& e) {
        return json{{"ok", false}, {"error", std::string("bad json: ") + e.what()}}.dump();
    }
    std::string method = req.value("method", "");
    json params = req.value("params", json::object());
    std::string id = req.value("id", "");

    if (method.empty()) {
        return json{{"id", id}, {"ok", false}, {"error", "method missing"}}.dump();
    }

    // 调本地 server
    auto* srv = reinterpret_cast<httplib::Server*>(g_server.impl);
    if (!srv) return json{{"id", id}, {"ok", false}, {"error", "server down"}}.dump();

    // REST 风格: GET 查 / POST 改 / DELETE 删
    // method 形式: <entity>.<action>,  例如 books.list, books.create, chapter.update
    auto dot = method.find('.');
    std::string entity = (dot == std::string::npos) ? method : method.substr(0, dot);
    std::string action = (dot == std::string::npos) ? "" : method.substr(dot + 1);

    // 简单分发
    std::string verb = "GET";
    std::string path;
    std::string body;

    if (entity == "books" && action == "list")          { verb = "GET"; path = "/api/books"; }
    else if (entity == "books" && action == "create")    { verb = "POST"; path = "/api/books"; body = params.dump(); }
    else if (entity == "books" && action == "update")    {
        verb = "PUT"; path = "/api/books/" + params.value("id", std::string("0"));
        body = json{{"title", params.value("title", "")}, {"author", params.value("author", "")}, {"summary", params.value("summary", "")}}.dump();
    }
    else if (entity == "books" && action == "delete")    { verb = "DELETE"; path = "/api/books/" + params.value("id", std::string("0")); }
    else if (entity == "chapters" && action == "list")   { verb = "GET"; path = "/api/books/" + params.value("bookId", std::string("0")) + "/chapters"; }
    else if (entity == "chapters" && action == "create") {
        verb = "POST"; path = "/api/books/" + params.value("bookId", std::string("0")) + "/chapters";
        body = json{{"title", params.value("title", "")}, {"orderIndex", params.value("orderIndex", 0)}}.dump();
    }
    else if (entity == "chapters" && action == "saveContent") {
        verb = "PUT"; path = "/api/chapters/" + params.value("id", std::string("0")) + "/content";
        body = json{{"content", params.value("content", "")}}.dump();
    }
    else if (entity == "chapters" && action == "rename") {
        verb = "PUT"; path = "/api/chapters/" + params.value("id", std::string("0")) + "/title";
        body = json{{"title", params.value("title", "")}}.dump();
    }
    else if (entity == "chapters" && action == "delete") { verb = "DELETE"; path = "/api/chapters/" + params.value("id", std::string("0")); }
    else if (entity == "lore" && action == "list")       { verb = "GET"; path = "/api/lore"; }
    else if (entity == "lore" && action == "create")     { verb = "POST"; path = "/api/lore"; body = params.dump(); }
    else if (entity == "lore" && action == "update")     { verb = "PUT"; path = "/api/lore/" + params.value("id", std::string("0")); body = params.dump(); }
    else if (entity == "lore" && action == "delete")     { verb = "DELETE"; path = "/api/lore/" + params.value("id", std::string("0")); }
    else if (entity == "agents" && action == "list")     { verb = "GET"; path = "/api/agents"; }
    else if (entity == "agents" && action == "save")     { verb = "POST"; path = "/api/agents"; body = params.dump(); }
    else if (entity == "agents" && action == "delete")   { verb = "DELETE"; path = "/api/agents/" + params.value("id", std::string("0")); }
    else if (entity == "conversations" && action == "list") { verb = "GET"; path = "/api/conversations"; }
    else if (entity == "conversations" && action == "create") { verb = "POST"; path = "/api/conversations"; body = params.dump(); }
    else if (entity == "conversations" && action == "delete") { verb = "DELETE"; path = "/api/conversations/" + params.value("id", std::string("0")); }
    else if (entity == "conversations" && action == "messages") { verb = "GET"; path = "/api/conversations/" + params.value("id", std::string("0")) + "/messages"; }
    else if (entity == "conversations" && action == "appendMessage") {
        verb = "POST"; path = "/api/conversations/" + params.value("convId", std::string("0")) + "/messages";
        body = json{{"role", params.value("role", "user")}, {"content", params.value("content", "")}}.dump();
    }
    else if (entity == "llm" && action == "chat") {
        verb = "POST"; path = "/api/llm/chat"; body = params.dump();
    }
    else if (entity == "llm" && action == "test") {
        verb = "POST"; path = "/api/llm/test"; body = params.dump();
    }
    else if (entity == "skills" && action == "list")     { verb = "GET"; path = "/api/skills"; }
    else if (entity == "skills" && action == "read")     {
        verb = "GET"; path = "/api/skills/" + params.value("name", std::string(""));
    }
    else if (entity == "vectors" && action == "import")  { verb = "POST"; path = "/api/vectors/import"; body = params.dump(); }
    else if (entity == "vectors" && action == "search")  { verb = "POST"; path = "/api/vectors/search"; body = params.dump(); }
    else if (entity == "vectors" && action == "stats")   { verb = "GET"; path = "/api/vectors/stats"; }
    else if (entity == "config" && action == "get")      { verb = "GET"; path = "/api/config"; }
    else if (entity == "config" && action == "set")      { verb = "PUT"; path = "/api/config"; body = params.dump(); }
    else if (entity == "system" && action == "openDataDir") {
        // 调外部进程打开数据目录
        std::string cmd = "explorer.exe \"" + zhinai::platform::dataDir().string() + "\"";
        system(cmd.c_str());
        return json{{"id", id}, {"ok", true}, {"data", {{"path", zhinai::platform::dataDir().string()}}}}.dump();
    }
    else {
        return json{{"id", id}, {"ok", false}, {"error", "unknown method: " + method}}.dump();
    }

    httplib::Client cli("http://127.0.0.1:" + std::to_string(g_server.port));
    cli.set_connection_timeout(0, 200000);  // 200 ms
    cli.set_read_timeout(60, 0);

    httplib::Result r;
    if (verb == "GET")         r = cli.Get(path);
    else if (verb == "POST")   r = cli.Post(path, body, "application/json");
    else if (verb == "PUT")    r = cli.Put(path, body, "application/json");
    else if (verb == "DELETE") r = cli.Delete(path);

    if (!r) {
        return json{{"id", id}, {"ok", false}, {"error", "native call failed"}}.dump();
    }
    json data;
    try { data = json::parse(r->body); } catch (...) { data = r->body; }
    return json{{"id", id}, {"ok", r->status >= 200 && r->status < 300}, {"status", r->status}, {"data", data}}.dump();
}

}  // namespace

int WINAPI wWinMain(HINSTANCE /*hInst*/, HINSTANCE /*hPrev*/, wchar_t* /*cmd*/, int /*show*/) {
    installSignalHandlers();
    zhinai::platform::log("INFO", "starting " + std::string(zhinai::platform::kAppTitle()));

    // 1) 初始化 DB
    if (!zhinai::db::init()) {
        zhinai::platform::log("WARN", "db init failed, running with stub (data will not persist)");
    }

    // 2) 找 web/ 目录: 优先 EXE 同目录, 其次源码目录
    std::filesystem::path webDir = zhinai::platform::exeDir() / "web";
    if (!std::filesystem::exists(webDir / "index.html")) {
        // 开发模式: 源码目录
        webDir = "E:/zhinai-novel-editor/win/web";
        zhinai::platform::log("INFO", "web/ not next to exe, using source: " + webDir.string());
    }

    // 3) 启 HTTP server
    int port = 0;
    if (!zhinai::http::start(g_server, webDir.string(), port)) {
        std::wcerr << L"failed to start http server\n";
        return 1;
    }
    zhinai::platform::log("INFO", "server on port " + std::to_string(port));

    // 4) 跑 webview
    std::string url = "http://127.0.0.1:" + std::to_string(port) + "/";
    int rc = zhinai::webview_app::run(url, zhinai::platform::kAppTitle(), dispatch);

    // 5) 清理
    zhinai::http::stop(g_server);
    zhinai::db::shutdown();
    return rc;
}
