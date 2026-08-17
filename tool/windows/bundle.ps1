[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$X64Package,
    [Parameter(Mandatory)]
    [string]$Arm64Package,
    [string]$Output = 'build\windows\bundle\Pomodoist.msixbundle'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stagePath = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot 'build\windows\bundle-input')
)
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
if (-not $stagePath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Bundle staging path escaped the repository.'
}

$kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$makeAppx = Get-ChildItem -LiteralPath $kitsBin -Filter makeappx.exe -Recurse |
    Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $makeAppx) { throw 'MakeAppx.exe was not found in Windows Kits.' }

if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagePath | Out-Null
New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($outputPath)) | Out-Null
Copy-Item -LiteralPath (Resolve-Path $X64Package).Path -Destination (Join-Path $stagePath 'Pomodoist_x64.msix')
Copy-Item -LiteralPath (Resolve-Path $Arm64Package).Path -Destination (Join-Path $stagePath 'Pomodoist_arm64.msix')

& $makeAppx.FullName bundle /d $stagePath /p $outputPath /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx failed to create the MSIX bundle.' }
Write-Output $outputPath
