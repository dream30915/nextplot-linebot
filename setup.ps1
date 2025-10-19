# ASCII-only setup: install cloudflared and add to PATH (User)
$ErrorActionPreference = "Stop"

$dir = "C:\Tools\cloudflared"
$cf = Join-Path $dir "cloudflared.exe"

# 1) Ensure directory
if (-not (Test-Path $dir)) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# 2) Download cloudflared if missing
if (-not (Test-Path $cf)) {
  Write-Host "Downloading cloudflared..."
  $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
  Invoke-WebRequest -Uri $url -OutFile $cf
}
else {
  Write-Host "cloudflared already exists at $cf"
}

# 3) Add to user PATH (effective for NEW terminals)
try {
  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not $current) { $current = "" }
  $pathParts = $current.Split(";") | Where-Object { $_ -and $_.Trim().Length -gt 0 }
  $hasEntry = $false
  foreach ($p in $pathParts) {
    if ([String]::Compare($p.TrimEnd("\"), $dir.TrimEnd("\"), $true) -eq 0) { $hasEntry = $true; break }
  }
  if (-not $hasEntry) {
    $newPath = ($current.TrimEnd(";") + ";" + $dir)
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "PATH updated for User. Open a NEW PowerShell window to use 'cloudflared' by name."
  }
  else {
    Write-Host "PATH already contains $dir"
  }
}
catch {
  Write-Warning "Failed to update PATH via .NET API: $($_.Exception.Message)"
  Write-Host "Trying fallback 'setx' ..."
  try {
    setx PATH "$env:PATH;$dir" | Out-Null
    Write-Host "PATH updated via setx (restart terminal to take effect)."
  }
  catch {
    Write-Warning "Fallback 'setx' failed: $($_.Exception.Message)"
  }
}

# 4) Print versions
try {
  & "$cf" --version
}
catch {
  Write-Warning "cloudflared exists but could not run. Try: & `"$cf`" --version"
}

Write-Host "setup.ps1 done."