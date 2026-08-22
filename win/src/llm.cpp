// llm.cpp - 用 WinHTTP 调 OpenAI 兼容 LLM API
// 流式: 解析 SSE, 每次拿到一段 delta 调 callback.
#include "llm.h"
#include "platform.h"
#include <winhttp.h>
#include <windows.h>
#include <nlohmann/json.hpp>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>

#pragma comment(lib, "winhttp.lib")

namespace zhinai::llm {

namespace {

struct UrlParts {
    bool https = false;
    std::wstring host;
    int port = 0;
    std::wstring path;
};

bool parseUrl(const std::wstring& url, UrlParts& out) {
    // 形如 https://api.openai.com/v1/chat/completions
    const std::wstring h = L"https://";
    const std::wstring p = L"http://";
    size_t pos = std::wstring::npos;
    if (url.compare(0, h.size(), h) == 0) { out.https = true; pos = h.size(); }
    else if (url.compare(0, p.size(), p) == 0) { out.https = false; pos = p.size(); }
    else return false;
    auto slash = url.find(L'/', pos);
    std::wstring hp = (slash == std::wstring::npos) ? url.substr(pos) : url.substr(pos, slash - pos);
    auto colon = hp.find(L':');
    if (colon == std::wstring::npos) {
        out.host = hp;
        out.port = out.https ? 443 : 80;
    } else {
        out.host = hp.substr(0, colon);
        out.port = std::stoi(hp.substr(colon + 1));
    }
    out.path = (slash == std::wstring::npos) ? L"/" : url.substr(slash);
    return true;
}

std::wstring utf8ToWide(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
    return w;
}

std::string wideToUtf8(const std::wstring& w) {
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr);
    return s;
}

std::string buildRequestBody(const Request& req) {
    nlohmann::json j;
    j["model"] = req.cfg.model;
    nlohmann::json arr = nlohmann::json::array();
    for (auto& m : req.messages) {
        arr.push_back({{"role", m.role}, {"content", m.content}});
    }
    j["messages"] = arr;
    if (req.temperature > 0) j["temperature"] = req.temperature;
    if (req.maxTokens > 0) j["max_tokens"] = req.maxTokens;
    j["stream"] = false;
    return j.dump();
}

std::string buildRequestBodyStream(const Request& req) {
    auto s = buildRequestBody(req);
    // 把 "stream":false 换成 true
    auto pos = s.find("\"stream\":false");
    if (pos != std::string::npos) s.replace(pos, 13, "\"stream\":true");
    return s;
}

Response doRequest(const std::string& url, const std::string& body, const std::string& apiKey, int timeoutSec) {
    Response resp;
    HINTERNET hSession = WinHttpOpen(L"zhinai-novel-editor/1.0",
                                     WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                     WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) { resp.error = "WinHttpOpen failed"; return resp; }

    UrlParts u;
    std::wstring wurl = utf8ToWide(url);
    if (!parseUrl(wurl, u)) { resp.error = "bad url"; WinHttpCloseHandle(hSession); return resp; }

    DWORD access = u.https ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hConnect = WinHttpConnect(hSession, u.host.c_str(), (INTERNET_PORT)u.port, 0);
    if (!hConnect) { resp.error = "WinHttpConnect failed"; WinHttpCloseHandle(hSession); return resp; }

    DWORD flags = access;
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", u.path.c_str(), nullptr,
                                           WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) { resp.error = "WinHttpOpenRequest failed"; WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return resp; }

    std::wstring headers = L"Content-Type: application/json\r\n";
    std::wstring authHeader = L"Authorization: Bearer " + utf8ToWide(apiKey) + L"\r\n";
    headers += authHeader;
    headers += L"Accept: application/json\r\n";

    WinHttpAddRequestHeaders(hRequest, headers.c_str(), (DWORD)headers.size(), WINHTTP_ADDREQ_FLAG_ADD);

    BOOL ok = WinHttpSendRequest(hRequest,
                                 WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                 (LPVOID)body.data(), (DWORD)body.size(),
                                 (DWORD)body.size(), 0);
    if (!ok) {
        resp.error = "WinHttpSendRequest failed: " + std::to_string(GetLastError());
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return resp;
    }
    if (!WinHttpReceiveResponse(hRequest, nullptr)) {
        resp.error = "WinHttpReceiveResponse failed";
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return resp;
    }

    // 取状态码
    DWORD statusCode = 0; DWORD statusSize = sizeof(statusCode);
    WinHttpQueryHeaders(hRequest,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);
    resp.httpStatus = (int)statusCode;

    // timeout
    WinHttpSetTimeouts(hRequest, 0, 0, timeoutSec * 1000, timeoutSec * 1000);

