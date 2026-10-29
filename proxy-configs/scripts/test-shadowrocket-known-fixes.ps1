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
$usGroups = @('美国节点', '美国稳定')
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
# after applying the explicitly enumerated v2.6.17 / v2.6.18 / v2.6.19 deltas below.
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
# Preserve the v2.6.17 invariant against its immutable pre-change revision.
$v2617 = @(Get-ActiveLines @(git -C $repoPath show 'e6f119a37596653d03a0da9d895ce91a723bdb4f:proxy-configs/shadowrocket_V26.00.lsr'))
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read v2.6.17 baseline'
Assert-True (($currentExpected -join "`n") -ceq ($v2617 -join "`n")) 'Historical v2.6.17 invariant failed'

# v2.6.18: exactly six interval edits; no group membership or other directive changes.
$ytRegionNames = @('YT-香港节点', 'YT-台湾节点', 'YT-日本节点', 'YT-新加坡节点', 'YT-美国节点')
$v2618Expected = [Collections.Generic.List[string]]::new()
$intervalEdits = 0
foreach ($line in $currentExpected) {
    $name = ($line -split ' = ', 2)[0]
    $updated = $line
    if ($ytRegionNames -ccontains $name) {
        Assert-True ($line.Contains(', interval=120, tolerance=300, timeout=5,')) "Unexpected region baseline: $name"
        $updated = $line.Replace(', interval=120,', ', interval=30,')
        $intervalEdits++
    } elseif ($name -ceq 'YT-Auto') {
        Assert-True ($line.EndsWith(', interval=60, timeout=5')) 'Unexpected outer fallback baseline'
        $updated = $line.Replace(', interval=60,', ', interval=30,')
        $intervalEdits++
    }
    $v2618Expected.Add($updated)
}
Assert-True ($intervalEdits -eq 6) 'Expected exactly six YouTube interval edits'
$v2618 = @(Get-ActiveLines @(git -C $repoPath show 'bedea9364b324e240a36ceb6344388b022650967:proxy-configs/shadowrocket_V26.00.lsr'))
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read v2.6.18 baseline'
Assert-True (($v2618Expected -join "`n") -ceq ($v2618 -join "`n")) 'Historical v2.6.18 invariant failed'

# v2.6.19: allowlisted selector defaults, Google/Gemini linkage and Meta coverage.
$replacements19 = @{
    'Proxy = select, AutoSelect, StableSelect, 香港节点, 台湾节点, 日本节点, 新加坡节点, 美国节点, DIRECT' = 'Proxy = select, 美国节点, AutoSelect, StableSelect, 香港节点, 台湾节点, 日本节点, 新加坡节点, DIRECT'
    'AI = select, 新加坡节点, 美国节点, 日本节点, AutoSelect' = 'AI = select, 美国节点, 新加坡节点, 日本节点, AutoSelect'
    'Gemini = select, 美国节点, 台湾节点, 日本节点, 新加坡节点, AutoSelect' = 'Gemini = select, 谷歌服务'
    'Netflix = select, 香港节点, 日本节点, 新加坡节点, 美国节点' = 'Netflix = select, 美国节点, 香港节点, 日本节点, 新加坡节点'
    'TikTok = select, 日本节点, 台湾节点, 新加坡节点, 美国节点' = 'TikTok = select, 美国节点, 日本节点, 台湾节点, 新加坡节点'
    'Telegram = select, 新加坡节点, 香港节点, 日本节点, 美国节点, AutoSelect' = 'Telegram = select, 美国节点, 新加坡节点, 香港节点, 日本节点, AutoSelect'
    '苹果服务 = select, DIRECT, 美国节点, 香港节点' = '苹果服务 = select, 美国节点, DIRECT, 香港节点'
    '谷歌服务 = select, AutoSelect, YT-Auto, 香港节点, 台湾节点, 日本节点, 新加坡节点, 美国节点' = '谷歌服务 = select, 美国节点, AutoSelect, YT-Auto, 香港节点, 台湾节点, 日本节点, 新加坡节点'
    '微软服务 = select, DIRECT, 美国节点, 香港节点' = '微软服务 = select, 美国节点, DIRECT, 香港节点'
    'YT-Auto = fallback, YT-香港节点, YT-台湾节点, YT-日本节点, YT-新加坡节点, YT-美国节点, url=https://www.gstatic.com/generate_204, interval=30, timeout=5' = 'YT-Auto = fallback, YT-美国节点, YT-香港节点, YT-台湾节点, YT-日本节点, YT-新加坡节点, url=https://www.gstatic.com/generate_204, interval=30, timeout=5'
    'DOMAIN-SUFFIX,facebook.com,Proxy' = 'DOMAIN-SUFFIX,facebook.com,Meta'
    'DOMAIN-SUFFIX,fbcdn.net,Proxy' = 'DOMAIN-SUFFIX,fbcdn.net,Meta'
    'DOMAIN-SUFFIX,fb.com,Proxy' = 'DOMAIN-SUFFIX,fb.com,Meta'
    'DOMAIN-SUFFIX,whatsapp.com,Proxy' = 'DOMAIN-SUFFIX,whatsapp.com,Meta'
    'DOMAIN-SUFFIX,whatsapp.net,Proxy' = 'DOMAIN-SUFFIX,whatsapp.net,Meta'
}
$metaRules = @('DOMAIN-SUFFIX,muse.ai,Meta', 'DOMAIN-SUFFIX,meta.ai,Meta', 'DOMAIN-SUFFIX,meta.com,Meta')
$googleCoreRules = @('DOMAIN-SUFFIX,google.com,谷歌服务', 'DOMAIN-SUFFIX,googleapis.com,谷歌服务',
    'DOMAIN-SUFFIX,gstatic.com,谷歌服务', 'DOMAIN-SUFFIX,googleusercontent.com,谷歌服务')
