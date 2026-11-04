<#
.SYNOPSIS
    Writes each character's TippWorks gear export to a text file (to paste or upload into ChatGPT).

.DESCRIPTION
    In game: TippWorks-Vault saves the export on every logout or /reload (open the bank now and then so its gear is in it).
    This reads the saved exports from the WTF folder (read only) and writes one file per character to
    Documents\TippWorks Gear, then opens that folder.
    The WoW folder comes from install.settings.json (the same file Update-WowAddons.ps1 uses).
#>
param(
    [string]$OutDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'TippWorks Gear'),
    [switch]$NoOpen,
    [string]$WowPath
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $RepoRoot 'install.settings.json'
if (-not (Test-Path $settingsPath)) { $settingsPath = Join-Path $RepoRoot 'install.settings.example.json' }
# Single backslashes in paths are fine too (same fix-up as Update-WowAddons.ps1).
$text = [regex]::Replace((Get-Content $settingsPath -Raw), '\\\\|\\"|\\', { param($m) if ($m.Value.Length -eq 2) { $m.Value } else { '\\' } })
$settings = $text | ConvertFrom-Json
$wowPath = if ($WowPath) { $WowPath } else { [Environment]::ExpandEnvironmentVariables($settings.wowPath) }
$flavor = if ($settings.flavor) { $settings.flavor } else { '_retail_' }
$wtf = Join-Path (Join-Path $wowPath $flavor) 'WTF\Account'
if (-not (Test-Path $wtf)) { Write-Host "ERROR: WoW's WTF folder not found: $wtf" -ForegroundColor Red; exit 1 }

# Lua string escapes as WoW writes them: \" \\ \n
function Unescape([string]$s) {
    return [regex]::Replace($s, '\\(.)', {
        param($m)
        switch ($m.Groups[1].Value) { 'n' { "`r`n" } 't' { "`t" } default { $m.Groups[1].Value } }
    })
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$written = 0
Get-ChildItem -Path $wtf -Recurse -Filter 'TippWorks-Vault.lua' | Where-Object { $_.DirectoryName -like '*\SavedVariables' } | ForEach-Object {
    $charDir = $_.Directory.Parent
    $char = $charDir.Name
    $realm = $charDir.Parent.Name
    $lines = Get-Content -Path $_.FullName -Encoding UTF8
    $at = $null; $out = New-Object System.Collections.Generic.List[string]
    $state = 0 # 0 looking for gearExport, 1 inside it, 2 inside its lines
    foreach ($l in $lines) {
        if ($state -eq 0) {
            if ($l -match '^\s*\["gearExport"\]\s*=\s*\{') { $state = 1 }
        } elseif ($state -eq 1) {
            if ($l -match '^\s*\["at"\]\s*=\s*"(.*)",') { $at = $Matches[1] }
            elseif ($l -match '^\s*\["lines"\]\s*=\s*\{') { $state = 2 }
            elseif ($l -match '^\s*\},?\s*$') { break }
        } else {
            if ($l -match '^\s*"(.*)",(\s*-- \[\d+\])?\s*$') { $out.Add((Unescape $Matches[1])) }
            elseif ($l -match '^\s*\},?\s*$') { $state = 1 }
        }
    }
    if ($out.Count -gt 0) {
        $file = Join-Path $OutDir ("{0} - {1}.txt" -f $char, $realm)
        [IO.File]::WriteAllLines($file, $out, (New-Object Text.UTF8Encoding($false)))
        Write-Host ("{0} - {1}: export from {2} -> {3}" -f $char, $realm, $at, $file) -ForegroundColor Green
        $written++
    }
}

if ($written -eq 0) {
    Write-Host 'No gear exports found. Log in with TippWorks-Vault 1.3.0 or newer, then /reload or log out.' -ForegroundColor Yellow
} elseif (-not $NoOpen) {
    Start-Process explorer.exe $OutDir
}
