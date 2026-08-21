import SwiftUI

// MARK: - 编辑区（右主区）：大纲 + 章节正文

struct EditorView: View {
    @EnvironmentObject var app: AppState
    @State private var showOutline = true

    private var currentChapter: Chapter? {
        app.chapters.first { $0.id == app.selectedChapterID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let c = currentChapter {
                header(c)
                Divider()
                outlineSection
                Divider()
                editor
                Divider()
                footer(c)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(app.currentNovelID == nil ? "请在左侧选择或新建作品" : "暂无章节，点击侧栏「＋ 新章节」")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: 顶栏

    private func header(_ c: Chapter) -> some View {
        HStack(spacing: 10) {
            Text("第 \(c.no) 章")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
            TextField("章节标题", text: titleBinding(c))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("\(c.content.count) 字")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: 大纲

    private var outlineSection: some View {
        DisclosureGroup(isExpanded: $showOutline) {
            TextEditor(text: outlineBinding)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 70, maxHeight: 190)
        } label: {
            Label("故事大纲", systemImage: "map")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var outlineBinding: Binding<String> {
        Binding(
            get: { app.novels.first { $0.id == app.currentNovelID }?.outline ?? "" },
            set: { app.novelOutlineEdited($0) }
        )
    }

    // MARK: 正文

    private var editor: some View {
        TextEditor(text: contentBinding(currentChapter!))
            .font(.system(size: 14.5))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentBinding(_ c: Chapter) -> Binding<String> {
        Binding(
            get: { app.chapters.first { $0.id == c.id }?.content ?? "" },
            set: { app.chapterEdited(content: $0) }
        )
    }

    private func titleBinding(_ c: Chapter) -> Binding<String> {
        Binding(
            get: { app.chapters.first { $0.id == c.id }?.title ?? "" },
            set: { app.chapterEdited(title: $0) }
        )
    }

    // MARK: 状态栏

    private func footer(_ c: Chapter) -> some View {
        HStack {
            Text("\(c.content.count) 字")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Text("自动保存 · 右键章节可排序")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.ultraThinMaterial)
    }
}
