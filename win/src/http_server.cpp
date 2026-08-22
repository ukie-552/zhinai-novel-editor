// http_server.cpp - 用 cpp-httplib 暴露 REST API + 静态资源
#include "http_server.h"
#include "db.h"
#include "llm.h"
#include "skills.h"
#include "vector_store.h"
#include "config.h"
#include "platform.h"
#include "skills_catalog.h"

#define CPPHTTPLIB_THREAD_POOL_COUNT 8
#include <httplib.h>
#include <nlohmann/json.hpp>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <queue>
#include <condition_variable>

namespace zhinai::http {

namespace {

using nlohmann::json;

// 流式状态: producer 线程 + provider 线程共享, 通过 mutex + cv 同步
struct StreamState {
    std::mutex mtx;
    std::condition_variable cv;
    std::queue<std::string> queue;
    bool done = false;
    bool cancelled = false;
    ~StreamState() = default;
};

httplib::Server* asImpl(void* p) { return reinterpret_cast<httplib::Server*>(p); }

void setCORS(httplib::Response& res) {
    // 前端是同源的 (127.0.0.1:port), 无需 CORS. 留空, 避免奇怪的浏览器策略.
}

// -- helpers --
json bookToJson(const db::Book& b) {
    return {
        {"id", b.id}, {"title", b.title}, {"author", b.author},
        {"summary", b.summary}, {"createdAt", b.createdAt}, {"updatedAt", b.updatedAt}
    };
}
json chapterToJson(const db::Chapter& c) {
    return {
        {"id", c.id}, {"bookId", c.bookId}, {"orderIndex", c.orderIndex},
        {"title", c.title}, {"content", c.content}, {"updatedAt", c.updatedAt}
    };
}
json loreToJson(const db::LoreEntry& e) {
    return {
        {"id", e.id}, {"kind", e.kind}, {"name", e.name},
        {"content", e.content}, {"keywords", e.keywords}, {"updatedAt", e.updatedAt}
    };
}
json agentToJson(const db::Agent& a) {
    return {
        {"id", a.id}, {"name", a.name}, {"prompt", a.prompt},
        {"model", a.model}, {"skill", a.skill}, {"toolGroups", a.toolGroups}
    };
}
json convToJson(const db::Conversation& c) {
    return {
        {"id", c.id}, {"title", c.title}, {"agentId", c.agentId},
        {"bookId", c.bookId}, {"createdAt", c.createdAt}
    };
}
json msgToJson(const db::Message& m) {
    return {
        {"id", m.id}, {"convId", m.convId}, {"role", m.role},
        {"content", m.content}, {"createdAt", m.createdAt}
    };
}

void registerBooks(httplib::Server& s) {
    s.Get("/api/books", [](const httplib::Request&, httplib::Response& res) {
        json arr = json::array();
        for (auto& b : db::listBooks()) arr.push_back(bookToJson(b));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post("/api/books", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; res.set_content("{\"error\":\"bad json\"}", "application/json"); return; }
        auto id = db::createBook(j.value("title", "未命名"), j.value("author", ""), j.value("summary", ""));
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
    s.Get(R"(/api/books/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto b = db::getBook(id);
        if (!b) { res.status = 404; return; }
        res.set_content(bookToJson(*b).dump(), "application/json");
    });
    s.Put(R"(/api/books/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        bool ok = db::updateBook(id, j.value("title", ""), j.value("author", ""), j.value("summary", ""));
        res.set_content(json{{"ok", ok}}.dump(), "application/json");
    });
    s.Delete(R"(/api/books/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        res.set_content(json{{"ok", db::deleteBook(id)}}.dump(), "application/json");
    });
}

void registerChapters(httplib::Server& s) {
    s.Get(R"(/api/books/(\d+)/chapters)", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        json arr = json::array();
        for (auto& c : db::listChapters(id)) arr.push_back(chapterToJson(c));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post(R"(/api/books/(\d+)/chapters)", [](const httplib::Request& req, httplib::Response& res) {
        auto bookId = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        int order = j.value("orderIndex", (int)db::listChapters(bookId).size());
        auto id = db::createChapter(bookId, order, j.value("title", "新章节"));
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
    s.Get(R"(/api/chapters/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto c = db::getChapter(id);
        if (!c) { res.status = 404; return; }
        res.set_content(chapterToJson(*c).dump(), "application/json");
    });
    s.Put(R"(/api/chapters/(\d+)/content)", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded() || !j.contains("content")) { res.status = 400; return; }
        bool ok = db::updateChapterContent(id, j["content"].get<std::string>());
        res.set_content(json{{"ok", ok}}.dump(), "application/json");
    });
    s.Put(R"(/api/chapters/(\d+)/title)", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        bool ok = db::updateChapterTitle(id, j.value("title", ""));
        res.set_content(json{{"ok", ok}}.dump(), "application/json");
    });
    s.Post(R"(/api/books/(\d+)/chapters/reorder)", [](const httplib::Request& req, httplib::Response& res) {
        auto bookId = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded() || !j.contains("ids") || !j["ids"].is_array()) { res.status = 400; return; }
        std::vector<long long> ids;
        for (auto& v : j["ids"]) ids.push_back(v.get<long long>());
        bool ok = db::reorderChapters(bookId, ids);
        res.set_content(json{{"ok", ok}}.dump(), "application/json");
    });
    s.Delete(R"(/api/chapters/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        res.set_content(json{{"ok", db::deleteChapter(id)}}.dump(), "application/json");
    });
}

