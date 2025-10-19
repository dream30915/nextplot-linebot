[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $false)][string]$Secret = "",
    [switch]$RelaxSignature
)
$ErrorActionPreference = "Stop"

function Set-DotenvKey([string]$Text, [string]$Key, [string]$Value) {
    if ($null -eq $Text) { $Text = "" }
    if ($null -eq $Value) { $Value = "" }
    $escaped = $Value -replace '"', '\"'
    $pattern = "^{0}\s*=.*$" -f [regex]::Escape($Key)
    if ([regex]::IsMatch($Text, $pattern, 'Multiline')) {
        return [regex]::Replace($Text, $pattern, ("$Key=""{0}""" -f $escaped), 'Multiline')
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Text)) { return "$Key=""$escaped""" }
        else { $nl = [Environment]::NewLine; return ($Text.TrimEnd() + $nl + "$Key=""$escaped""") }
    }
}

$envFile = ".\.env"
$content = ""
if (Test-Path $envFile) { $content = [System.IO.File]::ReadAllText($envFile) }

$content = Set-DotenvKey -Text $content -Key "LINE_CHANNEL_ACCESS_TOKEN" -Value $Token
if (-not [string]::IsNullOrWhiteSpace($Secret)) {
    $content = Set-DotenvKey -Text $content -Key "LINE_CHANNEL_SECRET" -Value $Secret
}
if ($RelaxSignature.IsPresent) {
    $content = Set-DotenvKey -Text $content -Key "LINE_SIGNATURE_RELAXED" -Value "true"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFile, $content, $utf8)
Write-Host ".env updated."