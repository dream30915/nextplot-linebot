<#
.SYNOPSIS
OMNI-AI Ultimate Fixed v4.2.1 Final - Full features: LINE + Proxy fallback, GUI async, TLS1.2, retry, beep, Google Drive/OneDrive/Webhook uploads.
#>

param(
    [switch]$RunScheduledBackup,
    [switch]$RunRestoreLatest,
    [switch]$RunCleanBackups,
    [switch]$InstallScheduler,
    [switch]$NoGui
)

$ScriptName = "OMNI-AI-Ultimate-Fixed-v4.2.1.ps1"
$ProjectFolder = "C:\Users\msi\Desktop\nextplot-linebot"
$BackupRoot = "$env:USERPROFILE\Documents\OMNI-AI\Backups"
$LogFile = Join-Path $ProjectFolder "OMNI-AI-Backup.log"
$RestorePathFile = Join-Path $ProjectFolder "OMNI-AI-RestorePath.txt"
$ConfigFile = Join-Path $ProjectFolder "OMNI-AI-Config.json"
$CrashReport = Join-Path $ProjectFolder "AI-Crash-Report.log"
$SchedulerName = "OMNI-AI-AutoBackup"
$NotifyStatusFile = Join-Path $ProjectFolder "OMNI-AI-NotifyStatus.txt"

# Force TLS 1.2
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
    # update status file for GUI (last line only)
    "$t $Level $Message" | Out-File -FilePath $NotifyStatusFile -Encoding utf8 -Force
    Write-Output $line
}

function Load-Config {
    if (-not (Test-Path $ConfigFile)) {
        $default = @{
            "LineToken" = "MzlxATDrbgU5D84zanluRvP/kgYSyIQZyA10SOtFENVzncFKGkBbkqXZ1oEqBWAgVn7rycxfaq7JMHAbRJGUxpG3aj74S/yhFiqi/fplP7YPADGs16gX1rCSPpYK1UAvP8xSWS7GfydFd2pN4ucr2wdB04t89/1O/w1cDnyilFU=";
            "FallbackWebhook" = "https://proxy.omni-ai.app/line";
            "KeepDays" = 7;
            "BackupProject" = $ProjectFolder;
            "BackupRoot" = $BackupRoot;
            "SchedulerTime" = "02:00";
            "GoogleDriveEnabled" = $true;
            "GoogleDriveServiceKey" = "C:\\Users\\msi\\Desktop\\service-account.json";
            "OneDriveEnabled" = $true;
            "OneDriveAccessToken" = "<<<PUT_YOUR_ONEDRIVE_TOKEN_HERE>>>";
            "OneDriveUploadFolder" = "Backups/OMNI-AI";
            "WebhookBackupEnabled" = $true;
            "WebhookBackup" = "https://your-webhook-url-here";
        } | ConvertTo-Json -Depth 6
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
            Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
            Write-Log "[LINE-FALLBACK] Notified via proxy: $uri"
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
        return $false
    }
    if (Test-Network) {
        $ok = Send-LineNotify-Main -Message $Message -Token $token
        if ($ok) { Write-Log "LINE sent via main"; return $true }
        Write-Log "Main LINE failed; trying fallback." "WARN"
    } else {
        Write-Log "Skipping main LINE due to DNS failure." "WARN"
    }
    if ($fallback -and ($fallback -ne "")) {
        $ok2 = Send-LineNotify-Fallback -Message $Message -FallbackUrl $fallback
        if ($ok2) { Write-Log "LINE sent via fallback proxy"; return $true }
    }
    Write-Log "All LINE notify attempts failed." "ERROR"
    return $false
}

# Upload helpers
function Upload-To-GoogleDrive {
    param([string]$FilePath, [string]$ServiceKeyPath)
    # Prefer gdrive CLI if available (https://github.com/gdrive-org/gdrive)
    if (Get-Command "gdrive" -ErrorAction SilentlyContinue) {
        try {
            & gdrive upload --parent root "$FilePath" | Out-Null
            Write-Log "Uploaded $FilePath to Google Drive using gdrive CLI."
            return $true
        } catch {
            Write-Log "gdrive upload failed: $($_.Exception.Message)" "ERROR"
            return $false
        }
    } else {
        Write-Log "gdrive CLI not found. Please install gdrive or rclone for Google Drive uploads." "WARN"
        return $false
    }
}

