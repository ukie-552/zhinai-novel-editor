import Foundation
import Darwin

enum ServerStatus {
    case starting
    case running(port: Int)
    case failed(String)
}

/// 管理内置 Node 服务的生命周期：查找 node、选择空闲端口、启动、监听就绪、退出时停止。
final class ServerManager {
    var onStatus: ((ServerStatus) -> Void)?
    private var process: Process?
    private var port = 8090

    // MARK: - Node 查找

    private func findNode() -> String? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["AINOVEL_NODE"],
           fm.isExecutableFile(atPath: env) {
            return env
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) { return c }

        // nvm 安装的 node（按版本号取最新）
        let home = fm.homeDirectoryForCurrentUser.path
        let nvmDir = home + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir).sorted(by: >) {
            for v in versions {
                let p = nvmDir + "/" + v + "/bin/node"
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }

        // PATH 兜底
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let p = String(dir) + "/node"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - 端口

    private func isPortFree(_ p: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return true }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(p).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r != 0 // connect 失败 = 端口空闲
    }

    private func freePort(start: Int) -> Int {
        for p in start...(start + 20) where isPortFree(p) { return p }
        return start
    }

    // MARK: - 生命周期

    func start() {
        guard let node = findNode() else {
            onStatus?(.failed("未找到 Node.js。请先安装 Node.js（https://nodejs.org）后重新打开本应用。"))
            return
        }
        guard let resources = Bundle.main.resourceURL else {
            onStatus?(.failed("应用资源缺失，请重新构建。"))
            return
        }
        let webDir = resources.appendingPathComponent("web").path
        guard FileManager.default.fileExists(atPath: webDir + "/server/index.js") else {
            onStatus?(.failed("内置服务文件缺失：\(webDir)"))
            return
        }

        port = freePort(start: 8090)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dataDir = home + "/Library/Application Support/AINovelWorkbench"
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = ["server/index.js", "--port", String(port), "--no-open"]
        proc.currentDirectoryURL = URL(fileURLWithPath: webDir)
        var env = ProcessInfo.processInfo.environment
        env["DATA_DIR"] = dataDir
        env["NO_OPEN"] = "1"
        env["READY_MARKER"] = "AINOVEL_READY_MARKER"
        proc.environment = env

        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        self.process = proc

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard let self = self, !d.isEmpty,
                  let s = String(data: d, encoding: .utf8),
                  s.contains("AINOVEL_READY_MARKER") else { return }
            DispatchQueue.main.async { self.onStatus?(.running(port: self.port)) }
        }

        do {
            try proc.run()
        } catch {
            onStatus?(.failed("启动内置服务失败：\(error.localizedDescription)"))
            return
        }

        // 兜底：4 秒后仍未就绪则检查进程状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, let p = self.process else { return }
            if p.isRunning {
                self.onStatus?(.running(port: self.port))
            } else {
                self.onStatus?(.failed("内置服务未能启动（Node.js 进程已退出）。"))
            }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
