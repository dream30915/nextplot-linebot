<#
.SYNOPSIS
OMNI-AI Ultimate Fixed v4.2 - Adds Proxy/Webhook fallback, GUI status indicator, async backup, TLS1.2, retry.
#>

param(
    [switch]$RunScheduledBackup,
    [switch]$RunRestoreLatest,
    [switch]$RunCleanBackups,
    [switch]$InstallScheduler,
    [switch]$NoGui
)

$ScriptName = "OMNI-AI-Ultimate-Fixed-v4.2.ps1"
$ProjectFolder = "C:\Users\msi\Desktop\nextplot-linebot"
$BackupRoot = "$env:USERPROFILE\Documents\OMNI-AI\Backups"
$LogFile = Join-Path $ProjectFolder "OMNI-AI-Backup.log"
$RestorePathFile = Join-Path $ProjectFolder "OMNI-AI-RestorePath.txt"
$ConfigFile = Join-Path $ProjectFolder "OMNI-AI-Config.json"
$CrashReport = Join-Path $ProjectFolder "AI-Crash-Report.log"
$SchedulerName = "OMNI-AI-AutoBackup"
$NotifyStatusFile = Join-Path $ProjectFolder "OMNI-AI-NotifyStatus.txt"

# Force TLS 1.2 for PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Ensure-Directories {
    if (-not (Test-Path $ProjectFolder)) { New-Item -Path $ProjectFolder -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $BackupRoot)) { New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$t [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Encoding utf8 -Append
    # Also write last status for GUI to read
    $line | Out-File -FilePath $NotifyStatusFile -Encoding utf8 -Append
    Write-Output $line
}

function Write-NotifyStatus {
    param([string]$Message)
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$t $Message" | Out-File -FilePath $NotifyStatusFile -Encoding utf8 -Force
}

function Load-Config {
    if (-not (Test-Path $ConfigFile)) {
        $default = @{
            "LineToken" = "<YOUR_LINE_TOKEN_HERE>";
            "FallbackWebhook" = "https://proxy.omni-ai.app/line";
            "KeepDays" = 7;
            "BackupProject" = $ProjectFolder;
            "BackupRoot" = $BackupRoot;
            "SchedulerTime" = "02:00";
        } | ConvertTo-Json -Depth 4
        $default | Out-File -FilePath $ConfigFile -Encoding utf8
        Write-Log "Created default config at $ConfigFile"
        return (ConvertFrom-Json $default)
    }
    try {
        return (Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json)
    } catch {
        Write-Log "Failed to parse config: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Test-DnsLookup {
    param([string]$HostName)
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($HostName)
        if ($addrs -and $addrs.Length -gt 0) { return $true } else { return $false }
    } catch {
        return $false
    }
}

function Test-Network {
    # quick DNS check for LINE API host
    if (Test-DnsLookup -HostName "notify-api.line.me") {
        Write-Log "DNS resolved notify-api.line.me"
        return $true
    } else {
        Write-Log "DNS failed for notify-api.line.me" "WARN"
        return $false
    }
}

function Send-LineNotify-Main {
    param([string]$Message, [string]$Token)
    $uri = "https://notify-api.line.me/api/notify"
    $headers = @{ "Authorization" = "Bearer $Token" }
    $body = @{ "message" = $Message }
    for ($i=1; $i -le 3; $i++) {
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
            Write-Log "[LINE-MAIN] Notified: $Message"
            Write-NotifyStatus "[LINE-MAIN] Sent"
            return $true
        } catch {
            Write-Log "[LINE-MAIN] Attempt $i failed: $($_.Exception.Message)" "WARN"
            Start-Sleep -Seconds 2
        }
    }
    Write-Log "[LINE-MAIN] Failed after 3 attempts." "ERROR"
    return $false
}

function Send-LineNotify-Fallback {
    param([string]$Message, [string]$FallbackUrl)
    $uri = $FallbackUrl
    $body = @{ "message" = $Message } | ConvertTo-Json
    for ($i=1; $i -le 3; $i++) {
        try {
            # Fallback proxy expects JSON body (no Authorization header)
            Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
            Write-Log "[LINE-FALLBACK] Notified via proxy: $uri"
            Write-NotifyStatus "[LINE-FALLBACK] Sent"
            return $true
        } catch {
            Write-Log "[LINE-FALLBACK] Attempt $i failed: $($_.Exception.Message)" "WARN"
            Start-Sleep -Seconds 2
        }
    }
    Write-Log "[LINE-FALLBACK] Failed after 3 attempts." "ERROR"
    return $false
}