    std::string buf;
    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &avail)) break;
        if (avail == 0) break;
        std::string chunk(avail, '\0');
        DWORD read = 0;
        if (!WinHttpReadData(hRequest, chunk.data(), avail, &read)) break;
        chunk.resize(read);
        buf += chunk;
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);

    if (statusCode < 200 || statusCode >= 300) {
        resp.error = "http " + std::to_string(statusCode) + ": " + buf;
        return resp;
    }
    try {
        auto j = nlohmann::json::parse(buf);
        resp.content = j.at("choices").at(0).at("message").at("content").get<std::string>();
        resp.ok = true;
    } catch (const std::exception& e) {
        resp.error = std::string("parse failed: ") + e.what() + " | body=" + buf.substr(0, 200);
    }
    return resp;
}

}  // namespace

Response chat(const Request& req) {
    if (req.cfg.baseURL.empty() || req.cfg.apiKey.empty() || req.cfg.model.empty()) {
        return {false, 0, "", "LLM config missing (baseURL/apiKey/model)"};
    }
    std::string url = req.cfg.baseURL;
    if (url.back() == '/') url.pop_back();
    url += "/chat/completions";
    auto body = buildRequestBody(req);
    return doRequest(url, body, req.cfg.apiKey, req.cfg.timeoutSec);
}

void chatStream(const Request& req, StreamCallback onDelta, std::string& outError) {
    outError.clear();
    if (req.cfg.baseURL.empty() || req.cfg.apiKey.empty() || req.cfg.model.empty()) {
        outError = "LLM config missing"; return;
    }
    std::string url = req.cfg.baseURL;
    if (url.back() == '/') url.pop_back();
    url += "/chat/completions";
    auto body = buildRequestBodyStream(req);

    UrlParts u;
    std::wstring wurl = utf8ToWide(url);
    if (!parseUrl(wurl, u)) { outError = "bad url"; return; }

    HINTERNET hSession = WinHttpOpen(L"zhinai-novel-editor/1.0",
                                     WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                     WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) { outError = "WinHttpOpen failed"; return; }
    DWORD access = u.https ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hConnect = WinHttpConnect(hSession, u.host.c_str(), (INTERNET_PORT)u.port, 0);
    if (!hConnect) { outError = "WinHttpConnect failed"; WinHttpCloseHandle(hSession); return; }
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"POST", u.path.c_str(), nullptr,
                                            WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, access);
    if (!hRequest) { outError = "WinHttpOpenRequest failed"; WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return; }

    std::wstring headers = L"Content-Type: application/json\r\n";
    headers += L"Authorization: Bearer " + utf8ToWide(req.cfg.apiKey) + L"\r\n";
    headers += L"Accept: text/event-stream\r\n";
    WinHttpAddRequestHeaders(hRequest, headers.c_str(), (DWORD)headers.size(), WINHTTP_ADDREQ_FLAG_ADD);
    WinHttpSetTimeouts(hRequest, 0, 0, req.cfg.timeoutSec * 1000, req.cfg.timeoutSec * 1000);

    if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            (LPVOID)body.data(), (DWORD)body.size(), (DWORD)body.size(), 0)) {
        outError = "send failed: " + std::to_string(GetLastError());
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return;
    }
    if (!WinHttpReceiveResponse(hRequest, nullptr)) {
        outError = "receive failed";
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return;
    }

    DWORD statusCode = 0; DWORD statusSize = sizeof(statusCode);
    WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);
    if (statusCode < 200 || statusCode >= 300) {
        outError = "http " + std::to_string(statusCode);
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return;
    }

    std::string pending;
    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &avail)) break;
        if (avail == 0) break;
        std::string chunk(avail, '\0');
        DWORD read = 0;
        if (!WinHttpReadData(hRequest, chunk.data(), avail, &read)) break;
        chunk.resize(read);
        pending += chunk;
        // 按 \n\n 切分 SSE 事件
        size_t pos;
        while ((pos = pending.find("\n\n")) != std::string::npos) {
            std::string ev = pending.substr(0, pos);
            pending.erase(0, pos + 2);
            std::string data;
            std::stringstream ss(ev);
            std::string line;
            while (std::getline(ss, line)) {
                if (line.rfind("data:", 0) == 0) {
                    if (!data.empty()) data += "\n";
                    data += line.substr(5);
                    // 去掉一个 leading 空格 (SSE 约定)
                    if (!data.empty() && data[0] == ' ') data.erase(0, 1);
                }
            }
            if (data == "[DONE]") {
                WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
                return;
            }
            if (data.empty()) continue;
            try {
                auto j = nlohmann::json::parse(data);
                auto& choice = j["choices"][0];
                if (choice.contains("delta") && choice["delta"].contains("content")) {
                    std::string d = choice["delta"]["content"].get<std::string>();
                    if (!d.empty() && onDelta) {
                        if (!onDelta(d)) {  // 客户端取消
                            WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
                            return;
                        }
                    }
                }
            } catch (...) { /* 忽略坏行 */ }
        }
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
}

}  // namespace zhinai::llm
