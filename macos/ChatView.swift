import SwiftUI

// MARK: - AI 助手：会话切换 + 与 Agent 对话

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @Binding var isPresented: Bool
    @State private var showsOutputUsage = false

    private var skill: Skill { skillByID(app.skillID, skills: app.skills) }

    private var currentConversation: Conversation? {
        app.conversations.first { $0.id == app.currentConversationID }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsHeader
            Divider()
            messageList
            Divider()
            inputBar
        }
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
                    Image(systemName: app.currentAgent.icon)
                        .font(.system(size: 10))
                    Text(app.currentAgent.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Agent：自定义系统提示词人格")

            Menu {
                let skills = app.availableSkills
                ForEach(SkillCategory.allCases) { cat in
                    let favs = skills.filter { $0.category == cat && app.config.favoriteSkills.contains($0.id) }
                    let others = skills.filter { $0.category == cat && !app.config.favoriteSkills.contains($0.id) }
                    if !favs.isEmpty || !others.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(favs) { s in skillItem(s) }
                            ForEach(others) { s in skillItem(s) }
                        }
                    }
                }
                Divider()
                Button("管理 Markdown Skills…") { app.showSkillManager = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: skill.icon)
                    Text(skill.name)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
                .help("选择或管理 Markdown Skills")
            Spacer()
            if app.streaming {
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
            Button {
                isPresented = false
            } label: {
                Image(systemName: "sidebar.trailing")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("收起对话区")
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

    @ViewBuilder
    private func skillItem(_ s: Skill) -> some View {
        Button {
            app.skillID = s.id
        } label: {
            if s.id == app.skillID {
                Label(s.name, systemImage: "checkmark")
            } else {
                Text(s.name)
            }
        }
    }

    // MARK: 消息列表

    private var messageList: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                    ForEach(app.messages) { m in
                        MessageRow(msg: m)
                            .id(m.id)
                    }
                    if app.streaming {
                        StreamingRow(text: app.streamingText)
                            .id("streaming")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .onChange(of: app.messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: app.streaming) { streaming in
                    if streaming { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            if app.messages.isEmpty && !app.streaming {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("选择 Agent 与技能开始创作\n或新建一个对话")
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
                Text("⌘⏎ 发送 · ⌥⌘N 新对话 · ⌘S 保存")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                if app.streaming {
                    Button("停止") { app.stopStreaming() }
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
        let tokens = showsOutputUsage ? outputTokens : inputTokens
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
                    Text("\(tokenText(tokens)) / \(tokenText(limit)) token")
                        .monospacedDigit()
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
        .help("点击切换输入上下文与本轮输出用量")
    }

    /// 输入使用最近一次实际组装的上下文；还未发送时用会话历史估算。
    private var inputTokens: Int {
        let history = app.messages.map(\.content).joined(separator: "\n")
        let sentContext = app.lastPlan?.totalTokens
            ?? (history.isEmpty ? 0 : estimateTokens(history))
        let draftTokens = app.draft.isEmpty ? 0 : estimateTokens(app.draft)
        return sentContext + draftTokens
    }

    /// API 流式结束前显示实时输出；结束后显示本次最后一条 AI 回复。
    private var outputTokens: Int {
        if app.streaming { return estimateTokens(app.streamingText) }
        let latestOutput = app.messages.last { $0.role == "assistant" }?.content ?? ""
        return latestOutput.isEmpty ? 0 : estimateTokens(latestOutput)
    }

    private var outputLimit: Int {
        app.currentAgent.maxTokens ?? app.config.maxTokens
    }

    private func tokenText(_ tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        let value = Double(tokens) / 1_000
        return value >= 10 ? String(format: "%.0fk", value) : String(format: "%.1fk", value)
    }

    /// 只有在可以实际调用的模型已配置时，才展示这个模型的 token 预算。
    private var hasUsableModel: Bool {
        !app.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (app.config.provider == "ollama"
                || !app.config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canSend: Bool {
        !app.streaming && !app.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 消息气泡

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
                avatar
            }
        }
    }

    private var avatar: some View {
        Image(systemName: msg.role == "assistant" ? "book.closed.fill" : "person.fill")
            .font(.system(size: 11))
            .frame(width: 26, height: 26)
            .background(msg.role == "assistant" ? Color.accentColor.opacity(0.25) : Color.green.opacity(0.2),
                        in: Circle())
            .foregroundStyle(msg.role == "assistant" ? Color.accentColor : Color.green)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if msg.role == "assistant" && !msg.skill.isEmpty && msg.skill != "chat" {
                Text(skillByID(msg.skill, skills: app.skills).name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(msg.content)
                .font(.system(size: 13.5))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(msg.role == "user" ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 640, alignment: msg.role == "user" ? .trailing : .leading)
    }
}

// MARK: - 流式输出行

struct StreamingRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.25), in: Circle())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.isEmpty ? "思考中…" : text + "▌")
                    .font(.system(size: 13.5))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 640, alignment: .leading)
            Spacer(minLength: 30)
        }
    }
}
