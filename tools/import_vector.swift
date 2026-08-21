import Foundation

@main
struct VectorImport {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fputs("用法: import_vector <TXT 路径> [期望章节数]\n", stderr)
            exit(1)
        }
        let url = URL(fileURLWithPath: arguments[1])
        let expected = arguments.count >= 3 ? Int(arguments[2]) : nil
        do {
            let library = try VectorStore().importTXT(url: url, expectedChapterCount: expected)
            print("已创建向量库：\(library.title)（\(library.chapterCount) 章，\(library.chunkCount) 个片段）")
        } catch {
            fputs("导入失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
