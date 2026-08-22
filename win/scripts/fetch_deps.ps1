# fetch_deps.ps1 - 拉单头文件依赖到 third_party\
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$tp = Join-Path $root 'third_party'
New-Item -ItemType Directory -Force -Path $tp | Out-Null

function Download($url, $out) {
    $dir = Split-Path -Parent $out
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Host "-> $out"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

# cpp-httplib
Download 'https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.15.3/httplib.h' `
         (Join-Path $tp 'cpp-httplib\httplib.h')

# nlohmann/json (single header)
Download 'https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp' `
         (Join-Path $tp 'nlohmann\json.hpp')

# webview/webview.h (仓库已从 nicbarker/webview 迁到 webview/webview, 用 0.10.0 tag 拿单头)
Download 'https://raw.githubusercontent.com/webview/webview/0.10.0/webview.h' `
         (Join-Path $tp 'webview\include\webview\webview.h')

# SQLite amalgamation (从 https://www.sqlite.org/download.html 找当前版本)
# 3.46.1 -> 文件名 sqlite-amalgamation-3460100.zip (zip 内含 sqlite-amalgamation-3460100/ 子目录)
$sUrl = 'https://sqlite.org/2024/sqlite-amalgamation-3460100.zip'
Download $sUrl (Join-Path $tp '_sqlite.zip')
$ext = Join-Path $tp 'sqlite_extract'
if (Test-Path $ext) { Remove-Item -Recurse -Force $ext }
Expand-Archive -Path (Join-Path $tp '_sqlite.zip') -DestinationPath $ext -Force
$sqlite = Join-Path $tp 'sqlite'
if (Test-Path $sqlite) { Remove-Item -Recurse -Force $sqlite }
New-Item -ItemType Directory -Force -Path $sqlite | Out-Null
Get-ChildItem $ext -Recurse -File | Where-Object { $_.Name -in 'sqlite3.c','sqlite3.h' } | ForEach-Object {
    Copy-Item $_.FullName $sqlite -Force
}
Remove-Item -Recurse -Force $ext
Remove-Item -Force (Join-Path $tp '_sqlite.zip')

# WebView2 SDK (NuGet Microsoft.Web.WebView2)
# webview 库 0.10.0 的 Windows 后端强制依赖, 拿 .h 头和 .lib/.dll
Download 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2' (Join-Path $tp '_webview2.nupkg')
$wv2 = Join-Path $tp 'webview2_extract'
if (Test-Path $wv2) { Remove-Item -Recurse -Force $wv2 }
New-Item -ItemType Directory -Force -Path $wv2 | Out-Null
# .nupkg 实际是 zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $tp '_webview2.nupkg'), $wv2)
$wv2root = Join-Path $wv2 'build\native'
$wv2dst = Join-Path $tp 'webview2'
if (Test-Path $wv2dst) { Remove-Item -Recurse -Force $wv2dst }
New-Item -ItemType Directory -Force -Path $wv2dst | Out-Null
Copy-Item -Recurse $wv2root "$wv2dst\" -Force
Remove-Item -Recurse -Force $wv2
Remove-Item -Force (Join-Path $tp '_webview2.nupkg')

Write-Host ""
Write-Host "Done. Deps in $tp" -ForegroundColor Green
Get-ChildItem $tp -Recurse -File | Select-Object FullName
