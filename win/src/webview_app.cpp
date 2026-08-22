// webview_app.cpp - 用 webview/webview.h 包 WebView2
// 前端通过 window.chrome.webview.postMessage(JSON.stringify({type, payload})) 发消息,
// C++ 调 onFrontendCall(JSON.stringify(payload)) -> 返回 JSON 字符串 -> resolve 给前端.
#define WEBVIEW_HEADER <webview/webview.h>
#include "webview_app.h"
#include "platform.h"
#include <atomic>
#include <mutex>
#include <string>

// webview/webview.h 是单头文件
#define WEBVIEW_IMPLEMENTATION
#include WEBVIEW_HEADER

namespace zhinai::webview_app {

int run(const std::string& url, const std::string& title, BoundCallback onFrontendCall) {
    try {
        webview::webview w(true, nullptr);  // debug=true, no custom user_data
        w.set_title(title);
        w.set_size(1280, 820, WEBVIEW_HINT_NONE);
        w.set_url(url);

        // 前端异步消息处理: 解析 JSON, payload 用 JSON.stringify 后调 onFrontendCall,
        // 再把结果 resolve 回去.
        w.bind("__nativeCall",
               [onFrontendCall](const std::string& req) -> std::string {
                   if (!onFrontendCall) return R"({"error":"no handler"})";
                   return onFrontendCall(req);
               });

        w.run();
        return 0;
    } catch (const webview::exception& e) {
        platform::log("ERROR", std::string("webview exception: ") + e.what());
        return 1;
    }
}

}  // namespace zhinai::webview_app
