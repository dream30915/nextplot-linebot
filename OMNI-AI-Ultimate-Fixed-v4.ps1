<#
.SYNOPSIS
OMNI-AI Ultimate Fixed v4 - All-in-one backup / restore / scheduler / LINE notify / crash analyzer for PowerShell 5.1
Usage:
    powershell -ExecutionPolicy Bypass -File ".\OMNI-AI-Ultimate-Fixed-v4.ps1" [-RunScheduledBackup] [-RunRestoreLatest] [-RunCleanBackups] [-InstallScheduler] [-NoGui]

Default behavior (no param): show GUI.
#>

param(
    [switch]$RunScheduledBackup,
    [switch]$RunRestoreLatest,
    [switch]$RunCleanBackups,
    [switch]$InstallScheduler,
    [switch]$NoGui
)

# ------------------------ CONFIG ------------------------
$ScriptName = "OMNI-AI-Ultimate-Fixed-v4.ps1"
$ProjectFolder = "C:\Users\msi\Desktop\nextplot-linebot"
$BackupRoot = "$env:USERPROFILE\Documents\OMNI-AI\Backups"
$LogFile = Join-Path $ProjectFolder "OMNI-AI-Backup.log"
$RestorePathFile = Join-Path $ProjectFolder "OMNI-AI-RestorePath.txt"
$ConfigFile = Join-Path $ProjectFolder "OMNI-AI-Config.json"
$CrashReport = Join-Path $ProjectFolder "AI-Crash-Report.log"
$SchedulerName = "OMNI-AI-AutoBackup"

# Ensure basic directories exist
function Ensure-Directories {
    if (-not (Test-Path $ProjectFolder)) {
        New-Item -Path $ProjectFolder -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $BackupRoot)) {
        New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
    }
}

# Simple logging
function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$t [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Encoding utf8 -Append
    Write-Output $line
}

