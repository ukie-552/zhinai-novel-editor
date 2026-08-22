// platform.h - 路径、文件系统、Win32 工具
#pragma once
#include <string>
#include <filesystem>

namespace zhinai::platform {

// 应用数据目录: %APPDATA%/ZhinaiNovelEditor/
// 与 macOS 版数据目录命名一致, 方便以后跨平台迁移.
std::filesystem::path dataDir();

// 数据目录下的子路径
std::filesystem::path dbPath();
std::filesystem::path configPath();
std::filesystem::path agentsPath();
std::filesystem::path vectorsPath();

// 写日志到 %APPDATA%/ZhinaiNovelEditor/logs/app.log
void log(const std::string& level, const std::string& msg);

// EXE 所在目录, 用于定位 web/ 静态资源
std::filesystem::path exeDir();

// 在 Win10 任务栏/标题显示的窗口标题
const char* kAppTitle();

}  // namespace zhinai::platform
