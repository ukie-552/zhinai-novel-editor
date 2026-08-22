// llm.h - OpenAI 兼容 LLM 客户端, 对应原 macos/LLM.swift
// 使用 WinHTTP, 不依赖 libcurl.
#pragma once
#include <functional>
#include <string>
#include <vector>

namespace zhinai::llm {

struct Message {
    std::string role;     // system / user / assistant
    std::string content;
};

struct Config {
    std::string baseURL;   // 例如 https://api.openai.com/v1
    std::string apiKey;
    std::string model;     // 例如 gpt-4o-mini
    int timeoutSec = 60;
};

struct Request {
    Config cfg;
    std::vector<Message> messages;
    double temperature = 0.7;
    int maxTokens = 0;  // 0 = 不指定
};

struct Response {
    bool ok = false;
    int httpStatus = 0;
    std::string content;
    std::string error;
};

// 同步请求
Response chat(const Request& req);

// 流式请求: 每次吐一段增量文本
using StreamCallback = std::function<bool(const std::string& delta)>;
void chatStream(const Request& req, StreamCallback onDelta, std::string& outError);

}  // namespace zhinai::llm