void registerLore(httplib::Server& s) {
    s.Get("/api/lore", [](const httplib::Request&, httplib::Response& res) {
        json arr = json::array();
        for (auto& e : db::listLore()) arr.push_back(loreToJson(e));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post("/api/lore", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        auto id = db::createLore(j.value("kind", "other"), j.value("name", ""),
                                  j.value("content", ""), j.value("keywords", ""));
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
    s.Put(R"(/api/lore/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        bool ok = db::updateLore(id, j.value("kind", "other"), j.value("name", ""),
                                  j.value("content", ""), j.value("keywords", ""));
        res.set_content(json{{"ok", ok}}.dump(), "application/json");
    });
    s.Delete(R"(/api/lore/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        res.set_content(json{{"ok", db::deleteLore(id)}}.dump(), "application/json");
    });
    s.Post("/api/lore/match", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        std::string text = j.value("text", "");
        json arr = json::array();
        for (auto& e : db::findLoreByKeywords(text)) arr.push_back(loreToJson(e));
        res.set_content(arr.dump(), "application/json");
    });
}

void registerAgents(httplib::Server& s) {
    s.Get("/api/agents", [](const httplib::Request&, httplib::Response& res) {
        json arr = json::array();
        for (auto& a : db::listAgents()) arr.push_back(agentToJson(a));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post("/api/agents", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        db::Agent a;
        a.id = j.value("id", 0LL);
        a.name = j.value("name", "");
        a.prompt = j.value("prompt", "");
        a.model = j.value("model", "");
        a.skill = j.value("skill", "");
        a.toolGroups = j.value("toolGroups", "");
        auto id = db::upsertAgent(a);
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
    s.Delete(R"(/api/agents/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        res.set_content(json{{"ok", db::deleteAgent(id)}}.dump(), "application/json");
    });
}

void registerConversations(httplib::Server& s) {
    s.Get("/api/conversations", [](const httplib::Request&, httplib::Response& res) {
        json arr = json::array();
        for (auto& c : db::listConversions()) arr.push_back(convToJson(c));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post("/api/conversations", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        auto id = db::createConversation(j.value("title", "新对话"),
                                          j.value("agentId", 0LL),
                                          j.value("bookId", 0LL));
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
    s.Delete(R"(/api/conversations/(\d+))", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        res.set_content(json{{"ok", db::deleteConversation(id)}}.dump(), "application/json");
    });
    s.Get(R"(/api/conversations/(\d+)/messages)", [](const httplib::Request& req, httplib::Response& res) {
        auto id = std::stoll(req.matches[1]);
        json arr = json::array();
        for (auto& m : db::listMessages(id)) arr.push_back(msgToJson(m));
        res.set_content(arr.dump(), "application/json");
    });
    s.Post(R"(/api/conversations/(\d+)/messages)", [](const httplib::Request& req, httplib::Response& res) {
        auto convId = std::stoll(req.matches[1]);
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        auto id = db::appendMessage(convId, j.value("role", "user"), j.value("content", ""));
        res.set_content(json{{"id", id}}.dump(), "application/json");
    });
}

void registerLLM(httplib::Server& s) {
    // 测试连接
    s.Post("/api/llm/test", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        llm::Config cfg;
        cfg.baseURL = j.value("baseURL", "");
        cfg.apiKey = j.value("apiKey", "");
        cfg.model = j.value("model", "");
        cfg.timeoutSec = j.value("timeoutSec", 15);
        llm::Request r{cfg, {{"user", "ping"}}, 0.0, 16};
        auto resp = llm::chat(r);
        res.set_content(json{{"ok", resp.ok}, {"error", resp.error}, {"content", resp.content}}.dump(),
                        "application/json");
    });

    // 同步对话 (支持 skillId 自动拼 system prompt)
    s.Post("/api/llm/chat", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        auto cfg = config::loadConfig();
        llm::Config c;
        c.baseURL = j.value("baseURL", cfg.value("baseURL", ""));
        c.apiKey = j.value("apiKey", cfg.value("apiKey", ""));
        c.model = j.value("model", cfg.value("model", ""));
        c.timeoutSec = j.value("timeoutSec", 60);
        llm::Request r;
        r.cfg = c;
        r.temperature = j.value("temperature", 0.7);
        r.maxTokens = j.value("maxTokens", 0);
        if (j.contains("messages") && j["messages"].is_array()) {
            for (auto& m : j["messages"]) {
                r.messages.push_back({m.value("role", "user"), m.value("content", "")});
            }
        }

        // skillId -> 自动拼 system prompt (跟 macOS 的 performSend 对齐)
        std::string skillId = j.value("skillId", "");
        std::string injectedSys;
        if (!skillId.empty() && skillId != "chat") {
            // 先查内置
            skills_catalog::Skill sk;
            bool found = false;
            for (const auto& s : skills_catalog::builtIn()) {
                if (s.id == skillId) { sk = s; found = true; break; }
            }
            // 再查用户 Markdown 技能
            if (!found) {
                for (const auto& u : skills::list()) {
                    if (u.name == skillId) {
                        sk = skills_catalog::Skill{
                            u.name, u.name, "📄", u.summary, "user",
                            skills::read(u.name), false, 0, false, u.path
                        };
                        found = true;
                        break;
                    }
                }
            }
            if (found) {
                // 拼 system prompt: 命中设定上下文 + skill 任务指令
                std::string loreCtx;
                if (j.contains("loreHits") && j["loreHits"].is_array()) {
                    for (auto& e : j["loreHits"]) {
                        loreCtx += "- " + e.value("name", "") + ": " + e.value("content", "") + "\n";
                    }
                }
                injectedSys = skills_catalog::composeSystemPrompt(sk, loreCtx);
            }
        }

        // 注入 system message (放在最前)
        if (!injectedSys.empty()) {
            r.messages.insert(r.messages.begin(), {"system", injectedSys});
        }

        auto resp = llm::chat(r);
        res.set_content(json{{"ok", resp.ok}, {"content", resp.content}, {"error", resp.error}}.dump(),
                        "application/json");
    });

    // 流式对话 (SSE) - 真正 chunked, 边收边推
    s.Post("/api/llm/chat/stream", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        auto cfg = config::loadConfig();
        llm::Config c;
        c.baseURL = j.value("baseURL", cfg.value("baseURL", ""));
        c.apiKey = j.value("apiKey", cfg.value("apiKey", ""));
        c.model = j.value("model", cfg.value("model", ""));
        c.timeoutSec = j.value("timeoutSec", 60);
        llm::Request r;
        r.cfg = c;
        r.temperature = j.value("temperature", 0.7);
        r.maxTokens = j.value("maxTokens", 0);
        if (j.contains("messages") && j["messages"].is_array()) {
            for (auto& m : j["messages"]) {
                r.messages.push_back({m.value("role", "user"), m.value("content", "")});
            }
        }
        // skill 注入
        std::string skillId = j.value("skillId", "");
        if (!skillId.empty() && skillId != "chat") {
            skills_catalog::Skill sk;
            bool found = false;
            for (const auto& s : skills_catalog::builtIn()) {
                if (s.id == skillId) { sk = s; found = true; break; }
            }
            if (!found) {
                for (const auto& u : skills::list()) {
                    if (u.name == skillId) {
                        sk = skills_catalog::Skill{
                            u.name, u.name, "📄", u.summary, "user",
                            skills::read(u.name), false, 0, false, u.path
                        };
                        found = true;
                        break;
                    }
                }
            }
            if (found) {
                std::string loreCtx;
                if (j.contains("loreHits") && j["loreHits"].is_array()) {
                    for (auto& e : j["loreHits"]) {
                        loreCtx += "- " + e.value("name", "") + ": " + e.value("content", "") + "\n";
                    }
                }
                std::string sys = skills_catalog::composeSystemPrompt(sk, loreCtx);
                r.messages.insert(r.messages.begin(), {"system", sys});
            }
        }

        // chunked SSE: producer 线程调 chatStream, 把 delta 写进 queue
        // provider 拉 queue 写到 socket. done 标志通知结束.
        auto* state = new StreamState();
        std::thread producer([state, r]() mutable {
            std::string err;
            llm::chatStream(r,
                [state](const std::string& d) -> bool {
                    if (state->cancelled) return false;
                    {
                        std::lock_guard<std::mutex> lk(state->mtx);
                        state->queue.push("data: " + json{{"delta", d}}.dump() + "\n\n");
                    }
                    state->cv.notify_one();
                    return true;
                },
                err);
            {
                std::lock_guard<std::mutex> lk(state->mtx);
                if (!err.empty()) {
                    state->queue.push("data: " + json{{"error", err}}.dump() + "\n\n");
                } else {
                    state->queue.push("data: " + json{{"done", true}}.dump() + "\n\n");
                }
                state->done = true;
            }
            state->cv.notify_one();
        });
        producer.detach();

        res.set_chunked_content_provider("text/event-stream; charset=utf-8",
            [state](size_t /*offset*/, httplib::DataSink& sink) -> bool {
                std::unique_lock<std::mutex> lk(state->mtx);
                state->cv.wait_for(lk, std::chrono::milliseconds(500),
                                   [state]() { return !state->queue.empty() || state->done; });
                if (!state->queue.empty()) {
                    auto chunk = state->queue.front();
                    state->queue.pop();
                    lk.unlock();
                    sink.write(chunk.data(), chunk.size());
                    return true;
                }
                // queue 空 + done -> 结束
                if (state->done) {
                    delete state;  // 释放
                    return false;
                }
                // 还没 done, 继续等 (但避免空 spin)
                lk.unlock();
                return true;
            });
    });
}

void registerSkills(httplib::Server& s) {
    s.Get("/api/skills", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(skills::listAsJson().dump(), "application/json");
    });

    // 内置 + 用户 Markdown 技能的全集 (供前端 AI 工具菜单) -
    // 必须在 /api/skills/<name> 之前注册, 否则通配会吞掉 "catalog"
    s.Get("/api/skills/catalog", [](const httplib::Request&, httplib::Response& res) {
        json arr = json::array();
        for (const auto& s : skills_catalog::builtIn()) {
            arr.push_back({
                {"id", s.id}, {"name", s.name}, {"icon", s.icon},
                {"desc", s.desc}, {"category", s.category},
                {"needsText", s.needsText}, {"chapters", s.chapters},
                {"builtIn", s.builtIn},
            });
        }
        auto userList = skills::list();
        for (const auto& s : userList) {
            arr.push_back({
                {"id", s.name}, {"name", s.name}, {"icon", "📄"},
                {"desc", s.summary}, {"category", "user"},
                {"needsText", false}, {"chapters", 0},
                {"builtIn", false}, {"filePath", s.path},
            });
        }
        res.set_content(arr.dump(), "application/json");
    });

    s.Get(R"(/api/skills/([^/]+))", [](const httplib::Request& req, httplib::Response& res) {
        std::string name = req.matches[1];
        res.set_content(json{{"name", name}, {"content", skills::read(name)}}.dump(), "application/json");
    });
}