$googleAuthRules = @('DOMAIN,accounts.google.com,谷歌服务', 'DOMAIN,oauth2.googleapis.com,谷歌服务',
    'DOMAIN,securetoken.googleapis.com,谷歌服务', 'DOMAIN,identitytoolkit.googleapis.com,谷歌服务')
$v2619Expected = [Collections.Generic.List[string]]::new()
$replaced19 = 0
foreach ($line in $v2618Expected) {
    if ($line -ceq 'DOMAIN-SUFFIX,instagram.com,Instagram') {
        foreach ($rule in $metaRules) { $v2619Expected.Add($rule) }
    }
    if ($line -ceq $googleRules[0]) {
        foreach ($rule in $googleCoreRules) { $v2619Expected.Add($rule) }
    }
    if ($replacements19.ContainsKey($line)) {
        $v2619Expected.Add($replacements19[$line])
        $replaced19++
    } else { $v2619Expected.Add($line) }
    if ($line -ceq 'DOMAIN,webchannel-alkalimakersuite-pa.clients6.google.com,Gemini') {
        foreach ($rule in $googleAuthRules) { $v2619Expected.Add($rule) }
    }
    if ($line.StartsWith('Gemini = ')) {
        $v2619Expected.Add('Meta = select, 美国节点, 香港节点, 台湾节点, 日本节点, 新加坡节点, AutoSelect')
    }
}
Assert-True ($replaced19 -eq 15 -and $v2619Expected.Count -eq $v2618Expected.Count + 12) 'Unexpected v2.6.19 delta size'
$v2619 = @(Get-ActiveLines @(git -C $repoPath show 'c6a9ac4fafdb6080bae386b33da6c8197b6ee41c:proxy-configs/shadowrocket_V26.00.lsr'))
Assert-True ($LASTEXITCODE -eq 0) 'Cannot read v2.6.19 baseline'
Assert-True (($v2619Expected -join "`n") -ceq ($v2619 -join "`n")) 'Historical v2.6.19 invariant failed'

# v2.6.20: only ten confirmed Meta/Threads suffixes may be added.
$metaAdditions20 = @{
    'DOMAIN-SUFFIX,meta.com,Meta' = @('DOMAIN-SUFFIX,metaaivm.com,Meta')
    'DOMAIN-SUFFIX,threads.net,Instagram' = @('DOMAIN-SUFFIX,threads.com,Instagram')
    'DOMAIN-SUFFIX,facebook.com,Meta' = @('DOMAIN-SUFFIX,facebook.net,Meta')
    'DOMAIN-SUFFIX,fbcdn.net,Meta' = @('DOMAIN-SUFFIX,fbcdn.com,Meta')
    'DOMAIN-SUFFIX,fb.com,Meta' = @('DOMAIN-SUFFIX,fb.me,Meta', 'DOMAIN-SUFFIX,m.me,Meta', 'DOMAIN-SUFFIX,fbsbx.com,Meta',
        'DOMAIN-SUFFIX,fbsbx.net,Meta', 'DOMAIN-SUFFIX,messenger.com,Meta')
    'DOMAIN-SUFFIX,whatsapp.net,Meta' = @('DOMAIN-SUFFIX,wa.me,Meta')
}
$v2620Expected = [Collections.Generic.List[string]]::new()
foreach ($line in $v2619Expected) {
    $v2620Expected.Add($line)
    if ($metaAdditions20.ContainsKey($line)) {
        foreach ($addition in $metaAdditions20[$line]) { $v2620Expected.Add($addition) }
    }
}
Assert-True ($v2620Expected.Count -eq $v2619Expected.Count + 10) 'Unexpected v2.6.20 delta size'

