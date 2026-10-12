<#
.SYNOPSIS
    Tippenhauer Works - pull the latest addons from GitHub and install them into WoW.

.DESCRIPTION
    1. git pull (fast-forward only) from https://github.com/rtippenhauer/wow-addons
    2. For every addon folder under addons\ that changed (or is missing), back up the
       installed copy to a zip, delete it, and copy the new one in (replace, never merge).
    3. Apply one-time renames from tools\migrations.json (copies saved data to the new
       name - only while WoW is closed).
    4. Print what changed and whether /reload is enough or WoW needs a full restart.

    Never deletes or edits anything in the WTF folder (saved kills, routes, settings).
    Machine-specific settings live in install.settings.json (gitignored, created on first run).

.PARAMETER NoPull
    Skip "git pull" and install the working copy as-is (useful on the dev machine).
.PARAMETER Force
    Reinstall every addon even if the installed copy is identical.
.PARAMETER Only
    Install just these addon folder names, e.g. -Only TippWorks-Curios
.PARAMETER DryRun
    Show what would happen without changing anything.
.PARAMETER Flavor
    Which WoW install to update: _retail_ (default, or the "flavor" setting), _ptr_, _xptr_ ...
    Short forms: ptr, xptr, beta. Backups for anything but retail go to a subfolder named after it.

.EXAMPLE
    .\Update-WowAddons.cmd
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\Update-WowAddons.ps1 -NoPull -Only CoiledRareTracker
.EXAMPLE
    .\Update-WowAddons.cmd -Flavor ptr -NoPull      (try the working copy on the PTR)
#>
[CmdletBinding()]
param(
    [switch]$NoPull,
    [switch]$Force,
    [string[]]$Only,
    [switch]$DryRun,
    [string]$Flavor
)

$ErrorActionPreference = 'Stop'
$RepoRoot     = Split-Path -Parent $PSScriptRoot
$SourceRoot   = Join-Path $RepoRoot 'addons'
$SettingsPath = Join-Path $RepoRoot 'install.settings.json'
$ExamplePath  = Join-Path $RepoRoot 'install.settings.example.json'
$MigrationsPath = Join-Path $PSScriptRoot 'migrations.json'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Expand($p) { [Environment]::ExpandEnvironmentVariables($p) }

Say "Tippenhauer Works - addon updater" 'Cyan'
if ($DryRun) { Say "(dry run - nothing will be changed)" 'Yellow' }

