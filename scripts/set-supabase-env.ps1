[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$AnonKey,
    [Parameter(Mandatory = $true)][string]$ServiceRole,
    [Parameter(Mandatory = $false)][string]$LegacyJwtSecret = "",
    [Parameter(Mandatory = $false)][string]$BucketName = "nextplot",
    [Parameter(Mandatory = $false)][string]$DbUrl = ""
)
$ErrorActionPreference = "Stop"

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

$envFile = ".\.env"
$content = ""
if (Test-Path $envFile) { $content = [System.IO.File]::ReadAllText($envFile) }

$content = Set-DotenvKey -Text $content -Key "SUPABASE_URL" -Value $Url
$content = Set-DotenvKey -Text $content -Key "SUPABASE_ANON_KEY" -Value $AnonKey
$content = Set-DotenvKey -Text $content -Key "SUPABASE_SERVICE_ROLE" -Value $ServiceRole
if (-not [string]::IsNullOrWhiteSpace($LegacyJwtSecret)) {
    $content = Set-DotenvKey -Text $content -Key "SUPABASE_LEGACY_JWT_SECRET" -Value $LegacyJwtSecret
}
$content = Set-DotenvKey -Text $content -Key "SUPABASE_BUCKET_NAME" -Value $BucketName
if (-not [string]::IsNullOrWhiteSpace($DbUrl)) {
    $content = Set-DotenvKey -Text $content -Key "SUPABASE_DB_URL" -Value $DbUrl
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFile, $content, $utf8)
Write-Host ".env updated."
