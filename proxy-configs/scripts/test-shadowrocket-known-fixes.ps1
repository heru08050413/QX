# Requires PowerShell 7. Run from any directory; no network or subscription needed.
# Static regression checks, NOT a Shadowrocket/iPhone runtime test.
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../shadowrocket_V26.00.lsr')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Get-ActiveLines([string[]]$Lines) {
    @($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[#;]' })
}

$lines = @(Get-Content -LiteralPath $ConfigPath -Encoding utf8)
$active = @(Get-ActiveLines $lines)
$usGroups = @('YT-美国节点', '美国节点', '美国稳定')
$positive = @('US', 'USA', 'us-01', 'US01', 'USA01', '机场-US-01',
    '美国01', '🇺🇸 01', 'United States 01', 'America 01', '洛杉矶01', 'SiliconValley')
$negative = @('Russia', 'RUS-01', 'Australia', 'AUS-01', 'RUS01', 'AUS01',
    'Austria', '🇦🇺 Sydney', 'JP 日本', 'HK 香港', 'Business 01', 'Plus 01')
$regexChecks = 0
foreach ($group in $usGroups) {
    $matchesGroup = @($active | Where-Object { $_.StartsWith("$group = ") })
    Assert-True ($matchesGroup.Count -eq 1) "Missing/duplicate group: $group"
    $pattern = ($matchesGroup[0] -split 'policy-regex-filter=', 2)[1]
    foreach ($name in $positive) {
        Assert-True ([regex]::IsMatch($name, $pattern)) "$group excludes US fixture: $name"
        $regexChecks++
    }
    foreach ($name in $negative) {
        Assert-True (![regex]::IsMatch($name, $pattern)) "$group admits non-US fixture: $name"
        $regexChecks++
    }
}

$domains = @('geller-pa.googleapis.com', 'robinfrontend-pa.googleapis.com',
    'gemini.gstatic.com', 'alkalicore-pa.clients6.google.com',
    'webchannel-alkalimakersuite-pa.clients6.google.com')
$googleRules = @($active | Where-Object { $_ -match '^RULE-SET,.*/Google/Google\.list,谷歌服务$' })
Assert-True ($googleRules.Count -eq 1) 'Expected one general Google ruleset'
$googleIndex = [array]::IndexOf($active, $googleRules[0])
foreach ($domain in $domains) {
    $rule = "DOMAIN,$domain,Gemini"
    Assert-True (@($active | Where-Object { $_ -ceq $rule }).Count -eq 1) "Missing/duplicate rule: $rule"
    Assert-True ([array]::IndexOf($active, $rule) -lt $googleIndex) "Rule shadowed by general Google: $rule"
}
$adUrl = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/Advertising/Advertising_Domain.list'
$adRules = @($active | Where-Object { $_.Contains($adUrl) })
Assert-True ($adRules.Count -eq 1 -and $adRules[0] -ceq "DOMAIN-SET,$adUrl,REJECT") 'Wrong domain-list import type'

# Reconstruct only the authorized active-line delta from the immutable pre-fix revision.
# Any other changed, removed, or reordered directive fails this test (including DNS,
# scripts/arguments, MITM, health checks, shared Google routing, and final DIRECT).
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$baseline = @(git -C $repoPath show '1b42bd097fe38c3b33636968bfa5bae46805278a:proxy-configs/shadowrocket_V26.00.lsr')
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read pre-fix git baseline'
$expected = [Collections.Generic.List[string]]::new()
$changedGroups = 0
foreach ($line in (Get-ActiveLines $baseline)) {
    $updated = $line
    foreach ($group in $usGroups) {
        if ($line.StartsWith("$group = ")) {
            $updated = $line.Replace('|US|USA|', '|(?:^|[^A-Za-z])(?:US|USA)(?=$|[^A-Za-z])|')
            Assert-True ($updated -cne $line) "Baseline US pattern changed: $group"
            $changedGroups++
        }
    }
    if ($line -ceq "RULE-SET,$adUrl,REJECT") { $updated = "DOMAIN-SET,$adUrl,REJECT" }
    $expected.Add($updated)
    if ($line -ceq 'DOMAIN,proactivebackend-pa.googleapis.com,Gemini') {
        foreach ($domain in $domains) { $expected.Add("DOMAIN,$domain,Gemini") }
    }
}
Assert-True ($changedGroups -eq 3) 'Expected exactly three US pool fixes'
Assert-True (($expected -join "`n") -ceq ($active -join "`n")) 'Unexpected active configuration change outside authorized fixes'
Write-Output "PASS: $regexChecks regex cases; 5 Gemini routes; DOMAIN-SET type; complete active-line scope invariant."