# ---------------------------------------------------------------- settings
function Find-WowPath {
    $keys = 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
            'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft'
    foreach ($k in $keys) {
        try {
            $p = (Get-ItemProperty $k -ErrorAction Stop).InstallPath
            # InstallPath points at ...\World of Warcraft\_retail_\
            if ($p) { return (Split-Path -Parent ($p.TrimEnd('\'))) }
        } catch {}
    }
    foreach ($p in "${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft",
                   'C:\World of Warcraft', 'D:\World of Warcraft', 'D:\Games\World of Warcraft') {
        if ($p -and (Test-Path (Join-Path $p '_retail_'))) { return $p }
    }
    return $null
}

# Settings files are edited by hand, so tolerate single backslashes in paths ("C:\Games\WoW").
function Read-Json($path) {
    $text = Get-Content $path -Raw
    $text = [regex]::Replace($text, '\\\\|\\"|\\', { param($m) if ($m.Value.Length -eq 2) { $m.Value } else { '\\' } })
    try { return $text | ConvertFrom-Json } catch { Fail "Could not read $path - check the JSON syntax.`n       $($_.Exception.Message)" }
}

if (-not (Test-Path $SettingsPath)) {
    if (-not (Test-Path $ExamplePath)) { Fail "install.settings.example.json is missing from the repo." }
    $text = Get-Content $ExamplePath -Raw
    $found = Find-WowPath
    if ($found) {
        $json = $found.Replace('\', '\\')
        $text = $text -replace '("wowPath"\s*:\s*)"[^"]*"', ('$1"' + $json.Replace('$', '$$') + '"')
    }
    if (-not $DryRun) { [IO.File]::WriteAllText($SettingsPath, $text) }
    Say "Created install.settings.json (WoW folder: $(if ($found) { $found } else { 'NOT FOUND - using the default' }))." 'Yellow'
    Say "Edit that file if the path is wrong. It is never overwritten by updates." 'Yellow'
}
$settings = if (Test-Path $SettingsPath) { Read-Json $SettingsPath } else { Read-Json $ExamplePath }

$wowPath   = Expand $settings.wowPath
$flavor    = if ($Flavor) { $Flavor } elseif ($settings.flavor) { $settings.flavor } else { '_retail_' }
$flavor    = '_' + $flavor.Trim('_').ToLower() + '_'   # "ptr" -> "_ptr_"
$addonsDir = Join-Path (Join-Path (Join-Path $wowPath $flavor) 'Interface') 'AddOns'
$wtfDir    = Join-Path (Join-Path $wowPath $flavor) 'WTF'
$backupDir = Expand $(if ($settings.backupDir) { $settings.backupDir } else { '%USERPROFILE%\WoWAddonBackups' })
if ($flavor -ne '_retail_') {
    $backupDir = Join-Path $backupDir $flavor # keep test-realm backups apart from live ones
    Say "Target: $flavor (not your live game)" 'Yellow'
}
$keep      = if ($settings.keepBackups) { [int]$settings.keepBackups } else { 10 }
$wanted    = @($settings.addons | Where-Object { $_ })
$excluded  = @($settings.exclude | Where-Object { $_ })
$doPull    = (-not $NoPull) -and ($settings.pull -ne $false)

if (-not (Test-Path $addonsDir) -and $flavor -ne '_retail_' -and (Test-Path $wowPath)) {
    $have = (Get-ChildItem $wowPath -Directory | Where-Object { $_.Name -match '^_.+_$' } | ForEach-Object { $_.Name }) -join ', '
    Fail "No $flavor install with an AddOns folder in $wowPath (found: $have).`n       Install it from the Battle.net launcher (game version dropdown) and start it once, then rerun."
}
if (-not (Test-Path $addonsDir)) {
    Fail "AddOns folder not found: $addonsDir`n       Fix wowPath in $SettingsPath (it should be the 'World of Warcraft' folder)."
}

# ---------------------------------------------------------------- git pull
if ($doPull) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail "git is not installed (https://git-scm.com/download/win), or run with -NoPull."
    }
    $dirty = git -C $RepoRoot status --porcelain -- addons tools
    if ($dirty) {
        Say "Local changes in the repo:" 'Red'; $dirty | ForEach-Object { Say "  $_" 'Red' }
        Fail "Addons must not be edited on this machine - changes go through GitHub.`n       Undo them with: git -C `"$RepoRoot`" checkout -- addons tools"
    }
    Say "Pulling latest from GitHub..."
    $before = git -C $RepoRoot rev-parse HEAD 2>$null
    git -C $RepoRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) { Fail "git pull failed (see above). Nothing was installed." }
    $after = git -C $RepoRoot rev-parse HEAD 2>$null
    if ($before -and $before -ne $after) {
        Say "Changes pulled:" 'Cyan'
        git -C $RepoRoot log --oneline "$before..$after" | ForEach-Object { Say "  $_" }
    }
}

# ---------------------------------------------------------------- helpers
function Get-TocVersion($dir) {
    $toc = Join-Path $dir ((Split-Path $dir -Leaf) + '.toc')
    if (-not (Test-Path $toc)) { return $null }
    $m = Select-String -Path $toc -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() } else { return '?' }
}

# Relative file list + hash, so we can tell "code-only" changes from "files added/removed".
function Get-Manifest($dir) {
    $h = @{}
    if (-not (Test-Path $dir)) { return $h }
    $base = (Resolve-Path $dir).Path.TrimEnd('\') + '\'
    Get-ChildItem $dir -Recurse -File | ForEach-Object {
        $h[$_.FullName.Substring($base.Length)] = (Get-FileHash $_.FullName -Algorithm MD5).Hash
    }
    return $h
}

# The .toc is only read at game start; a change other than "## Version" needs a restart.
function Get-TocBody($dir) {
    $toc = Join-Path $dir ((Split-Path $dir -Leaf) + '.toc')
    if (-not (Test-Path $toc)) { return '' }
    (Get-Content $toc | Where-Object { $_ -notmatch '^##\s*Version:' }) -join "`n"
}

function Test-WowRunning {
    [bool](Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in 'Wow', 'WowT', 'WowB', 'Wow-64' })
}

function Backup-Addon($name, $version) {
    $src = Join-Path $addonsDir $name
    if (-not (Test-Path $src)) { return $null }
    New-Item -ItemType Directory -Force $backupDir | Out-Null
    $ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $backupDir "$name-$version-$ts.zip"
    Compress-Archive -Path $src -DestinationPath $zip -Force
    # prune old backups of this addon
    Get-ChildItem $backupDir -Filter "$name-*.zip" | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $keep | Remove-Item -Force
    return $zip
}

# ---------------------------------------------------------------- install
$sources = Get-ChildItem $SourceRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName ($_.Name + '.toc')) }
if ($Only) { $sources = $sources | Where-Object { $_.Name -in $Only } }
elseif ($wanted.Count -gt 0 -and -not ($wanted -contains '*')) { $sources = $sources | Where-Object { $_.Name -in $wanted } }
if ($excluded.Count -gt 0) { $sources = $sources | Where-Object { $_.Name -notin $excluded } }
if (-not $sources) { Fail "No addons selected (check 'addons'/'exclude' in install.settings.json, or -Only)." }

$wowRunning = Test-WowRunning
$needRestart = $false
$results = @()

foreach ($src in $sources) {
    $name   = $src.Name
    $dest   = Join-Path $addonsDir $name
    $newVer = Get-TocVersion $src.FullName
    $oldVer = Get-TocVersion $dest
    $newMan = Get-Manifest $src.FullName
    $oldMan = Get-Manifest $dest

    $sameFiles = ($newMan.Count -eq $oldMan.Count) -and
                 -not ($newMan.Keys | Where-Object { -not $oldMan.ContainsKey($_) })
    $identical = $sameFiles -and -not ($newMan.Keys | Where-Object { $newMan[$_] -ne $oldMan[$_] })

    if ($identical -and -not $Force) {
        $results += [pscustomobject]@{ Addon = $name; Installed = $oldVer; Result = 'up to date' }
        continue
    }

    $restart = (-not (Test-Path $dest)) -or (-not $sameFiles) -or ((Get-TocBody $src.FullName) -ne (Get-TocBody $dest))
    if ($restart) { $needRestart = $true }

    if ($DryRun) {
        $results += [pscustomobject]@{ Addon = $name; Installed = "$oldVer -> $newVer"; Result = 'would update' + $(if ($restart) { ' (restart)' } else { '' }) }
        continue
    }

    try {
        $zip = Backup-Addon $name $oldVer
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item $src.FullName $dest -Recurse -Force
    } catch {
        if ($_.Exception -is [UnauthorizedAccessException] -or "$_" -match 'denied') {
            Fail "Access denied writing to $addonsDir. Close WoW and try again, or run as administrator."
        }
        throw
    }
    $verify = Get-Manifest $dest
    $ok = ($verify.Count -eq $newMan.Count) -and -not ($newMan.Keys | Where-Object { $verify[$_] -ne $newMan[$_] })
    $results += [pscustomobject]@{
        Addon = $name
        Installed = $(if ($oldVer) { "$oldVer -> $newVer" } else { "new: $newVer" })
        Result = $(if (-not $ok) { 'COPY MISMATCH - rerun' } elseif ($restart) { 'updated (restart)' } else { 'updated (/reload)' })
    }
}

# ---------------------------------------------------------------- one-time renames
# migrations.json: { "renames": [ { "from": "OldFolder", "to": "NewFolder" } ] }
# When the new addon is installed: copy saved data OldFolder.lua -> NewFolder.lua (only if the
# new file doesn't exist yet, only while WoW is closed), then back up + remove the old addon folder.
if (Test-Path $MigrationsPath) {
    $mig = Read-Json $MigrationsPath
    foreach ($r in @($mig.renames)) {
        if (-not $r -or -not (Test-Path (Join-Path $addonsDir $r.to))) { continue }
        $oldDir = Join-Path $addonsDir $r.from
        if ($wowRunning) {
            if (Test-Path $oldDir) { Say "Rename $($r.from) -> $($r.to) waits until WoW is closed. Close WoW and run the updater again." 'Yellow' }
            continue
        }
        if (Test-Path $wtfDir) {
            Get-ChildItem $wtfDir -Recurse -File -Filter "$($r.from).lua" -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -eq 'SavedVariables' } | ForEach-Object {
                    $target = Join-Path $_.DirectoryName "$($r.to).lua"
                    if (-not (Test-Path $target)) {
                        if ($DryRun) { Say "would copy saved data $($_.FullName) -> $($r.to).lua" }
                        else { Copy-Item $_.FullName $target; Say "Copied saved data -> $target" }
                    }
                }
        }
        if (Test-Path $oldDir) {
            if ($DryRun) { Say "would remove old addon folder $($r.from)" }
            else {
                $zip = Backup-Addon $r.from (Get-TocVersion $oldDir)
                Remove-Item $oldDir -Recurse -Force
                Say "Removed old addon $($r.from) (backup: $zip)"
                $needRestart = $true
            }
        }
    }
}

# ---------------------------------------------------------------- report
Say ""
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_.TrimEnd() }
Say ""
$changed = $results | Where-Object { $_.Result -notlike 'up to date' }
if (-not $changed) {
    Say "Everything is already up to date." 'Green'
} elseif ($needRestart) {
    Say "Exit WoW completely and start it again (new/removed files or .toc changes - /reload is NOT enough)." 'Yellow'
} else {
    Say "Type /reload in game." 'Green'
}
Say "Backups: $backupDir   (existing saved data in WTF is never changed or deleted)" 'DarkGray'