function Send-LineNotify {
    param([string]$Message)
    $cfg = Load-Config
    $token = $cfg.LineToken
    $fallback = $cfg.FallbackWebhook
    if (-not $token -or $token -match "<YOUR_LINE_TOKEN_HERE>") {
        Write-Log "LINE token missing in config; skipping notify." "WARN"
        Write-NotifyStatus "[LINE] Token missing"
        return $false
    }
    # Try main first if DNS resolves
    if (Test-Network) {
        $ok = Send-LineNotify-Main -Message $Message -Token $token
        if ($ok) { return $true }
        Write-Log "Main LINE failed, will try fallback." "WARN"
    } else {
        Write-Log "Skipping main LINE due to DNS failure." "WARN"
    }
    # Try fallback proxy if configured
    if ($fallback -and ($fallback -ne "")) {
        $ok2 = Send-LineNotify-Fallback -Message $Message -FallbackUrl $fallback
        if ($ok2) { return $true }
    }
    Write-NotifyStatus "[LINE] All notify attempts failed"
    return $false
}

function Create-Backup {
    Ensure-Directories
    $cfg = Load-Config
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zipName = "Backup_$timestamp.zip"
    $zipPath = Join-Path $cfg.BackupRoot $zipName
    $tempFolder = Join-Path $env:TEMP "OMNIAI_Backup_$timestamp"
    if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    try {
        Write-Log "Starting backup to $zipPath"
        # copy project
        if (Test-Path $cfg.BackupProject) {
            Copy-Item -Path $cfg.BackupProject -Destination (Join-Path $tempFolder "project") -Recurse -Force -ErrorAction SilentlyContinue -Exclude "Backups"
        } else {
            Write-Log "Project path not found: $($cfg.BackupProject)" "ERROR"
        }
        # export extensions
        $extFile = Join-Path $tempFolder "vscode-extensions.txt"
        if (Get-Command "code" -ErrorAction SilentlyContinue) { & code --list-extensions | Out-File $extFile -Encoding utf8 }
        # copy settings
        $settings = Join-Path $env:APPDATA "Code\User\settings.json"
        if (Test-Path $settings) { Copy-Item $settings (Join-Path $tempFolder "settings.json") -Force }
        # zip
        if (Test-Path $zipPath) { Remove-Item -Force $zipPath -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $tempFolder "*") -DestinationPath $zipPath -Force
        Write-Log "Backup completed: $zipPath"
        $zipPath | Out-File -FilePath $RestorePathFile -Encoding utf8
        Write-Log "Saved restore path to $RestorePathFile"
        Send-LineNotify "✅ OMNI-AI Backup completed successfully at $(Get-Date). File: $zipName"
        Remove-Item -Recurse -Force $tempFolder -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Log "Backup failed: $($_.Exception.Message)" "ERROR"
        Send-LineNotify "❌ OMNI-AI Backup failed: $($_.Exception.Message)"
        if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder -ErrorAction SilentlyContinue }
        return $false
    }
}

function Run-ScheduledBackup-Wrapper {
    Ensure-Directories
    Create-Backup | Out-Null
    # run crash analyzer asynchronously to avoid blocking GUI
    Start-Job -ScriptBlock { param($pf) 
        try {
            $vlog = Join-Path $env:APPDATA "Code\logs"
            if (Test-Path $vlog) {
                $latest = Get-ChildItem -Path $vlog -Recurse -Filter "main*.log" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latest) {
                    $content = Get-Content -Path $latest.FullName -Raw -ErrorAction SilentlyContinue
                    if ($content -match "Exception|ERROR|Unhandled") {
                        $report = "Crash analysis report - $(Get-Date)`nLog: $($latest.FullName)`n----`n"
                        $report | Out-File -FilePath (Join-Path $pf "AI-Crash-Report.log") -Encoding utf8 -Append
                    }
                }
            }
        } catch { }
    } -ArgumentList $ProjectFolder | Out-Null
}

