import SwiftUI
import AppKit

// MARK: - 活动栏

struct ActivityBar: View {
    @EnvironmentObject var app: AppState
    @Binding var isSidebarPresented: Bool

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Button {
                    if app.sidebarTab == tab {
                        isSidebarPresented.toggle()
                    } else {
                        app.sidebarTab = tab
                        isSidebarPresented = true
                    }
                } label: {
                    Image(systemName: icon(for: tab))
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 30)
                        .background(app.sidebarTab == tab ? Color.accentColor.opacity(0.28) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(app.sidebarTab == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 42)
        .background(.ultraThinMaterial)
    }

    private func icon(for tab: SidebarTab) -> String {
        switch tab {
        case .chapters: return "doc.text"
        case .lore: return "books.vertical"
        case .search: return "magnifyingglass"
        case .vectors: return "cube.transparent"
        case .conversations: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - 主布局

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var isSidebarPresented = true
    @State private var isAssistantPresented = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let sidebarFits = width >= 720
            let assistantFits = width >= 860

            HStack(alignment: .top, spacing: 0) {
                ActivityBar(isSidebarPresented: $isSidebarPresented)
                    .frame(height: geometry.size.height)
                HSplitView {
                    if isSidebarPresented && sidebarFits {
                        SidebarView()
                            .frame(minWidth: 160, idealWidth: 220, maxWidth: 300, maxHeight: .infinity)
                    }
                    MainArea(
                        isAssistantPresented: $isAssistantPresented,
                        assistantFits: assistantFits
                    )
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(
                    width: max(0, geometry.size.width - 42),
                    height: geometry.size.height,
                    alignment: .top
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .background { DefaultBackgroundView() }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $app.showSettings) { SettingsSheet() }
        .sheet(isPresented: $app.showEntrySheet) { EntrySheet() }
        .sheet(isPresented: $app.showAgentSheet) { AgentSheet() }
        .sheet(isPresented: $app.showSkillManager) { SkillManagerSheet() }
        .confirmationDialog("删除当前作品？其下所有章节、设定、对话与会话将一并删除。",
                            isPresented: $app.confirmDeleteNovel, titleVisibility: .visible) {
            Button("删除", role: .destructive) { app.deleteNovel() }
            Button("取消", role: .cancel) {}
        }
        .overlay(alignment: .bottom) { ToastView() }
    }

    // MARK: 顶部工具栏（全局功能集成）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                ForEach(app.novels) { n in
                    Button(n.title) { app.selectNovel(n.id) }
                }
                Divider()
                Button("新建作品") { app.createNovel() }
                if app.currentNovelID != nil {
                    Divider()
                    Button("删除当前作品", role: .destructive) { app.confirmDeleteNovel = true }
                }
            } label: {
                Label(app.novels.first { $0.id == app.currentNovelID }?.title ?? "选择作品",
                      systemImage: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
            }
            .help("切换 / 新建 / 删除作品")
            .fixedSize()

            Button {
                app.createChapter()
            } label: {
                Label("新章节", systemImage: "plus.square.on.square")
            }
            .help("新建章节（⌘⇧N）")

            Button {
                app.createConversation()
            } label: {
                Label("新对话", systemImage: "bubble.left.and.bubble.right")
            }
            .help("新建对话（⌥⌘N）")

            Menu {
                Button {
                    app.runAISkill("continue")
                } label: {
                    Label("续写正文", systemImage: "square.and.pencil")
                }
                Button {
                    app.runAISkill("polish")
                } label: {
                    Label("润色本章", systemImage: "sparkles")
                }
                Button {
                    app.runAISkill("consistency")
                } label: {
                    Label("一致性检查", systemImage: "checkmark.seal")
                }
                Divider()
                Button {
                    app.runAISkill("outline")
                } label: {
                    Label("生成大纲", systemImage: "map")
                }
            } label: {
                Label("AI 操作", systemImage: "sparkles")
            }
            .disabled(app.selectedChapterID == nil)
            .help("对当前章节执行 AI 操作")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if let plan = app.lastPlan {
                Text("≈\(plan.totalTokens)t/\(app.config.contextWindow)t")
                    .font(.system(size: 10.5)).monospacedDigit()
                    .foregroundStyle(plan.totalTokens > app.config.contextWindow * 8 / 10 ? Color.orange : Color.secondary)
                    .help("上次请求注入 tokens / 上下文窗口上限")
            }
            Button {
                isAssistantPresented.toggle()
            } label: {
                Label(isAssistantPresented ? "收起 AI 助手" : "展开 AI 助手",
                      systemImage: "sidebar.trailing")
            }
            .help(isAssistantPresented ? "收起 AI 助手" : "展开 AI 助手")
            Button {
                app.showAgentSheet = true
            } label: {
                Label("Agent", systemImage: "person.crop.circle")
            }
            .help("Agent 管理（自定义系统提示词）")
            Button {
                app.showSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .help("设置（⌘,）")
        }
    }
}

// MARK: - 默认背景

private struct DefaultBackgroundView: View {
    @EnvironmentObject var app: AppState

    private let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DefaultBackground", withExtension: "jpeg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(app.config.backgroundOpacity)
                    .overlay(Color.black.opacity(0.12))
                    .clipped()
            }
        }
    }
}

// MARK: - 主区域：对话 | 编辑（可拖拽分割）

struct MainArea: View {
    @EnvironmentObject var app: AppState
    @Binding var isAssistantPresented: Bool
    let assistantFits: Bool

    var body: some View {
        Group {
            if app.sidebarTab == .vectors {
                VectorWorkspaceView()
            } else {
                HSplitView {
                    if isAssistantPresented && assistantFits {
                        ChatView(isPresented: $isAssistantPresented)
                            .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
                    }
                    EditorView()
                        .frame(minWidth: 340, idealWidth: 680, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.26))
    }
}

// MARK: - Toast

struct ToastView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let t = app.toastText {
            Text(t)
                .font(.system(size: 12.5))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
                .shadow(radius: 8, y: 3)
                .padding(.bottom, 14)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        if app.toastText == t { withAnimation { app.toastText = nil } }
                    }
                }
        }
    }
}
