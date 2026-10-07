param(
    [ValidateSet("patch","restore","status")]
    [string]$Mode = "patch"
)

$ErrorActionPreference = "Stop"
$AppRoot = Join-Path $env:LOCALAPPDATA "Programs\@opencode-aidesktop"
$ResDir  = Join-Path $AppRoot "resources"
$Asar    = Join-Path $ResDir "app.asar"
$Yml     = Join-Path $ResDir "app-update.yml"
$BackupRoot = Join-Path $env:LOCALAPPDATA "Temp\opencode"
$OldPat  = 'new Date(2026, 8, 14)'
$NewPat  = 'new Date(2099, 8, 14)'
$Latin1  = [System.Text.Encoding]::GetEncoding(28591)

function Count-Pattern([string]$Text, [string]$Pat) {
    return ([regex]::Matches($Text, [regex]::Escape($Pat))).Count
}

function Get-AsarText {
    return $Latin1.GetString([System.IO.File]::ReadAllBytes($Asar))
}

function Find-LatestBackup {
    $dirs = Get-ChildItem -Path $BackupRoot -Directory -Filter "legacy-backup-*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
    foreach ($d in $dirs) {
        if ((Test-Path (Join-Path $d.FullName "app.asar.bak")) -and (Test-Path (Join-Path $d.FullName "app-update.yml.bak"))) {
            return $d.FullName
        }
    }
    return $null
}

function Do-Backup {
    $existing = Find-LatestBackup
    if ($existing) {
        Write-Host "Backup already present (keeping original): $existing"
        return
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dir = Join-Path $BackupRoot ("legacy-backup-" + $stamp)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item $Asar (Join-Path $dir "app.asar.bak")
    Copy-Item $Yml  (Join-Path $dir "app-update.yml.bak")
    Write-Host "Backup created: $dir"
}

function Do-Patch {
    if (-not (Test-Path $Asar)) { throw "Not found: $Asar" }
    if (-not (Test-Path $Yml))  { throw "Not found: $Yml" }

    $txt = Get-AsarText
    $oldCount = Count-Pattern $txt $OldPat
    $newCount = Count-Pattern $txt $NewPat

    if ($newCount -eq 1 -and $oldCount -eq 0) {
        Write-Host "asar already patched (2099 present): OK"
    } elseif ($oldCount -eq 1) {
        Do-Backup
        $patched = $txt.Replace($OldPat, $NewPat)
        $bytes = $Latin1.GetBytes($patched)
        $origLen = (Get-Item $Asar).Length
        if ($bytes.Length -ne $origLen) {
            throw "Replacement is not same-length (orig=$origLen new=$($bytes.Length)); asar header would break. Nothing written."
        }
        try {
            [System.IO.File]::WriteAllBytes($Asar, $bytes)
        } catch {
            throw ("Cannot write app.asar (likely locked by the running app). Close OpenCode and run again. Detail: " + $_.Exception.Message)
        }
        $after = Get-AsarText
        if ((Count-Pattern $after $NewPat) -ne 1 -or (Count-Pattern $after $OldPat) -ne 0) {
            throw "Post-write verification FAILED. Restore from backup."
        }
        Write-Host "asar patched OK: sunset 2026 -> 2099 (1 occurrence, verified)"
    } else {
        throw ("Pattern '$OldPat' found " + $oldCount + " times (expected exactly 1). Upstream change suspected. Nothing touched.")
    }

    $current = [System.IO.File]::ReadAllText($Yml)
    if ($current -match "opencode-legacy-disabled") {
        Write-Host "app-update.yml already neutralized: OK"
    } else {
        Do-Backup
        $dead = "owner: opencode-legacy-disabled`r`n" +
                "repo: opencode-legacy-disabled-0000`r`n" +
                "provider: github`r`n" +
                "channel: latest`r`n" +
                "updaterCacheDirName: '@opencode-aidesktop-updater'`r`n"
        [System.IO.File]::WriteAllText($Yml, $dead, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "app-update.yml neutralized (nonexistent repo)"
    }

    Write-Host ""
    Write-Host "PATCH DONE. Restart OpenCode to load the patched version."
    Write-Host "Next: Settings -> enable old interface + Show agent."
    Write-Host "Undo with: patch-legacy.ps1 -Mode restore"
}

function Do-Restore {
    $dir = Find-LatestBackup
    if (-not $dir) { throw "No backup found under $BackupRoot" }
    Copy-Item (Join-Path $dir "app.asar.bak") $Asar -Force
    Copy-Item (Join-Path $dir "app-update.yml.bak") $Yml -Force
    Write-Host "Restored from $dir (pure official state). Restart OpenCode."
}

function Do-Status {
    if (-not (Test-Path $Asar)) { Write-Host "app.asar NOT found"; return }
    $txt = Get-AsarText
    $old = Count-Pattern $txt $OldPat
    $new = Count-Pattern $txt $NewPat
    $size = (Get-Item $Asar).Length
    Write-Host ("app.asar: $size bytes | sunset-2026 x$old | sunset-2099 x$new")
    if ($old -eq 1 -and $new -eq 0) { Write-Host "State: OFFICIAL (unpatched)" }
    elseif ($old -eq 0 -and $new -eq 1) { Write-Host "State: PATCHED (2099)" }
    else { Write-Host "State: UNEXPECTED (inspect manually)" }
    Write-Host "--- app-update.yml ---"
    if (Test-Path $Yml) { Write-Host ([System.IO.File]::ReadAllText($Yml)) } else { Write-Host "(missing)" }
    $b = Find-LatestBackup
    if ($b) { Write-Host "Backup: $b" } else { Write-Host "Backup: none" }
}

switch ($Mode) {
    "patch"   { Do-Patch }
    "restore" { Do-Restore }
    "status"  { Do-Status }
}
