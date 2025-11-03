<#
.SYNOPSIS
OMNI-AI Ultimate Fixed v4.1 - Enhanced with Network Check, TLS1.2, Retry, Async GUI.
#>

param(
    [switch]$RunScheduledBackup,
    [switch]$RunRestoreLatest,
    [switch]$RunCleanBackups,
    [switch]$InstallScheduler,
    [switch]$NoGui
)

$ScriptName = "OMNI-AI-Ultimate-Fixed-v4.1.ps1"
$ProjectFolder = "C:\Users\msi\Desktop\nextplot-linebot"
$BackupRoot = "$env:USERPROFILE\Documents\OMNI-AI\Backups"
$LogFile = Join-Path $ProjectFolder "OMNI-AI-Backup.log"
$RestorePathFile = Join-Path $ProjectFolder "OMNI-AI-RestorePath.txt"
$ConfigFile = Join-Path $ProjectFolder "OMNI-AI-Config.json"
$SchedulerName = "OMNI-AI-AutoBackup"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$t [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Encoding utf8 -Append
    Write-Output $line
}

function Ensure-Directories {
    if (-not (Test-Path $ProjectFolder)) { New-Item -Path $ProjectFolder -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $BackupRoot)) { New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null }
}

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
    }
    return (Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json)
}

function Test-Network {
    Write-Log "Testing network connectivity..."
    try {
        $ping = Test-Connection -ComputerName "notify-api.line.me" -Count 1 -ErrorAction SilentlyContinue
        if ($ping) { Write-Log "Network OK."; return $true }
        else { Write-Log "Network test failed: notify-api.line.me unreachable" "WARN"; return $false }
    } catch {
        Write-Log "Network check exception: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Send-LineNotify {
    param([string]$Message)
    $cfg = Load-Config
    $token = $cfg.LineToken
    if (-not $token -or $token -match "<YOUR_LINE_TOKEN_HERE>") { Write-Log "LINE token not configured." "WARN"; return $false }
    if (-not (Test-Network)) { Write-Log "Skipping LINE notify - Network unavailable." "WARN"; return $false }
    $uri = "https://notify-api.line.me/api/notify"
    $headers = @{ "Authorization" = "Bearer $token" }
    $body = @{ "message" = $Message }
    for ($i=1; $i -le 3; $i++) {
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
            Write-Log "LINE notified successfully."
            return $true
        } catch {
            Write-Log "LINE notify attempt $i failed: $($_.Exception.Message)" "WARN"
            Start-Sleep -Seconds 3
        }
    }
    Write-Log "LINE notify failed after 3 attempts." "ERROR"
    return $false
}

function Create-Backup {
    Ensure-Directories
    $cfg = Load-Config
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zipPath = Join-Path $cfg.BackupRoot "Backup_$timestamp.zip"
    $tempFolder = Join-Path $env:TEMP "OMNIAI_Backup_$timestamp"
    if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    try {
        Write-Log "Starting backup: $zipPath"
        Copy-Item -Path $cfg.BackupProject -Destination (Join-Path $tempFolder "project") -Recurse -Force -ErrorAction SilentlyContinue -Exclude "Backups"
        $extFile = Join-Path $tempFolder "vscode-extensions.txt"
        if (Get-Command "code" -ErrorAction SilentlyContinue) { & code --list-extensions | Out-File $extFile -Encoding utf8 }
        $settings = Join-Path $env:APPDATA "Code\User\settings.json"
        if (Test-Path $settings) { Copy-Item $settings (Join-Path $tempFolder "settings.json") -Force }
        Compress-Archive -Path "$tempFolder\*" -DestinationPath $zipPath -Force
        $zipPath | Out-File -FilePath $RestorePathFile -Encoding utf8
        Write-Log "Backup completed successfully: $zipPath"
        Send-LineNotify "✅ OMNI-AI Backup completed successfully at $(Get-Date). File: $(Split-Path $zipPath -Leaf)"
        Remove-Item -Recurse -Force $tempFolder
        return $true
    } catch {
        Write-Log "Backup failed: $($_.Exception.Message)" "ERROR"
        Send-LineNotify "❌ OMNI-AI Backup failed: $($_.Exception.Message)"
        if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
        return $false
    }
}

function Run-ScheduledBackup-Wrapper {
    Ensure-Directories
    Create-Backup | Out-Null
}

function Show-GUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "OMNI-AI Extension Manager (v4.1)"
    $form.Size = New-Object System.Drawing.Size(700,360)
    $form.StartPosition = "CenterScreen"

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(10,250)
    $lbl.Size = New-Object System.Drawing.Size(650,60)
    $lbl.Text = "Status: Ready."

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = "Run Backup Now"
    $btnBackup.Size = New-Object System.Drawing.Size(160,40)
    $btnBackup.Location = New-Object System.Drawing.Point(10,10)
    $btnBackup.Add_Click({
        $lbl.Text = "Status: Running backup..."
        Start-Job -ScriptBlock {
            powershell -ExecutionPolicy Bypass -File "$using:ScriptName" -RunScheduledBackup
        } | Out-Null
    })

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit"
    $btnExit.Size = New-Object System.Drawing.Size(160,40)
    $btnExit.Location = New-Object System.Drawing.Point(10,70)
    $btnExit.Add_Click({ $form.Close() })

    $form.Controls.AddRange(@($btnBackup,$btnExit,$lbl))
    [void]$form.ShowDialog()
}

Ensure-Directories
if ($RunScheduledBackup) { Run-ScheduledBackup-Wrapper; exit }
if (-not $NoGui) { Show-GUI }
