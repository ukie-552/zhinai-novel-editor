import SwiftUI

// MARK: - AI 助手：会话切换 + 与 Agent 对话

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @Binding var isPresented: Bool
    @State private var showsOutputUsage = false
    @AppStorage("chat.followsStreamingOutput") private var followsStreamingOutput = true

    private var fixedSkill: Skill? {
        guard let id = app.currentAgent.fixedSkillID, id != "chat" else { return nil }
        return app.skills.first { $0.id == id }
    }

    private var currentConversation: Conversation? {
        app.conversations.first { $0.id == app.currentConversationID }
    }
    /// 选择作用域的事件只提供给模型，不作为聊天内容展示。
    private var visibleMessages: [Msg] {
        app.messages.filter { $0.role != "event" }
    }
    private var currentBackgroundRun: ConversationRun? {
        app.currentConversationID.flatMap { app.conversationRunStates[$0] }
    }
    private var currentConversationBusy: Bool {
        app.streaming || currentBackgroundRun?.status == "queued" || currentBackgroundRun?.status == "running"
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsHeader
                .frame(height: 42)
                .layoutPriority(2)
            Divider()
            messageList
                .frame(minHeight: 0, maxHeight: .infinity)
            Divider()
            inputBar
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Agent 与技能

    private var controlsHeader: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(app.agents) { a in
                    Button {
                        app.selectAgent(a.id)
                    } label: {
                        if a.id == app.currentAgentID {
                            Label(a.name, systemImage: "checkmark")
                        } else {
                            Text(a.name)
                        }
                    }
                }
                Divider()
                Button("管理 Agent…") { app.showAgentSheet = true }
            } label: {
                HStack(spacing: 4) {
                    AgentIconView(icon: app.currentAgent.icon,
                                  avatarPath: app.currentAgent.avatarPath,
                                  size: 14)
                        .font(.system(size: 10))
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
                    Text(app.currentAgent.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Agent：自定义系统提示词人格")

            if let fixedSkill {
                HStack(spacing: 4) {
                    Image(systemName: fixedSkill.icon)
                    Text("固定：\(fixedSkill.name)")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("此 Skill 固定绑定在当前 Agent；请在 Agent 编辑页修改")
            }
            Spacer()
            if currentConversationBusy {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
            Text(PROVIDERS[app.config.provider]?.label ?? app.config.provider)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("当前模型：\(app.config.model)")
            Menu {
                if let c = currentConversation {
                    Button("重命名…") { promptRename(c) }
                    Button("清空消息") { app.clearMessages() }
                    Divider()
                    Button("删除对话", role: .destructive) { app.deleteConversation() }
                } else {
                    Text("请先新建对话")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .help("对话操作")
            Button {
                app.createConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("新对话（⌥⌘N）")
            .keyboardShortcut("n", modifiers: [.option, .command])
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private func promptRename(_ c: Conversation) {
        let alert = NSAlert()
        alert.messageText = "重命名对话"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = c.title
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            app.renameConversation(c.id, title: field.stringValue)
        }
    }

    // MARK: 消息列表

    private var messageList: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                    ForEach(visibleMessages) { m in
                        MessageRow(msg: m)
                            .id(m.id)
                    }
                    if app.streaming {
                        StreamingRow(text: app.streamingText,
                                     reasoningDuration: app.streamingReasoningDuration,
                                     toolName: app.streamingToolName)
                            .id("streaming")
                    } else if let run = currentBackgroundRun,
                              run.status == "queued" || run.status == "running" {
                        StreamingRow(text: run.partialText.isEmpty ? "后台 Agent 正在准备…" : run.partialText)
                            .id("background-streaming")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .onChange(of: app.messages.count) { _ in
                    guard followsStreamingOutput else { return }
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: app.streaming) { streaming in
                    if streaming && followsStreamingOutput {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: app.streamingText) { _ in
                    guard followsStreamingOutput else { return }
                    // 等本次流式文本完成布局后再滚动，确保跟到新增加的最后一行。
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: currentBackgroundRun?.partialText) { _ in
                    guard followsStreamingOutput else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: followsStreamingOutput) { enabled in
                    guard enabled else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            if visibleMessages.isEmpty && !currentConversationBusy {
                VStack(spacing: 8) {
                    Image(systemName: app.currentNovelID == nil ? "lightbulb" : "bubble.left.and.bubble.right")
                        .font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(app.currentNovelID == nil
                         ? "没有灵感？有什么想写的书？\n和 Agent 聊聊吧"
                         : "选择 Agent 开始对话\nSkill 由 Agent 固定或按索引自行调取")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: 输入区

    private var inputBar: some View {
        VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $app.draft)
                    .font(.system(size: 13.5))
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                    .disabled(app.isCompressingContext)
                Button {
                    app.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(canSend ? Color.accentColor : Color.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("发送（⌘⏎）")
            }
            HStack {
                if app.isCompressingContext {
                    ProgressView()
                        .controlSize(.mini)
                    Text("上下文压缩中")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("⌘⏎ 发送 · ⌥⌘N 新对话 · ⌘S 保存")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if app.streaming {
                    Button("停止") { app.stopStreaming() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                } else if let run = currentBackgroundRun,
                          run.status == "queued" || run.status == "running" {
                    Button("取消后台任务") { _ = app.cancelConversationRun(run.conversationID) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            if hasUsableModel {
                conversationUsageBar
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// 永远显示在对话底部：点击即在输入上下文和本轮输出之间切换。
    private var conversationUsageBar: some View {
        let tokens = showsOutputUsage ? app.currentRequestOutputTokens : app.currentRequestInputTokens
        let limit = showsOutputUsage ? outputLimit : app.config.contextWindow
        let fraction = min(max(Double(tokens) / Double(max(limit, 1)), 0), 1)
        let color: Color = fraction >= 0.9 ? .red : (fraction >= 0.75 ? .orange : .accentColor)

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showsOutputUsage.toggle()
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: showsOutputUsage ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                    Text(showsOutputUsage ? "输出" : "输入上下文")
                    if !showsOutputUsage, let plan = app.lastPlan {
                        if plan.requestExceedsInputBudget {
                            Text("· 输入超出窗口")
                                .foregroundStyle(.red)
                        } else if plan.protectedContentExceededBudget {
                            Text("· 受保护内容超出目标")
                                .foregroundStyle(.orange)
                        } else if plan.compressionApplied {
                            Text("· 已压缩 \(plan.compressionPercent)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showsOutputUsage {
                        Text("· \(app.currentRequestOutputLines) 行 · \(app.currentRequestOutputCharacters) 字")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if fraction >= 0.8 {
                        Text("接近上限")
                            .foregroundStyle(color)
                    } else {
                        Text("点击切换")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 10.5))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(color)
                            .frame(width: max(3, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsOutputUsage
              ? "本轮模型输出：对话文本 \(app.currentRequestTextOutputTokens) token + 文件/工具编辑 \(app.currentRequestToolOutputTokens) token"
              : "本轮实际发送的输入上下文；上限跟随设置中的输入窗口")
    }

    private var outputLimit: Int {
        app.currentAgent.maxTokens ?? app.config.maxTokens
    }

    /// 只有在可以实际调用的模型已配置时，才展示这个模型的 token 预算。
    private var hasUsableModel: Bool {
        !app.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (app.config.provider == "ollama"
                || !app.config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canSend: Bool {
        !app.isCompressingContext
            && !currentConversationBusy
            && !app.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 消息气泡

private enum ChatMarkdownFormatter {
    static func displaySource(_ source: String) -> String {
        var output: [String] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if isFence(trimmed) || isTableDelimiter(trimmed) { continue }
            if isHorizontalRule(trimmed) {
                appendBlankLine(to: &output)
                continue
            }
            if trimmed.isEmpty {
                appendBlankLine(to: &output)
                continue
            }

            if let heading = headingText(trimmed) {
                output.append("**\(heading)**")
                continue
            }
            if isTableRow(trimmed) {
                let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !cells.isEmpty { output.append(cells.joined(separator: " · ")) }
                continue
            }

            var line = trimmed
            while line.hasPrefix(">") {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                line = "• " + line.dropFirst(2)
            }
            output.append(line)
        }

        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
    }

    static func attributed(_ source: String, showsCursor: Bool = false) -> AttributedString {
        let prepared = displaySource(source)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: prepared, options: options))
            ?? AttributedString(prepared.replacingOccurrences(of: "**", with: ""))
        if showsCursor { result.append(AttributedString("▌")) }
        return result
    }

    private static func appendBlankLine(to output: inout [String]) {
        if !output.isEmpty && output.last?.isEmpty != true { output.append("") }
    }

    private static func headingText(_ line: String) -> String? {
        let count = line.prefix { $0 == "#" }.count
        guard (1...6).contains(count) else { return nil }
        let remainder = line.dropFirst(count)
        guard remainder.first?.isWhitespace == true else { return nil }
        let heading = remainder.trimmingCharacters(in: .whitespaces)
        return heading.isEmpty ? nil : heading
    }

    private static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }
        return line.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0.isWhitespace }
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && (line.hasPrefix("|") || line.hasSuffix("|"))
    }
}

private struct MarkdownMessageText: View {
    let source: String
    var showsCursor = false

    var body: some View {
        Text(ChatMarkdownFormatter.attributed(source, showsCursor: showsCursor))
    }
}

struct MessageRow: View {
    @EnvironmentObject var app: AppState
    let msg: Msg

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if msg.role == "assistant" {
                avatar
                bubble
                Spacer(minLength: 30)
            } else {
                Spacer(minLength: 30)
                bubble
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if msg.role == "assistant" {
            AgentIconView(icon: app.currentAgent.icon,
                          avatarPath: app.currentAgent.avatarPath,
                          size: 26)
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5) }
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background(Color.green.opacity(0.2), in: Circle())
                .foregroundStyle(Color.green)
        }
    }

    private var bubble: some View {
        let legacyParts = msg.role == "assistant" ? ModelOutputParser.parse(msg.content) : nil
        let reasoning = msg.reasoning.isEmpty ? (legacyParts?.reasoning ?? "") : msg.reasoning
        let response = legacyParts?.response ?? msg.content
        return VStack(alignment: .leading, spacing: 4) {
            if msg.role == "assistant" && !msg.skill.isEmpty && msg.skill != "chat" {
                Text(skillByID(msg.skill, skills: app.skills).name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if msg.role == "assistant" && !reasoning.isEmpty {
                ThinkingDisclosure(reasoning: reasoning,
                                   duration: msg.reasoningDuration,
                                   inProgress: false)
            }
            if !response.isEmpty {
                MarkdownMessageText(source: response)
                    .font(.system(size: 13.5))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(msg.role == "user" ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 640, alignment: msg.role == "user" ? .trailing : .leading)
    }
}

// MARK: - 流式输出行

struct StreamingRow: View {
    @EnvironmentObject var app: AppState
    let text: String
    var reasoningDuration: Double = 0
    var toolName: String? = nil

    private var parts: ParsedModelOutput { ModelOutputParser.parse(text) }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AgentIconView(icon: app.currentAgent.icon,
                          avatarPath: app.currentAgent.avatarPath,
                          size: 26)
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5) }
            VStack(alignment: .leading, spacing: 4) {
                if !parts.reasoning.isEmpty {
                    ThinkingDisclosure(reasoning: parts.reasoning,
                                       duration: reasoningDuration,
                                       inProgress: parts.isThinking)
                }
                if let toolName, !toolName.isEmpty {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("正在调用工具：\(toolName)")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                if !parts.response.isEmpty {
                    MarkdownMessageText(source: parts.response, showsCursor: true)
                        .font(.system(size: 13.5))
                        .textSelection(.enabled)
                } else if parts.reasoning.isEmpty && toolName == nil {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("正在思考…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 640, alignment: .leading)
            Spacer(minLength: 30)
        }
    }
}

private struct ThinkingDisclosure: View {
    let reasoning: String
    let duration: Double
    let inProgress: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            MarkdownMessageText(source: reasoning)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 5)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text(title)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        if inProgress { return "思考中…" }
        guard duration > 0 else { return "思考过程" }
        if duration < 60 { return String(format: "思考了 %.1f 秒", duration) }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "思考了 \(minutes) 分 \(seconds) 秒"
    }
}
