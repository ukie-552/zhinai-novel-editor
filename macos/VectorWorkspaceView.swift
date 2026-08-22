import SwiftUI

struct VectorWorkspaceView: View {
    @EnvironmentObject var app: AppState
    @State private var chapterFilter = ""
    @State private var chapterListWidth: CGFloat = 270

    private var selectedLibrary: VectorLibrary? {
        app.vectorLibraries.first { $0.id == app.selectedVectorLibraryID }
    }

    private var filteredChapters: [VectorChapter] {
        let query = chapterFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return app.vectorChapters }
        if let number = Int(query) { return app.vectorChapters.filter { $0.no == number } }
        return app.vectorChapters.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if let library = selectedLibrary {
                GeometryReader { geometry in
                    let maximumListWidth = max(220, min(360, geometry.size.width - 461))
                    let resolvedListWidth = min(max(chapterListWidth, 220), maximumListWidth)

                    HStack(spacing: 0) {
                    chapterContainer(library)
                            .frame(width: resolvedListWidth, height: geometry.size.height)
                        HorizontalResizeDivider(
                            width: $chapterListWidth,
                            minimum: 220,
                            maximum: maximumListWidth
                        )
                    chapterDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                emptyLibrary
            }
        }
        .background(Color.clear)
    }

    private func chapterContainer(_ library: VectorLibrary) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                HStack {
                    Label("\(app.vectorChapters.count) 章", systemImage: "list.number")
                    Spacer()
                    Text("\(library.chunkCount) 向量片段")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            Divider()
            TextField("按章节号、标题或正文筛选…", text: $chapterFilter)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .padding(10)

            if app.vectorChapters.isEmpty {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26)).foregroundStyle(.tertiary)
                Text("此向量库没有可查看的原始章节\n请从左侧重新导入 TXT")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.top, 7)
                Spacer()
            } else {
                List(selection: $app.selectedVectorChapterID) {
                    ForEach(filteredChapters) { chapter in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(chapter.no)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            Text(chapter.title).font(.system(size: 12)).lineLimit(1)
                        }
                        .tag(chapter.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var chapterDetail: some View {
        if let chapter = app.vectorChapters.first(where: { $0.id == app.selectedVectorChapterID }) {
            VectorChapterEditor(chapter: chapter).id(chapter.id)
        } else {
            VStack(spacing: 9) {
                Image(systemName: "doc.text")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                Text("从左侧选择一个章节").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 38, weight: .light)).foregroundStyle(Color.accentColor)
            Text("选择一个向量库").font(.system(size: 14, weight: .semibold))
            Text("导入参考作品，提取匿名化写法画像，让文字表达更自然")
                .font(.caption).foregroundStyle(.secondary)
            Text("参考正文只保存在本地，不会作为续写内容直接注入模型")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VectorChapterEditor: View {
    @EnvironmentObject var app: AppState
    let chapter: VectorChapter
    @State private var title: String
    @State private var content: String
    @State private var isDirty = false

    init(chapter: VectorChapter) {
        self.chapter = chapter
        _title = State(initialValue: chapter.title)
        _content = State(initialValue: chapter.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("第 \(chapter.no) 章")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
                TextField("章节标题", text: $title)
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                Text("\(content.count) 字")
                    .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary)
                Button { save() } label: {
                    Label(isDirty ? "保存并重建向量" : "已保存",
                          systemImage: isDirty ? "arrow.triangle.2.circlepath" : "checkmark")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!isDirty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.ultraThinMaterial)
            Divider()
            TextEditor(text: $content)
                .font(.system(size: 14)).lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color.clear)
        }
        .onChange(of: title) { _ in isDirty = true }
        .onChange(of: content) { _ in isDirty = true }
    }

    private func save() {
        if app.saveVectorChapter(id: chapter.id, title: title, content: content) { isDirty = false }
    }
}