# v2.6.21: keep Tailscale's CGNAT range in TUN and route tailnet identities
# to the built-in Tailscale module; all other private-route behavior is intact.
$tailnetRules = @(
    'DOMAIN-SUFFIX,ts.net,TAILSCALE',
    'IP-CIDR,100.64.0.0/10,TAILSCALE,no-resolve'
)
$v2621Expected = [Collections.Generic.List[string]]::new()
foreach ($line in $v2620Expected) {
    $updated = $line
    if ($line.StartsWith('bypass-tun = ')) {
        Assert-True ($line.Contains(', 100.64.0.0/10,')) 'v2.6.20 TUN exclusion baseline changed'
        $updated = $line.Replace(', 100.64.0.0/10,', ',')
    }
    $v2621Expected.Add($updated)
    if ($line -ceq '[Rule]') {
        foreach ($rule in $tailnetRules) { $v2621Expected.Add($rule) }
    }
}
Assert-True (($v2621Expected -join "`n") -ceq ($active -join "`n")) 'Unexpected active configuration change outside authorized fixes'

$bypassTun = @($active | Where-Object { $_.StartsWith('bypass-tun = ') })
Assert-True ($bypassTun.Count -eq 1 -and !$bypassTun[0].Contains('100.64.0.0/10')) 'Tailscale IPv4 range must not bypass TUN'
# 2026-10-27: Apple's APNs-only ranges bypass the tunnel (support.apple.com/102266).
foreach ($apns in @('17.249.0.0/16', '17.252.0.0/16', '17.57.144.0/22', '17.188.128.0/18', '17.188.20.0/23')) {
    Assert-True ($bypassTun[0].Contains(", $apns")) "APNs range missing from bypass-tun: $apns"
}
Assert-True (!$bypassTun[0].Contains('17.0.0.0/8')) 'Do not bypass all of 17.0.0.0/8 (breaks 苹果服务 routing)'
# 2026-10-27: Privacy_Domain loaded, with carrier one-click-login exceptions ahead of it.
$privacySet = [array]::IndexOf($active, 'DOMAIN-SET,https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/Privacy/Privacy_Domain.list,REJECT')
Assert-True ($privacySet -ge 0) 'Privacy_Domain list missing'
foreach ($rule in @('DOMAIN-SUFFIX,cmpassport.com,DIRECT', 'DOMAIN-SUFFIX,id6.me,DIRECT', 'DOMAIN,opencloud.wostore.cn,DIRECT')) {
    $i = [array]::IndexOf($active, $rule)
    Assert-True ($i -ge 0 -and $i -lt $privacySet) "One-click login exception missing or after Privacy_Domain: $rule"
}
# 2026-10-29: 苹果服务 is wired to bm7 Apple lists; critical Apple DIRECT rules stay ahead of them.
$appleSet = [array]::IndexOf($active, 'DOMAIN-SET,https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/Apple/Apple_Domain.list,苹果服务')
Assert-True ($appleSet -ge 0) 'Apple_Domain list not routed to 苹果服务'
foreach ($rule in @('DOMAIN,ocsp.apple.com,DIRECT', 'DOMAIN-SUFFIX,ls.apple.com,DIRECT', 'DOMAIN-SUFFIX,mzstatic.com,DIRECT',
        'DOMAIN-SUFFIX,itunes.apple.com,DIRECT', 'DOMAIN-SUFFIX,apps.apple.com,DIRECT', 'DOMAIN-SUFFIX,icloud.com.cn,DIRECT')) {
    $i = [array]::IndexOf($active, $rule)
    Assert-True ($i -ge 0 -and $i -lt $appleSet) "Critical Apple DIRECT rule missing or after the Apple list: $rule"
}
foreach ($rule in $tailnetRules) {
    Assert-True (@($active | Where-Object { $_ -ceq $rule }).Count -eq 1) "Missing/duplicate Tailscale rule: $rule"
    Assert-True ([array]::IndexOf($active, $rule) -gt [array]::IndexOf($active, '[Rule]')) "Tailscale rule outside [Rule]: $rule"
}

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