function Upload-To-OneDrive {
    param([string]$FilePath, [string]$AccessToken, [string]$RemoteFolder)
    if (-not $AccessToken -or $AccessToken -match "<<<") { Write-Log "OneDrive token missing." "WARN"; return $false }
    try {
        $fileName = Split-Path $FilePath -Leaf
        $uploadPath = "/me/drive/root:/$RemoteFolder/$fileName:/content"
        $uri = "https://graph.microsoft.com/v1.0$uploadPath"
        Invoke-RestMethod -Uri $uri -Method Put -InFile $FilePath -Headers @{ Authorization = "Bearer $AccessToken" } -ErrorAction Stop | Out-Null
        Write-Log "Uploaded $fileName to OneDrive folder $RemoteFolder"
        return $true
    } catch {
        Write-Log "OneDrive upload failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Upload-To-Webhook {
    param([string]$FilePath, [string]$WebhookUrl)
    if (-not $WebhookUrl -or $WebhookUrl -match "your-webhook") { Write-Log "Webhook URL missing or placeholder." "WARN"; return $false }
    try {
        # Try multipart/form-data if available (Discord/Slack)
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","OMNI-AI/1.0")
        $wc.Headers.Add("Content-Type","application/octet-stream")
        $wc.UploadData($WebhookUrl, "POST", $fileBytes) | Out-Null
        Write-Log "Uploaded $FilePath to webhook $WebhookUrl (raw POST)"
        return $true
    } catch {
        Write-Log "Webhook upload failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
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
        if (Test-Path $cfg.BackupProject) {
            Copy-Item -Path $cfg.BackupProject -Destination (Join-Path $tempFolder "project") -Recurse -Force -ErrorAction SilentlyContinue -Exclude "Backups"
        } else {
            Write-Log "Project path not found: $($cfg.BackupProject)" "ERROR"
        }
        $extFile = Join-Path $tempFolder "vscode-extensions.txt"
        if (Get-Command "code" -ErrorAction SilentlyContinue) { & code --list-extensions | Out-File $extFile -Encoding utf8 }
        $settings = Join-Path $env:APPDATA "Code\User\settings.json"
        if (Test-Path $settings) { Copy-Item $settings (Join-Path $tempFolder "settings.json") -Force }
        if (Test-Path $zipPath) { Remove-Item -Force $zipPath -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $tempFolder "*") -DestinationPath $zipPath -Force
        Write-Log "Backup completed: $zipPath"
        $zipPath | Out-File -FilePath $RestorePathFile -Encoding utf8
        Write-Log "Saved restore path to $RestorePathFile"
        # Notify
        Send-LineNotify "✅ OMNI-AI Backup completed successfully at $(Get-Date). File: $zipName"
        # Uploads
        if ($cfg.GoogleDriveEnabled) {
            Write-Log "Google Drive upload enabled. Attempting upload..."
            Upload-To-GoogleDrive -FilePath $zipPath -ServiceKeyPath $cfg.GoogleDriveServiceKey | Out-Null
        }
        if ($cfg.OneDriveEnabled) {
            Write-Log "OneDrive upload enabled. Attempting upload..."
            Upload-To-OneDrive -FilePath $zipPath -AccessToken $cfg.OneDriveAccessToken -RemoteFolder $cfg.OneDriveUploadFolder | Out-Null
        }
        if ($cfg.WebhookBackupEnabled) {
            Write-Log "Webhook upload enabled. Attempting upload..."
            Upload-To-Webhook -FilePath $zipPath -WebhookUrl $cfg.WebhookBackup | Out-Null
        }
        # beep
        try { [console]::beep(800,200) } catch {}
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

# GUI
function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "OMNI-AI Extension Manager (v4.2.1 Final)"
    $form.Size = New-Object System.Drawing.Size(760,420)
    $form.StartPosition = "CenterScreen"

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(12,300)
    $lblStatus.Size = New-Object System.Drawing.Size(720,80)
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

    # Polling timer (closure reads $NotifyStatusFile from outer scope)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1500
    $timer.Add_Tick({
        try {
            if (Test-Path $NotifyStatusFile) {
                $text = Get-Content -Path $NotifyStatusFile -Raw -ErrorAction SilentlyContinue
                if ($text) { $lblStatus.Text = "Status: " + ($text -split "`n")[-1] }
            }
        } catch {}
    })
    $timer.Start()

    $form.Controls.AddRange(@($btnBackup,$btnRestore,$btnClean,$btnScheduler,$btnTestLine,$btnExit,$lblStatus))
    [void]$form.ShowDialog()
}

# Main
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
