# build.ps1 - 在 x64 Native Tools Command Prompt for VS 2022 跑, 或者从 PowerShell 自动激活环境
$ErrorActionPreference = 'Stop'

# 1) 找 vcvars64.bat
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere not found, install VS 2022 (含 C++ tools) first" }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "no VS 2022 instance with C++ tools found" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

$root = Split-Path -Parent $PSScriptRoot

# 2) 拷贝 assets -> win/web/img (背景图, 应用图标, Agent 头像)
$webImg = Join-Path $root 'web\img'
$agentsImg = Join-Path $webImg 'agents'
if (-not (Test-Path $webImg)) { New-Item -ItemType Directory -Force -Path $webImg | Out-Null }
if (-not (Test-Path $agentsImg)) { New-Item -ItemType Directory -Force -Path $agentsImg | Out-Null }
Copy-Item -Force (Join-Path $root '..\assets\DefaultBackground.jpeg') $webImg
Copy-Item -Force (Join-Path $root '..\assets\AppIcon.png') $webImg
Get-ChildItem (Join-Path $root '..\assets\AgentAvatars') -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -Force $_.FullName $agentsImg
}

# 3) cmake configure + build
$build = Join-Path $root 'build'
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Force -Path $build | Out-Null }

$cmd = "call `"$vcvars`" && cd /d `"$root`" && cmake -S . -B build -A x64 && cmake --build build --config Release"
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Write-Host ""
Write-Host "OK: $build\Release\织奈编辑器.exe" -ForegroundColor Green