function Install-Scheduler {
    Ensure-Directories
    $cfg = Load-Config
    $time = $cfg.SchedulerTime
    $psExec = (Get-Command "powershell" -ErrorAction SilentlyContinue).Source
    $scriptFull = Join-Path $ProjectFolder $ScriptName
    $cmd = "schtasks /Create /F /SC DAILY /TN `"$SchedulerName`" /TR `"$psExec -ExecutionPolicy Bypass -File `"$scriptFull`" -RunScheduledBackup`" /ST $time"
    try {
        Write-Log "Creating scheduled task: $SchedulerName at $time"
        cmd.exe /c $cmd | Out-Null
        Write-Log "Scheduled task created."
        Send-LineNotify "OMNI-AI Scheduler installed: $SchedulerName at $time"
        return $true
    } catch {
        Write-Log "Scheduler install failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# GUI with status polling timer
function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "OMNI-AI Extension Manager (v4.2)"
    $form.Size = New-Object System.Drawing.Size(720,380)
    $form.StartPosition = "CenterScreen"

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(12,260)
    $lblStatus.Size = New-Object System.Drawing.Size(680,80)
    $lblStatus.Text = "Status: Ready."

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Location = New-Object System.Drawing.Point(12,12)
    $btnBackup.Size = New-Object System.Drawing.Size(160,40)
    $btnBackup.Text = "Run Backup Now"
    $btnBackup.Add_Click({
        $lblStatus.Text = "Status: Running backup..."
        $form.Refresh()
        Start-Job -ScriptBlock { powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -RunScheduledBackup } | Out-Null
    })

    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Location = New-Object System.Drawing.Point(190,12)
    $btnRestore.Size = New-Object System.Drawing.Size(160,40)
    $btnRestore.Text = "Restore Latest"
    $btnRestore.Add_Click({
        $lblStatus.Text = "Status: Restoring..."
        $form.Refresh()
        Start-Job -ScriptBlock { powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -RunRestoreLatest } | Out-Null
    })

    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Location = New-Object System.Drawing.Point(370,12)
    $btnClean.Size = New-Object System.Drawing.Size(160,40)
    $btnClean.Text = "Clean Old Backups"
    $btnClean.Add_Click({
        $lblStatus.Text = "Status: Cleaning..."
        $form.Refresh()
        Start-Job -ScriptBlock { powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -RunCleanBackups } | Out-Null
    })

    $btnScheduler = New-Object System.Windows.Forms.Button
    $btnScheduler.Location = New-Object System.Drawing.Point(12,70)
    $btnScheduler.Size = New-Object System.Drawing.Size(160,40)
    $btnScheduler.Text = "Install Scheduler"
    $btnScheduler.Add_Click({
        $lblStatus.Text = "Status: Installing scheduler..."
        $form.Refresh()
        Start-Job -ScriptBlock { powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -InstallScheduler } | Out-Null
    })

    $btnTestLine = New-Object System.Windows.Forms.Button
    $btnTestLine.Location = New-Object System.Drawing.Point(190,70)
    $btnTestLine.Size = New-Object System.Drawing.Size(160,40)
    $btnTestLine.Text = "Test LINE Notify"
    $btnTestLine.Add_Click({
        $lblStatus.Text = "Status: Sending LINE test..."
        $form.Refresh()
        Start-Job -ScriptBlock { powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -NoGui } | Out-Null
    })

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Location = New-Object System.Drawing.Point(370,70)
    $btnExit.Size = New-Object System.Drawing.Size(160,40)
    $btnExit.Text = "Exit"
    $btnExit.Add_Click({ $form.Close() })

    # Timer to poll notify status file and update label
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.Add_Tick({
        if (Test-Path $using:NotifyStatusFile) {
            try {
                $text = Get-Content -Path $using:NotifyStatusFile -Raw -ErrorAction SilentlyContinue
                if ($text) { $lblStatus.Text = "Status: " + ($text -split "`n")[-1] }
            } catch {}
        }
    })
    $timer.Start()

    $form.Controls.AddRange(@($btnBackup,$btnRestore,$btnClean,$btnScheduler,$btnTestLine,$btnExit,$lblStatus))
    [void]$form.ShowDialog()
}

# --- Main flow ---
Ensure-Directories
$cfg = Load-Config

if ($RunScheduledBackup) { Run-ScheduledBackup-Wrapper; Write-Output $true; exit }
if ($RunRestoreLatest) { Write-Output (Restore-Latest); exit }
if ($RunCleanBackups) { Write-Output (Clean-OldBackups); exit }
if ($InstallScheduler) { Write-Output (Install-Scheduler); exit }

if ($NoGui -or -not $Host.UI.RawUI.KeyAvailable) {
    Run-ScheduledBackup-Wrapper | Out-Null
    exit
}

Show-GUI
