import SwiftUI

@main
struct ZhinaiNovelEditorApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .tint(app.config.tintColor)
                .frame(minWidth: 680, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建书籍") { app.createNovel() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("写作") {
                Button("保存章节") { app.flushSave() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("发送消息") { app.sendMessage() }
                    .keyboardShortcut(.return, modifiers: .command)
                Divider()
                Button("新建章节") { app.createChapter() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("删除当前章节") { app.deleteChapter() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("清空对话") { app.clearMessages() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { app.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
