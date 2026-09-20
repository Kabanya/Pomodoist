# Flutter always writes to <project>\build and keeps its compile cache in
# <project>\.dart_tool. Both has to be junctions to the repository-root build
# directory. Git for Windows checks the tracked symlinks out as plain files, so
# every entry point repairs the paths before Flutter runs.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$links = @(
    @{
        Path = Join-Path $repoRoot 'apps\flutter\build'
        Target = Join-Path $repoRoot 'build\flutter'
    },
    @{
        Path = Join-Path $repoRoot 'apps\flutter\.dart_tool'
        Target = Join-Path $repoRoot 'build\dart_tool'
    }
)

foreach ($link in $links) {
    New-Item -ItemType Directory -Force -Path $link.Target | Out-Null
    if (Test-Path -LiteralPath $link.Path) {
        $item = Get-Item -LiteralPath $link.Path -Force
        if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $link.Path -Recurse -Force
        }
    } elseif ([System.IO.File]::Exists($link.Path)) {
        Remove-Item -LiteralPath $link.Path -Force
    }
    if (-not (Test-Path -LiteralPath $link.Path)) {
        try {
            New-Item -ItemType Junction -Path $link.Path -Target $link.Target | Out-Null
        } catch {
            cmd /c rmdir "$($link.Path)" 2>$null
            New-Item -ItemType Junction -Path $link.Path -Target $link.Target | Out-Null
        }
    }
}
