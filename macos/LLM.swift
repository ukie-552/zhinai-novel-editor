import Foundation

enum LLMError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

/// 原生 LLM 客户端：OpenAI 兼容协议 + Anthropic 原生协议，SSE 流式解析。
enum LLM {

    /// 流式对话。tools 非空时启用 Tool Use（仅 OpenAI 兼容协议；Anthropic 忽略）。
    /// 返回：累积文本 + 模型发起的工具调用（若有）
    @MainActor
    static func streamChat(config: ModelConfig, system: String,
                           messages: [ChatMsg],
                           temperature: Double? = nil,
                           topP: Double? = nil,
                           maxTokens: Int? = nil,
                           tools: [[String: Any]]? = nil,
                           onToolDelta: ((String) -> Void)? = nil,
                           onToolName: ((String) -> Void)? = nil,
                           onDelta: @escaping (String) -> Void) async throws -> (text: String, toolCalls: [ToolCall]) {
        let temp = temperature ?? config.temperature
        let tp = topP ?? config.topP
        let mt = maxTokens ?? config.maxTokens
        if config.provider == "anthropic" {
            let t = try await streamAnthropic(config: config, system: system, messages: messages,
                                              temperature: temp, topP: tp, maxTokens: mt, onDelta: onDelta)
            return (t, [])
        } else {
            return try await streamOpenAI(config: config, messages: messages, temperature: temp,
                                          topP: tp, maxTokens: mt, tools: tools,
                                          onToolDelta: onToolDelta, onToolName: onToolName, onDelta: onDelta)
        }
    }

    // MARK: - OpenAI 兼容

