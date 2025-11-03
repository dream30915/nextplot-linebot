[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string]$DbPassword,
    [Parameter(Mandatory = $false)][string]$ProjectRef = "",
    [Parameter(Mandatory = $false)][string]$Url = ""
)
$ErrorActionPreference = "Stop"

function Get-ProjectRefFromUrl([string]$inputUrl) {
    if ([string]::IsNullOrWhiteSpace($inputUrl)) { return "" }
    try {
        $u = [System.Uri]::new($inputUrl)
        $host = $u.Host # e.g. xhcogxcmljnczwybqvia.supabase.co
        if ($host -like "*.supabase.co") {
            $parts = $host.Split('.')
            # host could be xhcogxcmljnczwybqvia.supabase.co -> first part is ref
            if ($parts.Length -ge 3) { return $parts[0] }
        }
        return ""
    } catch { return "" }
}

function Set-DotenvKey([string]$Text, [string]$Key, [string]$Value) {
    if ($null -eq $Text) { $Text = '' }
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value -replace '"', '""'
    $pattern = "^{0}\s*=.*$" -f [regex]::Escape($Key)
    $replacement = ($Key + '="' + $escaped + '"')
    if ([regex]::IsMatch($Text, $pattern, 'Multiline')) {
        return [regex]::Replace($Text, $pattern, $replacement, 'Multiline')
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $replacement }
        else { $nl = [Environment]::NewLine; return ($Text.TrimEnd() + $nl + $replacement) }
    }
}

# Try to derive project ref if not provided
if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
    # 1) Try from -Url if provided
    $ProjectRef = Get-ProjectRefFromUrl -inputUrl $Url
}
if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
    # 2) Try from existing .env SUPABASE_URL
    $envFile = ".\.env"
    if (Test-Path $envFile) {
        $content = [System.IO.File]::ReadAllText($envFile)
    # Use single-quoted regex for PS 5.1 compatibility; accept optional quotes around value
    # Note: In single-quoted PowerShell strings, backslash is literal, so use \s as \s? No — use single backslash.
    $m = [regex]::Match($content, '(?m)^SUPABASE_URL\s*=\s*"?(?<u>[^"\r\n]+)"?')
        if ($m.Success) { $ProjectRef = Get-ProjectRefFromUrl -inputUrl $m.Groups['u'].Value }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
    Write-Error "Cannot derive ProjectRef. Provide -ProjectRef or -Url or ensure SUPABASE_URL exists in .env"
}

# Build DB URL
$encPwd = [System.Uri]::EscapeDataString($DbPassword)
$dbHost = "db.$ProjectRef.supabase.co"
$dbUrl = "postgresql://postgres:$encPwd@$dbHost:5432/postgres?sslmode=require"

# Write to .env
$envFile = ".\.env"
$content = ""
if (Test-Path $envFile) { $content = [System.IO.File]::ReadAllText($envFile) }
$content = Set-DotenvKey -Text $content -Key "SUPABASE_DB_URL" -Value $dbUrl

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFile, $content, $utf8)

# Print minimal confirmation without leaking password
Write-Host "SUPABASE_DB_URL set for host: $dbHost"
