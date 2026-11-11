<#
.SYNOPSIS
    Writes each character's TippWorks gear export to a text file (to paste or upload into ChatGPT).

.DESCRIPTION
    In game: TippWorks-Vault saves the export a few seconds after login or /reload, after gear changes, and when the
    bank or Great Vault opens (open the bank now and then so its gear is in it); WoW writes it to disk on /reload or logout.
    This reads the saved exports from the WTF folder (read only) and writes one file per character to
    Documents\TippWorks Gear, then opens that folder. An incomplete export (no gear or spec) is reported, not written.
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

# Reads ["gearExport"] = { ... }: its scalar fields (at, reason, valid, equipped, ilvl, spec, actions) and its
# lines. Nesting is tracked, so another table inside it can't cut the read short.
function Read-GearExport([string[]]$lines) {
    $fields = @{}; $out = New-Object System.Collections.Generic.List[string]
    $depth = 0; $inLines = $false
    foreach ($l in $lines) {
        if ($depth -eq 0) {
            if ($l -match '^\s*\["gearExport"\]\s*=\s*\{\s*$') { $depth = 1 }
            continue
        }
        if ($l -match '^\s*\},?(\s*-- \[\d+\])?\s*$') {
            $depth--
            if ($depth -le 1) { $inLines = $false }
            if ($depth -eq 0) { break }
        } elseif ($l -match '=\s*\{\s*$' -or $l -match '^\s*\{\s*$') {
            $depth++
            if ($depth -eq 2 -and $l -match '^\s*\["lines"\]') { $inLines = $true }
        } elseif ($inLines -and $depth -eq 2 -and $l -match '^\s*"(.*)",(\s*-- \[\d+\])?\s*$') {
            $out.Add((Unescape $Matches[1]))
        } elseif ($depth -eq 1 -and $l -match '^\s*\["(\w+)"\]\s*=\s*(.*?),\s*$') {
            $k = $Matches[1]; $v = $Matches[2]
            if ($v -match '^"(.*)"$') { $v = Unescape $Matches[1] }
            $fields[$k] = $v
        }
    }
    return @{ Fields = $fields; Lines = $out }
}

# Complete = the snapshot could see the character. 1.3.1+ records that; older exports are judged by their text.
function Test-Complete($e) {
    $f = $e.Fields
    if ($f.ContainsKey('valid')) { return $f['valid'] -eq 'true' }
    $text = $e.Lines -join "`n"
    return -not ($text -match 'Average item level: 0\.0 equipped' -or $text -match '- Active: \? \(\?\)')
}

if (Get-Process -Name 'Wow', 'WowT', 'WowB' -ErrorAction SilentlyContinue) {
    Write-Host 'WoW is running: these are the exports as of each character''s last /reload or logout.' -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$written = 0
Get-ChildItem -Path $wtf -Recurse -Filter 'TippWorks-Vault.lua' | Where-Object { $_.DirectoryName -like '*\SavedVariables' } | ForEach-Object {
    $charDir = $_.Directory.Parent
    $char = $charDir.Name
    $realm = $charDir.Parent.Name
    $e = Read-GearExport (Get-Content -Path $_.FullName -Encoding UTF8)
    if ($e.Lines.Count -eq 0) { return }
    $f = $e.Fields
    $what = "export from {0} ({1})" -f $f['at'], $(if ($f['reason']) { $f['reason'] } else { 'reason not recorded' })
    if ($f.ContainsKey('equipped')) {
        $what += "; {0} slots equipped, ilvl {1}, spec {2}" -f $f['equipped'], $f['ilvl'], $(if ($f['spec']) { $f['spec'] } else { 'none' })
    }
    $file = Join-Path $OutDir ("{0} - {1}.txt" -f $char, $realm)
    if (-not (Test-Complete $e)) {
        # Never replace a file with one missing the character's gear and spec.
        Write-Host ("{0} - {1}: {2} is INCOMPLETE (no gear/spec), skipped. Log in, wait 10 seconds, /reload, run this again." -f $char, $realm, $what) -ForegroundColor Red
        if (Test-Path $file) { Write-Host ("    kept the earlier file: {0}, written {1}" -f $file, (Get-Item $file).LastWriteTime) }
        return
    }
    [IO.File]::WriteAllLines($file, $e.Lines, (New-Object Text.UTF8Encoding($false)))
    Write-Host ("{0} - {1}: {2} -> {3}" -f $char, $realm, $what, $file) -ForegroundColor Green
    $written++
}

if ($written -eq 0) {
    Write-Host 'No complete gear exports found. Log in with TippWorks-Vault 1.3.1 or newer, wait 10 seconds, then /reload.' -ForegroundColor Yellow
} elseif (-not $NoOpen) {
    Start-Process explorer.exe $OutDir
}
