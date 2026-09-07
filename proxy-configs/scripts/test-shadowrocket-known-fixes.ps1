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

# v2.6.16 targeted connectivity assertions.
$adIndex = [array]::IndexOf($active, "DOMAIN-SET,$adUrl,REJECT")
$compatRules = @(
    'DOMAIN-SUFFIX,id6.me,DIRECT',
    'DOMAIN-SUFFIX,cmpassport.com,DIRECT',
    'DOMAIN,amdc.alipay.com,DIRECT',
    'DOMAIN,fp-it.fengkongcloud.com,DIRECT',
    'DOMAIN,kuaishou.httpdns.pro,DIRECT',
    'DOMAIN,httpdns.c.cdnhwc2.com,DIRECT',
    'DOMAIN,oneid.getui.net,DIRECT',
    'DOMAIN,c-gtc.getui.net,DIRECT',
    'DOMAIN,c-oneid.getui.net,DIRECT',
    'DOMAIN,b-gtc.getui.net,DIRECT',
    'DOMAIN,c-gtc.gepush.com,DIRECT',
    'DOMAIN,b-gtc.gepush.com,DIRECT',
    'DOMAIN,c-oneid.gepush.com,DIRECT',
    'DOMAIN,oneid.gepush.com,DIRECT',
    'DOMAIN,c-hzgt2.getui.com,DIRECT',
    'DOMAIN,mtalk.google.com,谷歌服务'
)
foreach ($rule in $compatRules) {
    Assert-True (@($active | Where-Object { $_ -ceq $rule }).Count -eq 1) "Missing/duplicate compatibility rule: $rule"
    Assert-True ([array]::IndexOf($active, $rule) -lt $adIndex) "Compatibility rule is shadowed by advertising list: $rule"
}
$aiRules = @(
    'DOMAIN-SUFFIX,githubcopilot.com,AI',
    'DOMAIN-SUFFIX,cursor.sh,AI',
    'DOMAIN-SUFFIX,cursorapi.com,AI',
    'DOMAIN-SUFFIX,cursor-cdn.com,AI',
    'DOMAIN-SUFFIX,cursorvm.com,AI'
)
foreach ($rule in $aiRules) {
    Assert-True (@($active | Where-Object { $_ -ceq $rule }).Count -eq 1) "Missing/duplicate AI rule: $rule"
}
Assert-True (@($active | Where-Object { $_ -ceq 'DOMAIN-SUFFIX,pscp.tv,Twitter' }).Count -eq 1) 'Missing/duplicate Twitter video rule'
Assert-True (!$active.Contains('AND,((DOMAIN-SUFFIX,xiaohongshu.com),(PROTOCOL,UDP)),REJECT')) 'Stale Xiaohongshu QUIC block remains'
Assert-True (!$active.Contains('AND,((DOMAIN-SUFFIX,weibo.cn),(PROTOCOL,UDP)),REJECT')) 'Broad weibo.cn QUIC block remains'
Assert-True (!$active.Contains('AND,((DOMAIN-SUFFIX,weibo.com),(PROTOCOL,UDP)),REJECT')) 'Broad weibo.com QUIC block remains'

# Reconstruct only the authorized v2.6.16 active-line delta from the immutable
# v2.6.15 revision. Any other changed, removed, or reordered directive fails,
# including YouTube scripts/arguments, DNS, health checks, shared Google routing,
# policy groups, and FINAL=DIRECT.
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$baseline = @(git -C $repoPath show 'c4ac682:proxy-configs/shadowrocket_V26.00.lsr')
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read pre-fix git baseline'
$expected = [Collections.Generic.List[string]]::new()
$weiboUdpRules = @(
    'AND,((DOMAIN,api.weibo.cn),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,mapi.weibo.cn),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,api.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,mapi.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,sdkapp.uve.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,wbapp.uve.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,sdkapp.mob.uve.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,wbapp.mob.uve.weibo.com),(PROTOCOL,UDP)),REJECT',
    'AND,((DOMAIN,new.vip.weibo.cn),(PROTOCOL,UDP)),REJECT'
)
$oldMitm = '*.weibo.cn, *.weibo.com, *.weibo.com.cn, *.weibocdn.com, *.sina.cn, *.sina.com.cn, *.sinaimg.cn, *.sinajs.cn'
$newMitm = 'api.weibo.cn, mapi.weibo.cn, api.weibo.com, mapi.weibo.com, sdkapp.uve.weibo.com, wbapp.uve.weibo.com, sdkapp.mob.uve.weibo.com, wbapp.mob.uve.weibo.com, new.vip.weibo.cn'
foreach ($line in (Get-ActiveLines $baseline)) {
    if ($line -ceq 'AND,((DOMAIN-SUFFIX,weibo.cn),(PROTOCOL,UDP)),REJECT') {
        foreach ($rule in $weiboUdpRules) { $expected.Add($rule) }
        continue
    }
    if ($line -ceq 'AND,((DOMAIN-SUFFIX,weibo.com),(PROTOCOL,UDP)),REJECT' -or
        $line -ceq 'AND,((DOMAIN-SUFFIX,xiaohongshu.com),(PROTOCOL,UDP)),REJECT') { continue }
    $updated = $line
    if ($line.StartsWith('hostname = ')) {
        Assert-True ($line.Contains($oldMitm)) 'v2.6.15 MITM baseline changed'
        $updated = $line.Replace($oldMitm, $newMitm)
    }
    $expected.Add($updated)
    if ($line -ceq 'DOMAIN-SUFFIX,teg.tencent-cloud.net,DIRECT') {
        foreach ($rule in $compatRules) { $expected.Add($rule) }
    }
    if ($line -ceq 'DOMAIN,copilot.microsoft.com,AI') {
        foreach ($rule in $aiRules) { $expected.Add($rule) }
    }
    if ($line -ceq 'DOMAIN-SUFFIX,twitterstat.us,Twitter') { $expected.Add('DOMAIN-SUFFIX,pscp.tv,Twitter') }
}
Assert-True (($expected -join "`n") -ceq ($active -join "`n")) 'Unexpected active configuration change outside authorized fixes'
Write-Output "PASS: $regexChecks US-regex cases; 5 Gemini routes; 16 compatibility rules; 5 AI routes; Twitter video; narrowed QUIC/MITM; complete v2.6.16 scope invariant."