# Load or create config
function Load-Config {
    if (-not (Test-Path $ConfigFile)) {
        $default = @{
            "LineToken" = "<YOUR_LINE_TOKEN_HERE>";
            "KeepDays" = 7;
            "BackupProject" = $ProjectFolder;
            "BackupRoot" = $BackupRoot;
            "SchedulerTime" = "02:00";
        } | ConvertTo-Json -Depth 4
        $default | Out-File -FilePath $ConfigFile -Encoding utf8
        Write-Log "Created default config at $ConfigFile"
        return (ConvertFrom-Json $default)
    } else {
        try {
            $json = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
            return $json
        } catch {
            Write-Log "Failed to load config: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
}

# LINE Notify
function Send-LineNotify {
    param([string]$Message)
    $cfg = Load-Config
    $token = $cfg.LineToken
    if (-not $token -or $token -match "<YOUR_LINE_TOKEN_HERE>") {
        Write-Log "LINE token not configured; skipping notify." "WARN"
        return $false
    }
    try {
        $uri = "https://notify-api.line.me/api/notify"
        $headers = @{ "Authorization" = "Bearer $token" }
        $body = @{ "message" = $Message }
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Log "LINE notified: $Message"
        return $true
    } catch {
        Write-Log "LINE notify failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Create backup (project, vscode extensions, settings)
function Create-Backup {
    Ensure-Directories
    $cfg = Load-Config
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zipName = "Backup_$timestamp.zip"
    $zipPath = Join-Path $cfg.BackupRoot $zipName
    $tempFolder = Join-Path $env:TEMP "OMNIAI_Backup_$timestamp"
    if (Test-Path $tempFolder) { Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -Path $tempFolder -ItemType Directory | Out-Null

    try {
        Write-Log "Starting backup to $zipPath"
        # 1) Copy project folder (exclude Backups folder to avoid recursion)
        $projectSource = $cfg.BackupProject
        if (-not (Test-Path $projectSource)) {
            Write-Log "Project folder not found: $projectSource" "ERROR"
        } else {
            $destProj = Join-Path $tempFolder "project"
            Copy-Item -Path $projectSource -Destination $destProj -Recurse -Force -ErrorAction Stop -Exclude "Backups"
        }

        # 2) Export VSCode extensions list (if 'code' CLI exists)
        $extsFile = Join-Path $tempFolder "vscode-extensions.txt"
        try {
            $codeCmd = "code"
            $which = (Get-Command $codeCmd -ErrorAction SilentlyContinue)
            if ($which) {
                Write-Log "Exporting VSCode extensions list"
                & $codeCmd --list-extensions | Out-File -FilePath $extsFile -Encoding utf8
            } else {
                Write-Log "'code' CLI not found; skipping extensions export" "WARN"
            }
        } catch {
            Write-Log "Extensions export error: $($_.Exception.Message)" "ERROR"
        }

        # 3) Copy VSCode settings (Windows path)
        $vscodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
        if (Test-Path $vscodeSettings) {
            Copy-Item -Path $vscodeSettings -Destination (Join-Path $tempFolder "settings.json") -Force
        } else {
            Write-Log "VSCode settings not found at $vscodeSettings" "WARN"
        }

        # Create zip
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $tempFolder "*") -DestinationPath $zipPath -Force
        Write-Log "Backup completed: $zipPath"
        $zipPath | Out-File -FilePath $RestorePathFile -Encoding utf8
        Write-Log "Saved restore path to $RestorePathFile"
        Send-LineNotify "OMNI-AI Backup succeeded: $zipName"
        # cleanup temp folder
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Log "Backup failed: $($_.Exception.Message)" "ERROR"
        Send-LineNotify "OMNI-AI Backup failed: $($_.Exception.Message)"
        if (Test-Path $tempFolder) { Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# Restore latest backup
function Restore-Latest {
    Ensure-Directories
    if (-not (Test-Path $RestorePathFile)) {
        Write-Log "No restore path file found." "ERROR"
        return $false
    }
    try {
        $path = Get-Content -Path $RestorePathFile -Raw
        if (-not (Test-Path $path)) {
            Write-Log "Restore file not found: $path" "ERROR"
            return $false
        }
        $tempRestore = Join-Path $env:TEMP "OMNIAI_Restore_" + (Get-Date -Format "yyyyMMddHHmmss")
        New-Item -Path $tempRestore -ItemType Directory | Out-Null
        Expand-Archive -Path $path -DestinationPath $tempRestore -Force
        # Copy back project files (prompt)
        $sourceProj = Join-Path $tempRestore "project"
        if (-not (Test-Path $sourceProj)) {
            Write-Log "No project data found inside archive." "ERROR"
            return $false
        }
        Write-Log "Restoring project files to $ProjectFolder"
        # Prompt user for confirmation before overwriting
        $ans = Read-Host "Restore will overwrite project files. Type YES to continue"
        if ($ans -ne "YES") {
            Write-Log "Restore cancelled by user." "WARN"
            Remove-Item -Path $tempRestore -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        Copy-Item -Path (Join-Path $sourceProj "*") -Destination $ProjectFolder -Recurse -Force
        Write-Log "Restore completed from $path"
        Send-LineNotify "OMNI-AI Restore completed: $(Split-Path $path -Leaf)"
        Remove-Item -Path $tempRestore -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Log "Restore failed: $($_.Exception.Message)" "ERROR"
        Send-LineNotify "OMNI-AI Restore failed: $($_.Exception.Message)"
        return $false
    }
}

# Clean old backups older than KeepDays
function Clean-OldBackups {
    Ensure-Directories
    $cfg = Load-Config
    $keep = $cfg.KeepDays
    try {
        $deleted = 0
        Get-ChildItem -Path $cfg.BackupRoot -Filter "*.zip" -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$keep) } | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            $deleted++
            Write-Log "Deleted old backup: $($_.Name)"
        }
        Write-Log "Clean completed. Files deleted: $deleted"
        Send-LineNotify "OMNI-AI Clean completed. Files deleted: $deleted"
        return $true
    } catch {
        Write-Log "Clean failed: $($_.Exception.Message)" "ERROR"
        Send-LineNotify "OMNI-AI Clean failed: $($_.Exception.Message)"
        return $false
    }
}

# Install Scheduled Task
function Install-Scheduler {
    Ensure-Directories
    $cfg = Load-Config
    $time = $cfg.SchedulerTime
    $taskName = $SchedulerName
    # Build schtasks command
    $psExec = (Get-Command "powershell" -ErrorAction SilentlyContinue).Source
    $scriptFull = Join-Path $ProjectFolder $ScriptName
    $cmd = "schtasks /Create /F /SC DAILY /TN `"$taskName`" /TR `"$psExec -ExecutionPolicy Bypass -File `"$scriptFull`" -RunScheduledBackup`" /ST $time"
    try {
        Write-Log "Creating scheduled task: $taskName at $time"
        cmd.exe /c $cmd | Out-Null
        Write-Log "Scheduled task created."
        Send-LineNotify "OMNI-AI Scheduler installed: $taskName at $time"
        return $true
    } catch {
        Write-Log "Scheduler install failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Simple AI Crash Analyzer: search VSCode logs for "Exception" and summarize
function Run-CrashAnalyzer {
    try {
        $vscodeLogRoot = Join-Path $env:APPDATA "Code\logs"
        if (-not (Test-Path $vscodeLogRoot)) {
            Write-Log "VSCode logs folder not found: $vscodeLogRoot" "WARN"
            return $false
        }
        $latestLog = Get-ChildItem -Path $vscodeLogRoot -Recurse -Filter "main*.log" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latestLog) {
            Write-Log "No main log files found for VSCode." "WARN"
            return $false
        }
        $content = Get-Content -Path $latestLog.FullName -Raw -ErrorAction SilentlyContinue
        $exceptions = Select-String -InputObject $content -Pattern "Exception|ERROR|Unhandled" -SimpleMatch -AllMatches
        if ($exceptions) {
            $report = "Crash analysis report - $(Get-Date)`nLog: $($latestLog.FullName)`n----`n"
            $exceptions.Matches | ForEach-Object { $report += $_.Value + "`n" }
            $report | Out-File -FilePath $CrashReport -Encoding utf8 -Append
            Write-Log "Crash analyzer found possible issues. Reported to $CrashReport"
            Send-LineNotify "VSCode Crash Detected (AI Crash Analyzer แจ้งเตือน)"
            return $true
        } else {
            Write-Log "Crash analyzer: no obvious exceptions found."
            return $false
        }
    } catch {
        Write-Log "Crash analyzer error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Top-level wrapper for scheduled run
function Run-ScheduledBackup-Wrapper {
    Ensure-Directories
    $ok = Create-Backup
    Run-CrashAnalyzer | Out-Null
    return $ok
}

# GUI (Windows Forms) - only show if not NoGui and running interactively
function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "OMNI-AI Extension Manager (OMNI-AI)"
    $form.Size = New-Object System.Drawing.Size(700,360)
    $form.StartPosition = "CenterScreen"

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(12,250)
    $lblStatus.Size = New-Object System.Drawing.Size(660,80)
    $lblStatus.Text = "Status: Ready."
    $lblStatus.AutoSize = $false

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Location = New-Object System.Drawing.Point(12,12)
    $btnBackup.Size = New-Object System.Drawing.Size(160,40)
    $btnBackup.Text = "Run Backup Now"
    $btnBackup.Add_Click({
        $lblStatus.Text = "Status: Running backup..."
        $form.Refresh()
        $res = Run-ScheduledBackup-Wrapper
        if ($res) { $lblStatus.Text = "Status: Backup completed successfully." } else { $lblStatus.Text = "Status: Backup failed. Check log." }
    })

    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Location = New-Object System.Drawing.Point(190,12)
    $btnRestore.Size = New-Object System.Drawing.Size(160,40)
    $btnRestore.Text = "Restore Latest"
    $btnRestore.Add_Click({
        $lblStatus.Text = "Status: Restoring..."
        $form.Refresh()
        $res = Restore-Latest
        if ($res) { $lblStatus.Text = "Status: Restore completed." } else { $lblStatus.Text = "Status: Restore failed or cancelled." }
    })

    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Location = New-Object System.Drawing.Point(370,12)
    $btnClean.Size = New-Object System.Drawing.Size(160,40)
    $btnClean.Text = "Clean Old Backups"
    $btnClean.Add_Click({
        $lblStatus.Text = "Status: Cleaning..."
        $form.Refresh()
        $res = Clean-OldBackups
        if ($res) { $lblStatus.Text = "Status: Clean completed." } else { $lblStatus.Text = "Status: Clean failed." }
    })

    $btnScheduler = New-Object System.Windows.Forms.Button
    $btnScheduler.Location = New-Object System.Drawing.Point(12,70)
    $btnScheduler.Size = New-Object System.Drawing.Size(160,40)
    $btnScheduler.Text = "Install Scheduler"
    $btnScheduler.Add_Click({
        $lblStatus.Text = "Status: Installing scheduler..."
        $form.Refresh()
        $res = Install-Scheduler
        if ($res) { $lblStatus.Text = "Status: Scheduler installed." } else { $lblStatus.Text = "Status: Scheduler install failed." }
    })

    $btnTestLine = New-Object System.Windows.Forms.Button
    $btnTestLine.Location = New-Object System.Drawing.Point(190,70)
    $btnTestLine.Size = New-Object System.Drawing.Size(160,40)
    $btnTestLine.Text = "Test LINE Notify"
    $btnTestLine.Add_Click({
        $lblStatus.Text = "Status: Sending LINE test..."
        $form.Refresh()
        Send-LineNotify "OMNI-AI Test message from GUI at $(Get-Date)"
        $lblStatus.Text = "Status: LINE test sent (or skipped if token missing)."
    })

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Location = New-Object System.Drawing.Point(370,70)
    $btnExit.Size = New-Object System.Drawing.Size(160,40)
    $btnExit.Text = "Exit"
    $btnExit.Add_Click({ $form.Close() })

    # Add controls
    $form.Controls.AddRange(@($btnBackup,$btnRestore,$btnClean,$btnScheduler,$btnTestLine,$btnExit,$lblStatus))

    # Show form
    [void]$form.ShowDialog()
}

# --- Main execution flow ---
Ensure-Directories
# Create config if missing
$cfg = Load-Config

if ($RunScheduledBackup) {
    $ok = Run-ScheduledBackup-Wrapper
    Write-Output $ok
    exit
}

if ($RunRestoreLatest) {
    $ok = Restore-Latest
    Write-Output $ok
    exit
}

if ($RunCleanBackups) {
    $ok = Clean-OldBackups
    Write-Output $ok
    exit
}

if ($InstallScheduler) {
    $ok = Install-Scheduler
    Write-Output $ok
    exit
}

# If running non-interactive and no GUI requested, just run scheduled backup
if ($NoGui -or -not $Host.UI.RawUI.KeyAvailable) {
    # try to run backup once
    Run-ScheduledBackup-Wrapper | Out-Null
    exit
}

# Otherwise show GUI
Show-GUI
