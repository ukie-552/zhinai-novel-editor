cmake_minimum_required(VERSION 3.20)
project(zhinai_novel_editor_win LANGUAGES C CXX)

# ---------------------------------------------------------------------------
#  织奈编辑器 Windows 移植版 (C++ + WebView2)
#  - HTTP server (cpp-httplib, 单头文件)
#  - JSON (nlohmann/json, 单头文件)
#  - SQLite (amalgamation, 直接编译进去)
#  - LLM 客户端: WinHTTP (Windows SDK 自带, 不需要 libcurl)
#  - GUI: WebView2 via webview/webview.h (单头文件, 运行时只依赖 WebView2Loader.dll)
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE OFF)

if(MSVC)
    add_compile_options(/W3 /utf-8 /permissive- /EHsc)
    # WIN32_LEAN_AND_MEAN / NOMINMAX 由 webview.h 自己 define, 这里不重复
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

set(APP_NAME "zhinai_editor")

# ---------------------------------------------------------------------------
#  Single-header deps
# ---------------------------------------------------------------------------
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# 已经在 win/third_party 里以单头文件方式提供, 这里只做可选校验.
# 想要自动拉取可以打开:
#   option(ZHINAI_FETCH_DEPS "Fetch single-header deps" ON)
#   if(ZHINAI_FETCH_DEPS)
#       FetchContent_Declare(cpp-httplib URL https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.15.3/httplib.h)
#       FetchContent_Declare(json URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp)
#       FetchContent_Declare(webview URL https://raw.githubusercontent.com/nlopstad/webview/webview-0.10.0/webview/webview.h)
#   endif()

# ---------------------------------------------------------------------------
#  SQLite amalgamation
#  从 SQLite 官网下载 amalgamation (sqlite3.c + sqlite3.h), 放到 third_party/sqlite
#  链接时直接 .c 编进 EXE, 无需 DLL.
# ---------------------------------------------------------------------------
set(SQLITE_DIR ${CMAKE_SOURCE_DIR}/third_party/sqlite)
set(ZHINAI_HAS_SQLITE OFF)
if(EXISTS ${SQLITE_DIR}/sqlite3.c)
    add_library(sqlite3 STATIC ${SQLITE_DIR}/sqlite3.c)
    target_include_directories(sqlite3 PUBLIC ${SQLITE_DIR})
    target_compile_definitions(sqlite3 PUBLIC SQLITE_THREADSAFE=1 SQLITE_ENABLE_FTS5)
    set(ZHINAI_HAS_SQLITE ON)
else()
    message(WARNING "SQLite amalgamation not found in ${SQLITE_DIR}. "
                    "Download sqlite-amalgamation from https://www.sqlite.org/amalgamation.html "
                    "and place sqlite3.c + sqlite3.h there. DB features will be stubbed.")
    add_library(sqlite3 INTERFACE)
endif()

# ---------------------------------------------------------------------------
#  Main executable
# ---------------------------------------------------------------------------
file(GLOB APP_SOURCES CONFIGURE_DEPENDS
    ${CMAKE_SOURCE_DIR}/src/*.cpp
)
# 永远排除 db_stub.cpp - 它只在 SQLite 不可用时才加回来
list(REMOVE_ITEM APP_SOURCES ${CMAKE_SOURCE_DIR}/src/db_stub.cpp)

if(ZHINAI_HAS_SQLITE)
    add_executable(${APP_NAME} WIN32 ${APP_SOURCES})
    set_target_properties(${APP_NAME} PROPERTIES OUTPUT_NAME "织奈编辑器")
    target_compile_definitions(${APP_NAME} PRIVATE ZHINAI_HAS_SQLITE=1)
else()
    # SQLite 不可用, 用 db_stub 替换 db.cpp
    list(REMOVE_ITEM APP_SOURCES ${CMAKE_SOURCE_DIR}/src/db.cpp)
    add_executable(${APP_NAME} WIN32 ${APP_SOURCES} ${CMAKE_SOURCE_DIR}/src/db_stub.cpp)
    set_target_properties(${APP_NAME} PROPERTIES OUTPUT_NAME "织奈编辑器")
endif()

target_include_directories(${APP_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/third_party
    ${CMAKE_SOURCE_DIR}/third_party/cpp-httplib
    ${CMAKE_SOURCE_DIR}/third_party/nlohmann
    ${CMAKE_SOURCE_DIR}/third_party/webview/include
    ${CMAKE_SOURCE_DIR}/third_party/webview2/native/include
)

# WebView2Loader 静态链: 用 .lib 即可, 不需要 .dll 跟 EXE
set(WEBVIEW2_LIB ${CMAKE_SOURCE_DIR}/third_party/webview2/native/x64/WebView2LoaderStatic.lib)

target_link_libraries(${APP_NAME} PRIVATE
    sqlite3
    # Windows libs
    user32
    gdi32
    comdlg32
    ole32
    oleaut32
    shell32
    advapi32
    crypt32
    winhttp
    webservices
    # WebView2 (静态)
    ${WEBVIEW2_LIB}
)

# ---------------------------------------------------------------------------
#  Post-build: 把 web/ 复制到 EXE 同目录, windeployqt 之类的由 scripts/build.bat 单独跑
# ---------------------------------------------------------------------------
add_custom_command(TARGET ${APP_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/web
        $<TARGET_FILE_DIR:${APP_NAME}>/web
)

# ---------------------------------------------------------------------------
#  Install
# ---------------------------------------------------------------------------
install(TARGETS ${APP_NAME} RUNTIME DESTINATION .)
install(DIRECTORY web DESTINATION .)