void registerVectors(httplib::Server& s) {
    s.Post("/api/vectors/import", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        std::string source = j.value("source", "");
        std::string text = j.value("text", "");
        vector::importText(source, text);
        res.set_content(vector::stats().dump(), "application/json");
    });
    s.Post("/api/vectors/search", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        std::string q = j.value("query", "");
        int topK = j.value("topK", 5);
        json arr = json::array();
        for (auto& h : vector::search(q, topK)) {
            arr.push_back({{"source", h.source}, {"snippet", h.snippet}, {"score", h.score}});
        }
        res.set_content(arr.dump(), "application/json");
    });
    s.Get("/api/vectors/stats", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(vector::stats().dump(), "application/json");
    });
}

void registerConfig(httplib::Server& s) {
    s.Get("/api/config", [](const httplib::Request&, httplib::Response& res) {
        // 跟原 config 合并默认值, 让前端能拿到完整 schema
        json cfg = config::loadConfig();
        // 模型商预设
        cfg["providers"] = {
            {{"id", "openai"}, {"label", "OpenAI"}, {"baseURL", "https://api.openai.com/v1"},
             {"models", {"gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "o1-mini"}}},
            {{"id", "deepseek"}, {"label", "DeepSeek"}, {"baseURL", "https://api.deepseek.com/v1"},
             {"models", {"deepseek-chat", "deepseek-reasoner"}}},
            {{"id", "dashscope"}, {"label", "通义千问 (DashScope)"}, {"baseURL", "https://dashscope.aliyuncs.com/compatible-mode/v1"},
             {"models", {"qwen-plus", "qwen-turbo", "qwen-max", "qwen-long"}}},
            {{"id", "zhipu"}, {"label", "智谱 GLM"}, {"baseURL", "https://open.bigmodel.cn/api/paas/v4"},
             {"models", {"glm-4-flash", "glm-4-air", "glm-4-plus"}}},
            {{"id", "ollama"}, {"label", "Ollama (本地)"}, {"baseURL", "http://127.0.0.1:11434/v1"},
             {"models", {"qwen2.5:7b", "llama3.1:8b", "gemma2:9b"}}},
            {{"id", "custom"}, {"label", "自定义"}, {"baseURL", ""}, {"models", json::array()}},
        };
        cfg["defaults"] = {
            {"temperature", 0.7}, {"maxTokens", 8192}, {"contextWindow", 131072},
            {"enableTools", true}, {"enableContextCompression", true},
            {"backgroundOpacity", 0.64}, {"backgroundMediaPath", ""},
            {"followsStreamingOutput", true},
        };
        // 补默认值
        for (auto it = cfg["defaults"].begin(); it != cfg["defaults"].end(); ++it) {
            if (!cfg.contains(it.key())) cfg[it.key()] = it.value();
        }
        res.set_content(cfg.dump(), "application/json");
    });
    s.Put("/api/config", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body, nullptr, false);
        if (j.is_discarded()) { res.status = 400; return; }
        // 去掉前端不存的后端辅助字段
        j.erase("providers");
        j.erase("defaults");
        config::saveConfig(j);
        res.set_content(R"({"ok":true})", "application/json");
    });
}

void registerStatic(httplib::Server& s, const std::string& webDir) {
    if (!s.set_mount_point("/", webDir)) {
        platform::log("WARN", "static mount failed: " + webDir);
    }
    s.Get("/", [webDir](const httplib::Request&, httplib::Response& res) {
        std::ifstream f((std::filesystem::path(webDir) / "index.html").string(), std::ios::binary);
        if (!f) { res.status = 404; return; }
        std::stringstream ss; ss << f.rdbuf();
        res.set_content(ss.str(), "text/html; charset=utf-8");
    });
}

void registerSearch(httplib::Server& s) {
    s.Get("/api/search", [](const httplib::Request& req, httplib::Response& res) {
        std::string q = req.get_param_value("q");
        if (q.empty()) { res.set_content("[]", "application/json"); return; }
        // 简单 LIKE 搜索 (够用), FTS5 等下版升级
        auto books = db::listBooks();
        json out = json::array();
        for (const auto& b : books) {
            if (b.title.find(q) != std::string::npos ||
                b.author.find(q) != std::string::npos ||
                b.summary.find(q) != std::string::npos) {
                out.push_back({{"type", "book"}, {"id", b.id}, {"title", b.title},
                                {"snippet", b.summary}, {"score", 1}});
            }
        }
        for (const auto& b : books) {
            for (const auto& c : db::listChapters(b.id)) {
                if (c.title.find(q) != std::string::npos ||
                    c.content.find(q) != std::string::npos) {
                    std::string snippet;
                    auto pos = c.content.find(q);
                    if (pos != std::string::npos) {
                        size_t start = (pos > 40) ? pos - 40 : 0;
                        size_t end = std::min(c.content.size(), pos + q.size() + 40);
                        snippet = c.content.substr(start, end - start);
                    } else snippet = c.title;
                    out.push_back({{"type", "chapter"}, {"id", c.id}, {"bookId", b.id},
                                    {"title", c.title}, {"snippet", snippet}, {"score", 1}});
                }
            }
        }
        for (const auto& e : db::listLore()) {
            if (e.name.find(q) != std::string::npos ||
                e.content.find(q) != std::string::npos ||
                e.keywords.find(q) != std::string::npos) {
                std::string snippet;
                auto pos = e.content.find(q);
                if (pos != std::string::npos) {
                    size_t start = (pos > 40) ? pos - 40 : 0;
                    size_t end = std::min(e.content.size(), pos + q.size() + 40);
                    snippet = e.content.substr(start, end - start);
                } else snippet = e.name;
                out.push_back({{"type", "lore"}, {"id", e.id}, {"name", e.name},
                                {"snippet", snippet}, {"score", 1}});
            }
        }
        res.set_content(out.dump(), "application/json");
    });
}

}  // namespace

