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

    # An existing junction with the expected target is already correct. The
    # path has to be classified by its own entry rather than by what it
    # resolves to: a junction left behind by the old tracked links has a target
    # that does not exist, and Get-Item then fails outright instead of
    # reporting the entry. GetAttributes succeeds for every form the path can
    # take and sets ReparsePoint for a junction, which is the only reliable
    # signal. It throws when nothing occupies the name at all, which is the
    # fresh-checkout case.
    $attributes = $null
    try {
        $attributes = [System.IO.File]::GetAttributes($link.Path)
    } catch [System.IO.FileNotFoundException] {
        # Nothing occupies the path yet, which is the fresh-checkout case.
    } catch [System.IO.DirectoryNotFoundException] {
    }
    if ($null -ne $attributes -and
        ($attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        $existing = (Get-Item -LiteralPath $link.Path -Force).Target
        if ($existing -is [array]) { $existing = $existing[0] }
        if ($existing -ceq $link.Target) { continue }
        # A junction is removed with rmdir: Remove-Item would delete the target.
        cmd /c rmdir "$($link.Path)" 2>$null
    } elseif ($null -ne $attributes -and
        ($attributes -band [System.IO.FileAttributes]::Directory)) {
        Remove-Item -LiteralPath $link.Path -Recurse -Force
    } elseif ($null -ne $attributes) {
        Remove-Item -LiteralPath $link.Path -Force
    }

    New-Item -ItemType Junction -Path $link.Path -Target $link.Target | Out-Null
}
