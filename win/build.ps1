# build.ps1 - 在 x64 Native Tools Command Prompt for VS 2022 跑, 或者从 PowerShell 自动激活环境
$ErrorActionPreference = 'Stop'

# 找 vcvars64.bat
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere not found, install VS Build Tools 2022 first" }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "no VS 2022 instance with C++ tools found" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

# 拼一段在 vcvars64 环境里跑的 cmake 命令
$cmd = "call `"$vcvars`" && cd /d `"$root`" && cmake -S . -B build -A x64 -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release"
cmd.exe /c $cmd
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Write-Host ""
Write-Host "OK: $build\Release\织奈编辑器.exe" -ForegroundColor Green