    @MainActor
    private static func streamOpenAI(config: ModelConfig, messages: [ChatMsg],
                                     temperature: Double, topP: Double, maxTokens: Int,
                                     tools: [[String: Any]]?,
                                     onToolDelta: ((String) -> Void)?,
                                     onToolName: ((String) -> Void)?,
                                     onDelta: @escaping (String) -> Void) async throws -> (String, [ToolCall]) {
        guard let base = URL(string: normalizedBase(config.baseURL)) else {
            throw LLMError.message("Base URL 无效")
        }
        let url = base.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { msgDict($0) },
            "temperature": temperature,
            "top_p": topP,
            "max_tokens": maxTokens,
            "stream": true,
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, resp) = try await URLSession.shared.bytes(for: req)
        } catch {
            throw LLMError.message("无法连接 \(url.absoluteString)：\(error.localizedDescription)")
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.message(await errorText(bytes: bytes, resp: resp, model: config.model))
        }

        var full = ""
        var toolCalls: [Int: ToolCall] = [:]   // 按 index 累积分片
        var callOrder: [Int] = []

        for try await line in bytes.lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("data:") else { continue }
            let payload = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = j["choices"] as? [[String: Any]],
                  let c0 = choices.first,
                  let delta = c0["delta"] as? [String: Any] else { continue }
            if let text = delta["content"] as? String, !text.isEmpty {
                full += text
                onDelta(text)
            }
            if let tcDelta = delta["tool_calls"] as? [[String: Any]] {
                for tc in tcDelta {
                    guard let idx = tc["index"] as? Int else { continue }
                    let id = tc["id"] as? String
                    let fn = tc["function"] as? [String: Any]
                    let name = fn?["name"] as? String
                    let args = fn?["arguments"] as? String ?? ""
                    if let name, !name.isEmpty {
                        onToolName?(name)
                        onToolDelta?("\n\(name)\n")
                    }
                    if !args.isEmpty { onToolDelta?(args) }
                    if toolCalls[idx] == nil {
                        toolCalls[idx] = ToolCall(id: id ?? "call_\(idx)", name: name ?? "", arguments: "")
                        callOrder.append(idx)
                    } else {
                        if let id { toolCalls[idx]?.id = id }
                        if let name { toolCalls[idx]?.name = name }
                    }
                    toolCalls[idx]?.arguments += args
                }
            }
        }
        let ordered = callOrder.compactMap { toolCalls[$0] }
        return (full, ordered)
    }

    /// 消息序列化（user / assistant / tool）
    private static func msgDict(_ m: ChatMsg) -> [String: Any] {
        switch m.role {
        case "tool":
            return ["role": "tool", "tool_call_id": m.toolCallID ?? "", "content": m.content]
        case "assistant":
            var d: [String: Any] = ["role": "assistant", "content": m.content]
            if let tcs = m.toolCalls, !tcs.isEmpty {
                d["tool_calls"] = tcs.map { tc in
                    ["id": tc.id, "type": "function",
                     "function": ["name": tc.name, "arguments": tc.arguments]]
                }
            }
            return d
        default:
            return ["role": "user", "content": m.content]
        }
    }

    // MARK: - Anthropic

    @MainActor
    private static func streamAnthropic(config: ModelConfig, system: String,
                                        messages: [ChatMsg],
                                        temperature: Double, topP: Double, maxTokens: Int,
                                        onDelta: @escaping (String) -> Void) async throws -> String {
        guard let base = URL(string: normalizedBase(config.baseURL)) else {
            throw LLMError.message("Base URL 无效")
        }
        let url = base.appendingPathComponent("v1/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": config.model,
            "system": system,
            "messages": messages.filter { $0.role != "tool" }.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": maxTokens,
            "temperature": temperature,
            "top_p": topP,
            "stream": true,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, resp) = try await URLSession.shared.bytes(for: req)
        } catch {
            throw LLMError.message("无法连接 \(url.absoluteString)：\(error.localizedDescription)")
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.message(await errorText(bytes: bytes, resp: resp, model: config.model))
        }

        var full = ""
        for try await line in bytes.lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("data:") else { continue }
            let payload = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if j["type"] as? String == "content_block_delta",
               let d = j["delta"] as? [String: Any],
               d["type"] as? String == "text_delta",
               let text = d["text"] as? String {
                full += text
                onDelta(text)
            } else if j["type"] as? String == "message_stop" {
                break
            }
        }
        return full
    }

    // MARK: - 非流式补全与连接测试

    /// 通用非流式补全（AI 生成 Agent 配置等场景）
    @MainActor
    static func complete(config: ModelConfig, system: String, user: String,
                         temperature: Double? = nil, maxTokens: Int = 1024) async throws -> String {
        let messages = [("user", user)]
        if config.provider == "anthropic" {
            guard let base = URL(string: normalizedBase(config.baseURL)) else { throw LLMError.message("Base URL 无效") }
            let url = base.appendingPathComponent("v1/messages")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = ["model": config.model, "system": system,
                                       "messages": messages.map { ["role": $0.0, "content": $0.1] },
                                       "max_tokens": maxTokens,
                                       "temperature": temperature ?? config.temperature]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw LLMError.message(userFacingAPIError(
                    status: (resp as? HTTPURLResponse)?.statusCode ?? -1, data: data, model: config.model
                ))
            }
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let blocks = j?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["text"] as? String }.joined()
        }
        guard let base = URL(string: normalizedBase(config.baseURL)) else { throw LLMError.message("Base URL 无效") }
        let url = base.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty { req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["model": config.model,
                                   "messages": messages.map { ["role": $0.0, "content": $0.1] },
                                   "max_tokens": maxTokens,
                                   "temperature": temperature ?? config.temperature]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.message(userFacingAPIError(
                status: (resp as? HTTPURLResponse)?.statusCode ?? -1, data: data, model: config.model
            ))
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = j?["choices"] as? [[String: Any]] ?? []
        return (choices.first?["message"] as? [String: Any])?["content"] as? String ?? "（无返回内容）"
    }

    @MainActor
    static func testConnection(config: ModelConfig) async throws -> String {
        let messages = [("user", "你好，请只回复四个字：连接成功")]
        if config.provider == "anthropic" {
            guard let base = URL(string: normalizedBase(config.baseURL)) else { throw LLMError.message("Base URL 无效") }
            let url = base.appendingPathComponent("v1/messages")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = ["model": config.model,
                                       "messages": messages.map { ["role": $0.0, "content": $0.1] },
                                       "max_tokens": config.maxTokens]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw LLMError.message(userFacingAPIError(
                    status: (resp as? HTTPURLResponse)?.statusCode ?? -1, data: data, model: config.model
                ))
            }
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let blocks = j?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["text"] as? String }.joined()
        }
        guard let base = URL(string: normalizedBase(config.baseURL)) else { throw LLMError.message("Base URL 无效") }
        let url = base.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty { req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["model": config.model,
                                   "messages": messages.map { ["role": $0.0, "content": $0.1] },
                                   "max_tokens": config.maxTokens]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.message(userFacingAPIError(
                status: (resp as? HTTPURLResponse)?.statusCode ?? -1, data: data, model: config.model
            ))
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = j?["choices"] as? [[String: Any]] ?? []
        return (choices.first?["message"] as? [String: Any])?["content"] as? String ?? "（无返回内容）"
    }

    // MARK: - Ollama 模型列表

    @MainActor
    static func ollamaModels(baseURL: String) async throws -> [String] {
        var b = normalizedBase(baseURL)
        if b.hasSuffix("/v1") { b = String(b.dropLast(3)) }
        guard let url = URL(string: b + "/api/tags") else { throw LLMError.message("Base URL 无效") }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.message("Ollama 接口错误")
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (j?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }

    private static func normalizedBase(_ s: String) -> String {
        var b = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    private static func errorText(bytes: URLSession.AsyncBytes, resp: URLResponse, model: String) async -> String {
        var body = ""
        do {
            for try await line in bytes.lines {
                body += line + "\n"
                if body.count > 600 { break }
            }
        } catch { /* ignore */ }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        return userFacingAPIError(status: status, body: body, model: model)
    }

    /// 将不同模型厂商返回的 JSON / 英文错误转换为用户能直接处理的中文提示。
    static func userFacingAPIError(status: Int, data: Data, model: String) -> String {
        userFacingAPIError(status: status,
                           body: String(data: data, encoding: .utf8) ?? "",
                           model: model)
    }

    static func userFacingAPIError(status: Int, body: String, model: String) -> String {
        let providerMessage = extractProviderMessage(from: body)
        let lower = providerMessage.lowercased()
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前模型" : model

        if lower.contains("max_tokens") || lower.contains("max tokens") || lower.contains("maximum output") {
            let limit = firstNumber(afterMaxTokensIn: providerMessage)
            let limitText = limit.map { "最多支持 \($0.formatted()) tokens" } ?? "不支持当前填写的输出长度"
            return "输出上限设置过高\n\(modelName) \(limitText)。请打开“设置 → 模型连接”，把“输出上限”调低后重试。"
        }
        if lower.contains("context length") || lower.contains("context window")
            || lower.contains("too many tokens") || lower.contains("prompt is too long") {
            return "输入内容超过模型窗口\n请缩短输入内容，或在“设置 → 上下文压缩”中提高压缩强度后重试。"
        }
        if status == 401 || status == 403 || lower.contains("api key")
            || lower.contains("unauthorized") || lower.contains("authentication") {
            return "模型服务认证失败\n请检查“设置 → 模型连接”中的 API Key、Base URL 和账号权限。"
        }
        if status == 404 || lower.contains("model not found") || lower.contains("does not exist") {
            return "找不到模型“\(modelName)”\n请检查模型名称，或从该厂商的模型列表中重新选择。"
        }
        if status == 429 || lower.contains("rate limit") || lower.contains("too many requests") {
            return "请求过于频繁\n模型厂商暂时限流，请稍等片刻后重试。"
        }
        if lower.contains("quota") || lower.contains("balance") || lower.contains("insufficient")
            || lower.contains("credit") {
            return "模型账户额度不足\n请前往模型厂商控制台检查余额、套餐或调用额度。"
        }
        if status >= 500 {
            return "模型服务暂时不可用（HTTP \(status)）\n这是厂商服务端故障，请稍后重试。"
        }
        if !providerMessage.isEmpty {
            return "模型请求失败（HTTP \(status)）\n厂商提示：\(providerMessage)"
        }
        return "模型请求失败（HTTP \(status)）\n模型厂商没有返回具体原因，请检查连接设置后重试。"
    }

    private static func extractProviderMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func message(in value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                if let text = dictionary["message"] as? String, !text.isEmpty { return text }
                if let text = dictionary["msg"] as? String, !text.isEmpty { return text }
                if let error = dictionary["error"], let found = message(in: error) { return found }
                for child in dictionary.values {
                    if let found = message(in: child) { return found }
                }
            } else if let values = value as? [Any] {
                for child in values {
                    if let found = message(in: child) { return found }
                }
            }
            return nil
        }
        return message(in: object) ?? ""
    }

    private static func firstNumber(afterMaxTokensIn message: String) -> Int? {
        let pattern = #"(?i)max[_ ]?tokens[^0-9]{0,40}([0-9][0-9,]*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return Int(message[range].replacingOccurrences(of: ",", with: ""))
    }
}
