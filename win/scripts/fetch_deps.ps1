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

# webview/webview.h
Download 'https://raw.githubusercontent.com/nlopstad/webview/webview-0.10.0/webview/webview.h' `
         (Join-Path $tp 'webview\include\webview\webview.h')

# SQLite amalgamation
$sVer = '3.46.1'
$url = "https://www.sqlite.org/2024/sqlite-amalgamation-$($sVer -replace '\.','' ).zip"
# 更稳: 走 sqlite-org 固定 URL
$sUrl = "https://sqlite.org/2024/sqlite-amalgamation-3460100.zip"
Download $sUrl (Join-Path $tp '_sqlite.zip')
Expand-Archive -Path (Join-Path $tp '_sqlite.zip') -DestinationPath (Join-Path $tp 'sqlite_tmp') -Force
Copy-Item (Join-Path $tp 'sqlite_tmp\*.c') (Join-Path $tp 'sqlite\') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $tp 'sqlite_tmp\*.h') (Join-Path $tp 'sqlite\') -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $tp 'sqlite_tmp')
Remove-Item -Force (Join-Path $tp '_sqlite.zip')

Write-Host ""
Write-Host "Done. Deps in $tp" -ForegroundColor Green
Get-ChildItem $tp -Recurse -File | Select-Object FullName
