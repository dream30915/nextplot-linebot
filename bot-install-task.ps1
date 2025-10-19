[CmdletBinding()]
param(
    [string]$Token = "",
    [string]$Secret = "",
    [int]$Port = 8000,
    [switch]$AutoPickPort,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "bot-keepalive.ps1"
if (-not (Test-Path $script)) { throw "bot-keepalive.ps1 not found in $PSScriptRoot" }

# Compose args for keepalive
$argParts = @()
if ($Token) { $argParts += ('-LineToken "{0}"' -f $Token) }
if ($Secret) { $argParts += ('-LineSecret "{0}"' -f $Secret) }
$argParts += ('-Port {0}' -f $Port)
if ($AutoPickPort) { $argParts += '-AutoPickPort' }

$psArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $script, ($argParts -join ' ')
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Limited by default to avoid admin requirement
$runLevel = if ($Elevated) { 'Highest' } else { 'Limited' }
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel $runLevel -LogonType Interactive

$taskName = "NextplotLineBotKeepAlive"

$installed = $false
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    $installed = $true
    Write-Host "Scheduled Task '$taskName' installed (RunLevel=$runLevel). It will run at user logon."
}
catch {
    Write-Warning ("Register-ScheduledTask failed: {0}" -f $_.Exception.Message)
    if ($Elevated) {
        throw "Access denied while Elevated. Re-run PowerShell as Administrator and try again, or omit -Elevated and use Startup method."
    }

    # Fallback: schtasks.exe (RunLevel LIMITED, current user)
    try {
        $fullCmd = "powershell.exe $psArgs"
        $quotedFull = '"' + $fullCmd.Replace('"', '\"') + '"'
        schtasks.exe /Create /TN $taskName /SC ONLOGON /RL LIMITED /RU $env:USERNAME /TR $quotedFull /F | Out-Null
        $installed = $true
        Write-Host "Scheduled Task '$taskName' installed via schtasks.exe (RunLevel=LIMITED). It will run at user logon."
    }
    catch {
        throw "Failed to install task via schtasks.exe: $($_.Exception.Message). Use install-startup.ps1 as a no-admin alternative."
    }
}

if (-not $installed) {
    throw "Task installation did not complete. Use install-startup.ps1 (no admin) instead."
}