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
        .background(Color.clear)
    }

    private func icon(for tab: SidebarTab) -> String {
        switch tab {
        case .books: return "folder"
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
    @State private var sidebarWidth: CGFloat = 220

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let sidebarFits = width >= 720
            let assistantFits = width >= 900
            let minimumMainWidth: CGFloat = assistantFits ? 662 : 340
            let maximumSidebarWidth = max(160, min(300, width - 42 - minimumMainWidth))
            let resolvedSidebarWidth = min(max(sidebarWidth, 160), maximumSidebarWidth)

            ZStack {
                DefaultBackgroundView()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                HStack(alignment: .top, spacing: 0) {
                    ActivityBar(isSidebarPresented: $isSidebarPresented)
                        .frame(height: geometry.size.height)
                    if isSidebarPresented && sidebarFits {
                        SidebarView()
                            .frame(width: resolvedSidebarWidth, height: geometry.size.height)
                        HorizontalResizeDivider(
                            width: $sidebarWidth,
                            minimum: 160,
                            maximum: maximumSidebarWidth
                        )
                    }
                    MainArea(
                        isAssistantPresented: $isAssistantPresented,
                        assistantFits: assistantFits
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $app.showSettings) { SettingsSheet() }
        .sheet(isPresented: $app.showEntrySheet) { EntrySheet() }
        .sheet(isPresented: $app.showAgentSheet) { AgentSheet() }
        .sheet(isPresented: $app.showSkillManager) { SkillManagerSheet() }
        .confirmationDialog("删除当前书籍？其下所有章节、设定、对话与会话将一并删除。",
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
                Button("公共会话 · 不选择书籍") { app.selectNoNovel() }
                Divider()
                ForEach(app.novels) { n in
                    Button(n.title) { app.selectNovel(n.id) }
                }
                Divider()
                Button("新建书籍") {
                    app.sidebarTab = .books
                    isSidebarPresented = true
                }
                Button("导入书籍…") { app.importBook() }
                if app.currentNovelID != nil {
                    Button("导出当前书籍…") { app.exportCurrentBook() }
                    Divider()
                    Button("删除当前书籍", role: .destructive) { app.confirmDeleteNovel = true }
                }
            } label: {
                Label(app.novels.first { $0.id == app.currentNovelID }?.title ?? "选择作品",
                      systemImage: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
            }
            .help("选择与管理书籍")
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
                Label("写作工具", systemImage: "sparkles")
            }
            .disabled(app.selectedChapterID == nil)
            .help("对当前章节执行写作操作")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isAssistantPresented.toggle()
            } label: {
                Label(isAssistantPresented ? "收起对话" : "展开对话",
                      systemImage: "bubble.left.and.bubble.right")
            }
            .help(isAssistantPresented ? "收起对话" : "展开对话")
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

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mpeg", "mpg"
    ]

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DefaultBackground", withExtension: "jpeg") else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.cacheMode = .always
        return image
    }()

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let customURL, Self.videoExtensions.contains(customURL.pathExtension.lowercased()) {
                BackgroundVideoView(url: customURL)
                    .opacity(app.config.backgroundOpacity)
                    .overlay(Color.black.opacity(0.12))
                    .clipped()
            } else if let customURL, let customImage = NSImage(contentsOf: customURL) {
                Image(nsImage: customImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(app.config.backgroundOpacity)
                    .overlay(Color.black.opacity(0.12))
                    .clipped()
            } else if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(app.config.backgroundOpacity)
                    .overlay(Color.black.opacity(0.12))
                    .clipped()
            }
            // 所有工作区共用这一层遮罩，页面和分栏不得重复叠加底色。
            Color(nsColor: .textBackgroundColor).opacity(0.26)
        }
    }

    private var customURL: URL? {
        guard !app.config.backgroundMediaPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: app.config.backgroundMediaPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - 主区域：对话 | 编辑（可拖拽分割）

struct MainArea: View {
    @EnvironmentObject var app: AppState
    @Binding var isAssistantPresented: Bool
    let assistantFits: Bool
    @State private var assistantWidth: CGFloat = 420

    var body: some View {
        Group {
            if app.sidebarTab == .vectors {
                VectorWorkspaceView()
            } else {
                GeometryReader { geometry in
                    let maximumAssistantWidth = max(320, min(520, geometry.size.width - 341))
                    let resolvedAssistantWidth = min(max(assistantWidth, 320), maximumAssistantWidth)

                    Group {
                        if isAssistantPresented && !assistantFits {
                            // 窄窗口下让对话区独占主区域，否则状态虽已展开却仍不可见。
                            ChatView(isPresented: $isAssistantPresented)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HStack(spacing: 0) {
                                if isAssistantPresented {
                                    ChatView(isPresented: $isAssistantPresented)
                                        .frame(width: resolvedAssistantWidth, height: geometry.size.height)
                                    HorizontalResizeDivider(
                                        width: $assistantWidth,
                                        minimum: 320,
                                        maximum: maximumAssistantWidth
                                    )
                                }
                                EditorView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .overlay(alignment: .topLeading) {
                                if !isAssistantPresented {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            isAssistantPresented = true
                                        }
                                    } label: {
                                        Label("展开对话", systemImage: "bubble.left.and.bubble.right")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .padding(10)
                                    .help("展开对话")
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - 可拖拽分隔条

struct HorizontalResizeDivider: View {
    @Binding var width: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = width }
                        width = min(max((dragStart ?? width) + value.translation.width, minimum), maximum)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .help("拖拽调整宽度")
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