# 2026-10-29 simplification: dedicated YT-* region pools removed (same nodes and filters as the
# generic pools). Generic region pools now probe Google over HTTPS, and YT-Auto fails over across them.
$ytGroups = @($active | Where-Object { $_ -match '^YT-.+ = ' })
Assert-True ($ytGroups.Count -eq 1 -and $ytGroups[0].StartsWith('YT-Auto = ')) 'Only YT-Auto may remain as a YouTube-specific group'
Assert-True ($ytGroups[0] -ceq 'YT-Auto = fallback, 美国节点, 香港节点, 台湾节点, 日本节点, 新加坡节点, url=https://www.gstatic.com/generate_204, interval=300, timeout=5') 'YT-Auto must fail over across the generic region pools'
foreach ($name in @('香港节点', '台湾节点', '日本节点', '新加坡节点', '美国节点')) {
    $group = @($active | Where-Object { $_.StartsWith("$name = ") })
    Assert-True ($group.Count -eq 1 -and $group[0].StartsWith("$name = url-test, url=https://www.gstatic.com/generate_204, interval=900, tolerance=200, timeout=5,")) "Region pool must probe Google over HTTPS at 900s: $name"
}
Assert-True (@($active | Where-Object { $_.StartsWith('YouTube = select, YT-Auto, 美国节点,') }).Count -eq 1) 'YouTube selector must default to YT-Auto'
foreach ($name in @('美国稳定', '日本稳定', '新加坡稳定')) {
    $group = @($active | Where-Object { $_.StartsWith("$name = ") })
    Assert-True ($group.Count -eq 1 -and $group[0].Contains('= fallback,') -and
        $group[0].Contains('url=https://cp.cloudflare.com/generate_204, interval=900, timeout=5')) "Invalid stable pool: $name"
}
$ytScripts = @($active | Where-Object { $_ -match '^YouTube\.(response|request\.(init|log_event)) = ' })
Assert-True ($ytScripts.Count -eq 3) 'YouTube hook count changed'
Assert-True ($ytScripts[0].Contains('"blockUpload":true')) 'Upload-button hiding disabled'
foreach ($hook in $ytScripts) {
    Assert-True ($hook.Contains('/65075cdb388fc5e3094afd7e7314c67b243f3525/')) 'YouTube script pin changed'
    Assert-True ($hook.Contains('engine=webview') -and $hook.Contains('binary-body-mode=1')) 'YouTube binary runtime changed'
}
# Parse all policy references and reject missing members/cycles, including manual alternatives.
$groupStart = [array]::IndexOf($active, '[Proxy Group]')
$groups = @{}
foreach ($line in $active[($groupStart + 1)..($ruleStart - 1)]) {
    $pair = $line -split ' = ', 2
    Assert-True ($pair.Count -eq 2 -and !$groups.ContainsKey($pair[0])) "Invalid/duplicate policy: $line"
    $parts = @($pair[1] -split ', ')
    $groups[$pair[0]] = @{
        Kind = $parts[0]
        Members = @($parts | Select-Object -Skip 1 | Where-Object { $_ -notmatch '=' })
    }
}
function Test-PolicyGraph([string]$Name, [string[]]$Chain = @()) {
    if (@('DIRECT','REJECT','REJECT-DROP') -ccontains $Name) { return }
    Assert-True ($groups.ContainsKey($Name)) "Unknown policy reference: $Name"
    Assert-True ($Chain -cnotcontains $Name) "Policy cycle: $($Chain -join ' -> ') -> $Name"
    foreach ($member in $groups[$Name].Members) { Test-PolicyGraph $member (@($Chain) + $Name) }
}
foreach ($name in $groups.Keys) { Test-PolicyGraph $name }
function Resolve-DefaultPool([string]$Name, [hashtable]$Selections = @{}) {
    if (!$groups.ContainsKey($Name)) { return $Name }
    $group = $groups[$Name]
    if ($group.Kind -ceq 'url-test' -or $group.Members.Count -eq 0) { return $Name }
    $choice = if ($Selections.ContainsKey($Name)) { $Selections[$Name] } else { $group.Members[0] }
    Assert-True ($group.Members -ccontains $choice) "Invalid selection for ${Name}: $choice"
    Resolve-DefaultPool $choice $Selections
}
$expectedDefaults = @{
    Proxy='美国节点'; AI='美国节点'; Gemini='美国节点'; Meta='美国节点';
    YouTube='美国节点'; Netflix='美国节点'; Spotify='新加坡节点'; TikTok='美国节点';
    Telegram='美国节点'; Instagram='美国稳定'; Twitter='美国稳定';
    苹果服务='DIRECT'; 谷歌服务='美国节点'; 微软服务='美国节点'; 哔哩哔哩='DIRECT'; Final='DIRECT'
}
foreach ($entry in $expectedDefaults.GetEnumerator()) {
    Assert-True ((Resolve-DefaultPool $entry.Key) -ceq $entry.Value) "Wrong initial region/pool: $($entry.Key)"
}
Assert-True (($groups.Gemini.Members -join ',') -ceq '谷歌服务') 'Gemini must follow the single Google selector'
foreach ($choice in $groups['谷歌服务'].Members) {
    $selection = @{ '谷歌服务' = $choice }
    Assert-True ((Resolve-DefaultPool 'Gemini' $selection) -ceq (Resolve-DefaultPool '谷歌服务' $selection)) "Google/Gemini drift when selecting $choice"
}
$routingFixtures = @{
    'gemini.google.com'='Gemini'; 'geller-pa.googleapis.com'='Gemini'; 'gemini.gstatic.com'='Gemini';
    'accounts.google.com'='谷歌服务'; 'oauth2.googleapis.com'='谷歌服务';
    'securetoken.googleapis.com'='谷歌服务'; 'identitytoolkit.googleapis.com'='谷歌服务';
    'lh3.googleusercontent.com'='谷歌服务'; 'www.gstatic.com'='谷歌服务';
    'muse.ai'='Meta'; 'auth.muse.ai'='Meta'; 'hatch-api.meta.ai'='Meta'; 'api.meta.ai'='Meta';
    'ar.graph.meta.com'='Meta'; 'auth.meta.com'='Meta'; 'graph.facebook.com'='Meta';
    'hatch.metaaivm.com'='Meta'; 'vm-123.metaaivm.com'='Meta';
    'static.facebook.net'='Meta'; 'scontent.example.fbcdn.net'='Meta';
    'static.fbcdn.com'='Meta'; 'cdn.fbsbx.com'='Meta'; 'api.fbsbx.net'='Meta';
    'm.me'='Meta'; 'fb.me'='Meta'; 'www.messenger.com'='Meta';
    'api.whatsapp.com'='Meta'; 'wa.me'='Meta';
    'i.instagram.com'='Instagram'; 'www.threads.com'='Instagram';
    'rr1.example.googlevideo.com'='YouTube'; 'device.example.ts.net'='TAILSCALE';
    'youtubei.googleapis.com'='YouTube'; 'init-stream.maasea.workers.dev'='YouTube';
    'sample.xz.fbcdn.net'='REJECT-DROP'; 'sample.xy.fbcdn.net'='REJECT-DROP';
    'qq.com'='DIRECT'; 'api.zhihu.com'='DIRECT'; 'p6.douyinpic.com'='DIRECT';
    'gateway.icloud.com.cn'='DIRECT'; 'apps.apple.com'='DIRECT'
}
foreach ($fixture in $routingFixtures.GetEnumerator()) {
    $match = First-LocalDomainRule $fixture.Key
    Assert-True ($match -and ($match -split ',')[-1] -ceq $fixture.Value) "Wrong local route for $($fixture.Key): $match"
}
# These local-only fixtures do NOT evaluate upstream ad/IP lists or iPhone policy state.
foreach ($domain in @('meta.ai.evil.example', 'notmeta.ai', 'muse.ai.evil.example', 'notmuse.ai',
    'notmetaaivm.com', 'metaaivm.com.evil.example', 'threads.com.evil.example')) {
    Assert-True ((First-LocalDomainRule $domain) -notmatch ',Meta$') "Meta suffix overmatch: $domain"
}
foreach ($rule in @($metaRules) + @($googleCoreRules) + @($googleAuthRules) +
    @($metaAdditions20.Values | ForEach-Object { $_ })) {
    Assert-True ([array]::IndexOf($active, $rule) -gt $firstAd) 'Core routing unexpectedly bypasses ad filtering'
}
$youtubeRemote = @($active | Where-Object { $_ -match '^RULE-SET,.*/YouTube/YouTube\.list,YouTube$' })
Assert-True ($youtubeRemote.Count -eq 1) 'Missing YouTube ruleset'
foreach ($rule in $googleAuthRules) {
    Assert-True ([array]::IndexOf($active, $rule) -lt [array]::IndexOf($active, $youtubeRemote[0])) 'Google auth can be captured by remote YouTube UA/IP rules'
}
Write-Output "PASS: $regexChecks US-regex cases; legacy routing and hooks; YT-Auto over Google-probed region pools; complete v2.6.16 through v2.6.21 scope invariants; Tailscale TUN/routing; policy graph; $($expectedDefaults.Count) defaults; $($routingFixtures.Count) local routing fixtures; shared Google/Gemini selection; Meta suffix safety."