bool start(Server& s, const std::string& webDir, int& outPort) {
    auto* impl = new httplib::Server();
    s.impl = impl;

    registerBooks(*impl);
    registerChapters(*impl);
    registerSearch(*impl);
    registerLore(*impl);
    registerAgents(*impl);
    registerConversations(*impl);
    registerLLM(*impl);
    registerSkills(*impl);
    registerVectors(*impl);
    registerConfig(*impl);
    registerStatic(*impl, webDir);

    impl->set_exception_handler([](const httplib::Request&, httplib::Response& res, std::exception_ptr ep) {
        std::string msg = "internal error";
        try { if (ep) std::rethrow_exception(ep); }
        catch (const std::exception& e) { msg = e.what(); }
        catch (...) {}
        res.status = 500;
        res.set_content(json{{"error", msg}}.dump(), "application/json");
    });

    // 找空闲端口: 从 8090 开始
    int port = 8090;
    for (int tries = 0; tries < 50; ++tries) {
        if (impl->bind_to_port("127.0.0.1", port)) break;
        port++;
    }
    s.port = port;
    outPort = port;

    s.running = true;
    s.th = std::thread([impl, port]() {
        platform::log("INFO", "http server listening on 127.0.0.1:" + std::to_string(port));
        impl->listen_after_bind();
    });

    // 等服务起来
    for (int i = 0; i < 100; ++i) {
        if (impl->is_running()) break;
        Sleep(20);
    }
    return impl->is_running();
}

void stop(Server& s) {
    if (!s.impl) return;
    auto* impl = asImpl(s.impl);
    impl->stop();
    if (s.th.joinable()) s.th.join();
    delete impl;
    s.impl = nullptr;
    s.running = false;
}

}  // namespace zhinai::http
