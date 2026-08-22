// webview_app.cpp - 用 webview/webview.h 包 WebView2
// 前端通过 window.chrome.webview.postMessage(JSON.stringify({type, payload})) 发消息,
// C++ 调 onFrontendCall(JSON.stringify(payload)) -> 返回 JSON 字符串 -> resolve 给前端.
#include "webview_app.h"
#include "platform.h"
#include <atomic>
#include <mutex>
#include <string>
// webview.h 末尾的 C API 实现带函数体, 多 TU include 会重复定义.
// 把它变 static 让各 TU 独立 (static 函数不参与外部链接).
#define WEBVIEW_API static
#include <webview/webview.h>

namespace zhinai::webview_app {

int run(const std::string& url, const std::string& title, BoundCallback onFrontendCall) {
    try {
        webview::webview w(true, nullptr);  // debug=true, no custom user_data
        w.set_title(title);
        w.set_size(1280, 820, WEBVIEW_HINT_NONE);

        // 同步 binding: 前端调 window.__nativeCall(jsonStr) -> 拿 string 返回值
        // 必须在 navigate() 之前调, webview.h Windows 后端用
        // AddScriptToExecuteOnDocumentCreated 注入 JS, navigate 后再 bind 无效
        w.bind("__nativeCall",
               [onFrontendCall](const std::string& req) -> std::string {
                   if (!onFrontendCall) return R"({"error":"no handler"})";
                   return onFrontendCall(req);
               });

        w.navigate(url);

        w.run();
        return 0;
    } catch (const std::exception& e) {
        platform::log("ERROR", std::string("webview exception: ") + e.what());
        return 1;
    } catch (...) {
        platform::log("ERROR", "webview unknown exception");
        return 1;
    }
}

}  // namespace zhinai::webview_app
