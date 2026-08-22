// platform.cpp
#include "platform.h"
#include <shlobj.h>
#include <windows.h>
#include <fstream>
#include <iostream>
#include <mutex>
#include <sstream>

namespace zhinai::platform {

namespace {
std::mutex g_logMutex;

std::filesystem::path appendData(const std::string& leaf) {
    auto dir = dataDir();
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    auto p = dir / leaf;
    return p;
}
}  // namespace

std::filesystem::path dataDir() {
    // CSIDL_APPDATA -> %APPDATA%/Roaming (与 macOS 的 Application Support 对齐)
    PWSTR raw = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &raw))) {
        std::filesystem::path p(raw);
        CoTaskMemFree(raw);
        return p / "ZhinaiNovelEditor";
    }
    // fallback: 临时目录
    char buf[MAX_PATH]{};
    if (GetTempPathA(MAX_PATH, buf)) {
        return std::filesystem::path(buf) / "ZhinaiNovelEditor";
    }
    return std::filesystem::current_path() / "ZhinaiNovelEditor";
}

std::filesystem::path dbPath() { return appendData("novels.db"); }
std::filesystem::path configPath() { return appendData("config.json"); }
std::filesystem::path agentsPath() { return appendData("agents.json"); }
std::filesystem::path vectorsPath() { return appendData("vectors.db"); }

std::filesystem::path exeDir() {
    char buf[MAX_PATH]{};
    if (GetModuleFileNameA(nullptr, buf, MAX_PATH) > 0) {
        return std::filesystem::path(buf).parent_path();
    }
    return std::filesystem::current_path();
}

void log(const std::string& level, const std::string& msg) {
    std::lock_guard<std::mutex> lk(g_logMutex);
    auto p = appendData("logs");
    std::error_code ec;
    std::filesystem::create_directories(p, ec);
    auto fp = p / "app.log";
    std::ofstream f(fp, std::ios::app);
    if (!f) return;
    SYSTEMTIME st;
    GetLocalTime(&st);
    char ts[32];
    std::snprintf(ts, sizeof(ts), "%04d-%02d-%02d %02d:%02d:%02d",
                  st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    f << ts << " [" << level << "] " << msg << "\n";
}

const char* kAppTitle() { return "织奈编辑器"; }

}  // namespace zhinai::platform
