[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string]$OpenAIKey,
    [Parameter(Mandatory = $false)][string]$Model = "gpt-4o-mini",
    [Parameter(Mandatory = $false)][double]$Temperature = 0.3,
    [Parameter(Mandatory = $false)][int]$MaxTokens = 300,
    [Parameter(Mandatory = $false)][string]$SystemPrompt
)
$ErrorActionPreference = "Stop"

function Set-DotenvKey([string]$Text, [string]$Key, [string]$Value) {
    if ($null -eq $Text) { $Text = "" }
    if ($null -eq $Value) { $Value = "" }
    $escaped = $Value -replace '"', '""'
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

$content = Set-DotenvKey -Text $content -Key "NEXTPLOT_CHAT_ENABLED" -Value "true"
$content = Set-DotenvKey -Text $content -Key "NEXTPLOT_CHAT_DRIVER" -Value "openai"
$content = Set-DotenvKey -Text $content -Key "OPENAI_API_KEY" -Value $OpenAIKey
$content = Set-DotenvKey -Text $content -Key "OPENAI_CHAT_MODEL" -Value $Model
$content = Set-DotenvKey -Text $content -Key "OPENAI_TEMPERATURE" -Value ("{0}" -f $Temperature)
$content = Set-DotenvKey -Text $content -Key "OPENAI_MAX_TOKENS" -Value ("{0}" -f $MaxTokens)
if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
    $content = Set-DotenvKey -Text $content -Key "OPENAI_SYSTEM_PROMPT" -Value $SystemPrompt
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFile, $content, $utf8)
Write-Host ".env updated for AI chat."
