# Flutter always writes to <project>\build and keeps its compile cache in
# <project>\.dart_tool. Both have to be junctions to the repository-root build
# directory, so every generated artifact lands under build/ and nothing is left
# next to the sources.
#
# The links cannot be tracked in Git: the repository-root build/ directory is
# ignored, so a fresh checkout would restore dangling links that Flutter cannot
# create or remove. Every entry point therefore repairs the paths before
# Flutter runs. Git Bash cannot create junctions, so Windows delegates to this
# script; other platforms use tool/link-build.sh.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'flavors.ps1')

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
    Set-PomodoistReparsePoint -Path $link.Path -Target $link.Target -Junction
}
