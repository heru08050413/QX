# Requires PowerShell 7. Run from any directory; no network or subscription needed.
# Static regression checks, NOT a Shadowrocket/iPhone runtime test.
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../shadowrocket_V26.00.lsr'),
    [string]$ConfigText
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Get-ActiveLines([string[]]$Lines) {
    @($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[#;]' })
}

$lines = if ($PSBoundParameters.ContainsKey('ConfigText')) { @($ConfigText -split '\r?\n') }
    else { @(Get-Content -LiteralPath $ConfigPath -Encoding utf8) }
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

# Reconstruct the authorized v2.6.16 active-line delta from the immutable
# v2.6.15 revision. Any other changed, removed, or reordered directive fails,
# after applying the explicitly enumerated v2.6.17 delta below.
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
# Keep the previous change-set verifiable; do not silently replace its baseline.
$previous = @(Get-ActiveLines @(git -C $repoPath show '8860378:proxy-configs/shadowrocket_V26.00.lsr'))
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read v2.6.16 baseline'
Assert-True (($expected -join "`n") -ceq ($previous -join "`n")) 'Historical v2.6.16 invariant failed'

$retired = @(
    'DOMAIN-SUFFIX,biz.weibo.com,REJECT',
    'DOMAIN,bootpreload.uve.weibo.com,REJECT',
    'DOMAIN-SUFFIX,fastimage.uve.weibo.com,REJECT',
    'DOMAIN-SUFFIX,adimg.vue.weibo.com,REJECT',
    'DOMAIN-SUFFIX,sdkapp.uve.weibo.com,REJECT'
)
$imageRules = @(
    'DOMAIN,fastimage.uve.weibo.com,REJECT',
    'DOMAIN,adimg.uve.weibo.com,REJECT',
    'DOMAIN,adimg.vue.weibo.com,REJECT'
)
$currentExpected = [Collections.Generic.List[string]]::new()
foreach ($line in $expected) {
    if ($retired -ccontains $line) { continue }
    if ($line -ceq 'DOMAIN-SUFFIX,weibo.cn,DIRECT') {
        foreach ($rule in $imageRules) { $currentExpected.Add($rule) }
    }
    if ($line -ceq 'DOMAIN-SUFFIX,weixin.qq.com.cn,DIRECT') {
        $currentExpected.Add('DOMAIN,dns.weixin.qq.com,DIRECT')
    }
    $updated = $line
    if ($line -match '^YT-.+ = ') {
        $updated = $line.Replace('url=http://www.gstatic.com/', 'url=https://www.gstatic.com/')
    }
    if ($line -match '^(美国|日本|新加坡)稳定 = ') {
        $updated = $line.Replace('= url-test, url=http://cp.cloudflare.com/generate_204, interval=900, tolerance=300, timeout=3,',
            '= fallback, url=https://cp.cloudflare.com/generate_204, interval=300, timeout=5,')
    }
    $currentExpected.Add($updated)
}
Assert-True (($currentExpected -join "`n") -ceq ($active -join "`n")) 'Unexpected active configuration change outside authorized fixes'

# Check relevant rule ordering independently of the full delta comparison.
$ruleStart = [array]::IndexOf($active, '[Rule]')
$hostStart = [array]::IndexOf($active, '[Host]')
Assert-True ($ruleStart -ge 0 -and $hostStart -gt $ruleStart) 'Missing Rule/Host sections'
$rules = @($active[($ruleStart + 1)..($hostStart - 1)])
function First-LocalDomainRule([string]$Domain) {
    foreach ($rule in $rules) {
        $parts = $rule -split ','
        if ($parts[0] -ceq 'DOMAIN' -and $Domain -ceq $parts[1]) { return $rule }
        if ($parts[0] -ceq 'DOMAIN-SUFFIX' -and
            ($Domain -ceq $parts[1] -or $Domain.EndsWith('.' + $parts[1]))) { return $rule }
    }
    return ''
}
foreach ($rule in $imageRules) {
    $domain = ($rule -split ',')[1]
    Assert-True ((First-LocalDomainRule $domain) -ceq $rule) "Image rejection shadowed: $domain"
}
foreach ($domain in @('sdkapp.uve.weibo.com', 'wbapp.uve.weibo.com', 'api.weibo.cn',
    'mapi.weibo.com', 'bootpreload.uve.weibo.com', 'wx1.sinaimg.cn', 'video.weibocdn.com')) {
    Assert-True ((First-LocalDomainRule $domain).EndsWith(',DIRECT')) "Business/media host blocked: $domain"
}
$firstAd = [array]::IndexOf($active, ($active | Where-Object { $_ -match '^RULE-SET,.*/Advertising/Advertising\.list,REJECT$' } | Select-Object -First 1))
Assert-True ($firstAd -ge 0) 'Advertising ruleset not found'
Assert-True ([array]::IndexOf($active, 'DOMAIN,dns.weixin.qq.com,DIRECT') -lt $firstAd) 'WeChat DNS protection too late'
Assert-True (!$active.Contains('DOMAIN-SUFFIX,weixin.qq.com,DIRECT') -or
    [array]::IndexOf($active, 'DOMAIN-SUFFIX,weixin.qq.com,DIRECT') -gt $firstAd) 'WeChat ads bypass the advertising list'

$ytGroups = @($active | Where-Object { $_ -match '^YT-.+ = ' })
Assert-True ($ytGroups.Count -eq 6) 'YouTube must retain five region pools plus outer fallback'
foreach ($group in $ytGroups) {
    Assert-True ($group.Contains('url=https://www.gstatic.com/generate_204')) 'YouTube probe is not HTTPS'
    Assert-True (!$group.Contains('DIRECT')) 'YouTube pool unexpectedly contains DIRECT'
}
foreach ($name in @('美国稳定', '日本稳定', '新加坡稳定')) {
    $group = @($active | Where-Object { $_.StartsWith("$name = ") })
    Assert-True ($group.Count -eq 1 -and $group[0].Contains('= fallback,') -and
        $group[0].Contains('interval=300, timeout=5')) "Invalid stable pool: $name"
}
$ytScripts = @($active | Where-Object { $_ -match '^YouTube\.(response|request\.(init|log_event)) = ' })
Assert-True ($ytScripts.Count -eq 3) 'YouTube hook count changed'
Assert-True ($ytScripts[0].Contains('"blockUpload":true')) 'Upload-button hiding disabled'
foreach ($hook in $ytScripts) {
    Assert-True ($hook.Contains('/65075cdb388fc5e3094afd7e7314c67b243f3525/')) 'YouTube script pin changed'
    Assert-True ($hook.Contains('engine=webview') -and $hook.Contains('binary-body-mode=1')) 'YouTube binary runtime changed'
}
Write-Output "PASS: $regexChecks US-regex cases; legacy Gemini/AI/compatibility checks; 10 Weibo routing fixtures; WeChat DNS order; 6 HTTPS YouTube probes; 3 stable fallback pools; unchanged YouTube hooks; complete v2.6.16 + v2.6.17 scope invariants."
