// http_server.h - 嵌入式 HTTP server, 对应原 Server.swift + WebView 的本地 server
// 用 cpp-httplib 单头文件, 监听 127.0.0.1 上一个空闲端口.
#pragma once
#include <atomic>
#include <functional>
#include <string>
#include <thread>

namespace zhinai::http {

struct Server {
    void* impl = nullptr;  // httplib::Server*, 实现藏在 cpp 里
    std::thread th;
    std::atomic<bool> running{false};
    int port = 0;
};

// 在 127.0.0.1 上找一个空闲端口, 启动 server, 绑定 REST API.
// webDir 是静态资源目录的绝对路径, 用于 serve / 和 /web/*.
// 端口号会写回 outPort.
bool start(Server& s, const std::string& webDir, int& outPort);

// 优雅关闭
void stop(Server& s);

}  // namespace zhinai::http
