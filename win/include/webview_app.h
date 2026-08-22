// webview_app.h - WebView2 封装, 用 webview/webview.h 单头文件
// 对应原 macOS 的 WebView.swift + MainApp.swift
#pragma once
#include <functional>
#include <string>

namespace zhinai::webview_app {

using BoundCallback = std::function<std::string(const std::string&)>;

// 阻塞运行, 直到用户关闭窗口.
// url: 本地 HTTP server 地址, 例如 http://127.0.0.1:8090/
// title: 窗口标题
// onFrontendCall: 前端通过 window.chrome.webview.postMessage 发来的请求, 返回 JSON 字符串.
int run(const std::string& url, const std::string& title, BoundCallback onFrontendCall);

}  // namespace zhinai::webview_app
