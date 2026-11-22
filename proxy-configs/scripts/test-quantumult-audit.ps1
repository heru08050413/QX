# Requires PowerShell 5.1+ (PowerShell 7 for -Online); checks declared contracts, not the native QX parser or actual proxy nodes.
param([string]$ConfigPath = (Join-Path $PSScriptRoot '../quantumult_B_V26.00'), [switch]$Online)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8
function Assert([bool]$Ok, [string]$Message) { if (!$Ok) { throw $Message } }
function Active([string]$Text) {
    @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(#|;|//)' })
}
function Sections([string]$Text) {
    $s = [ordered]@{}; $name = ''
    foreach ($line in (Active $Text)) {
        if ($line -match '^\[(.+)\]$') {
            $name = $Matches[1]; Assert (!$s.Contains($name)) "Duplicate section: $name"
            $s[$name] = [Collections.Generic.List[string]]::new()
        } else { Assert ($name -ne '') 'Data before section'; $s[$name].Add($line) }
    }
    $s
}
$us = '(?i)🇺🇸|(?:^|[^A-Za-z])(?:US|USA)(?=$|[^A-Za-z])|America|United States|美国|凤凰城|洛杉矶|西雅图|芝加哥|纽约|沪美|LosAngeles|SiliconValley'
$nodeFilter = '^(?!.*(剩余|套餐|官网|流量|过期|更新|失联|网址|备用|测试|GB|MB)).*$'
$wechat = @('dns.weixin.qq.com','dns.weixin.qq.com.cn','apd-pcdnwxlogin.teg.tencent-cloud.net')
$images = @('fastimage.uve.weibo.com','adimg.uve.weibo.com','adimg.vue.weibo.com')
$gemini = @('geller-pa.googleapis.com','robinfrontend-pa.googleapis.com','gemini.gstatic.com',
    'alkalicore-pa.clients6.google.com','webchannel-alkalimakersuite-pa.clients6.google.com')
$ytRules = @('host, youtubei.googleapis.com, YouTube','host, youtubei-att.googleapis.com, YouTube',
    'host-suffix, youtube.com, YouTube','host-suffix, googlevideo.com, YouTube','host-suffix, ytimg.com, YouTube')
$ytGroup = "url-latency-benchmark=YT-自动选择, server-tag-regex=$nodeFilter, check-interval=120, tolerance=300, alive-checking=false"

function Check([string]$Text) {
    $s=Sections $Text; $active=@(Active $Text)
    Assert (@($s['general'] | Where-Object { $_ -like 'resource_parser_url=*' }).Count -eq 0) 'Unused resource_parser_url must be disabled'
    $groups=@{}
    foreach ($line in $s['policy']) {
        $pair=$line -split '=',2; $parts=@($pair[1] -split ',\s*')
        Assert (!$groups.ContainsKey($parts[0])) "Duplicate group: $($parts[0])"
        $groups[$parts[0]]=@{Type=$pair[0]; Members=@($parts | Select-Object -Skip 1)}
    }
    Assert (-not $groups.ContainsKey('大陆抖音') -and -not $groups.ContainsKey('美国服务')) 'Orphan policy group returned'
    foreach ($name in $groups.Keys) {
        $group=$groups[$name]
        Assert ($group.Type -in @('static','available','url-latency-benchmark')) "Unsupported group type: $name"
        foreach ($member in $group.Members | Where-Object { $_ -notmatch '=' }) {
            Assert ($member -eq 'direct' -or $groups.ContainsKey($member)) "Unknown candidate: $member"
            Assert ($group.Type -eq 'static') "Non-static group nests a policy: $name"
        }
    }
    Assert ($groups['YouTube'].Members[0] -eq '美国节点') 'Wrong YouTube default'
    Assert ($ytGroup -in $s['policy']) 'Invalid YouTube benchmark contract'
    Assert ($groups['Gemini'].Members[0] -eq '美国节点') 'Wrong Gemini default'
    Assert ($groups['人工智能'].Members[0] -eq '狮城节点') 'Changed general AI default'
    Assert ($groups['谷歌服务'].Members[0] -eq '狮城节点') 'Changed Google default'
    Assert (-not ($groups['YouTube'].Members -contains '谷歌服务')) 'YouTube group must not offer 谷歌服务'
    foreach ($name in @('美国稳定','日本稳定','狮城稳定')) {
        Assert ($groups[$name].Type -eq 'available') "Unstable type: $name"
        Assert ($groups[$name].Members.Count -eq 1 -and $groups[$name].Members[0].StartsWith('server-tag-regex=')) "Unsupported available parameters: $name"
    }
    $yes=@('US','USA','us-01','US01','USA01','机场-US-01','美国01','🇺🇸 01','United States 01','America 01','洛杉矶01','SiliconValley')
    $no=@('Russia','RUS-01','Australia','AUS-01','RUS01','AUS01','Austria','🇦🇺 Sydney','JP 日本','HK 香港','Business 01','Plus 01')
    foreach ($name in @('美国节点','美国稳定')) {
        $pattern=($groups[$name].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
        foreach ($fixture in $yes) { Assert ([regex]::IsMatch($fixture,$pattern)) "$name excludes $fixture" }
        foreach ($fixture in $no) { Assert (![regex]::IsMatch($fixture,$pattern)) "$name admits $fixture" }
    }
    $hkRx = ($groups['香港节点'].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
    $twRx = ($groups['台湾节点'].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
    $jpRx = ($groups['日本节点'].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
    $krRx = ($groups['韩国节点'].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
    $sgRx = ($groups['狮城节点'].Members | Where-Object { $_.StartsWith('server-tag-regex=') }).Substring(17)
    Assert ([regex]::IsMatch('HK01', $hkRx) -and ![regex]::IsMatch('剩余流量 10GB HK', $hkRx)) 'HK filter failed boundary/junk check'
    Assert (![regex]::IsMatch('Network 01', $twRx) -and ![regex]::IsMatch('Twitter 解锁', $twRx) -and [regex]::IsMatch('TW01', $twRx)) 'TW filter boundary broken'
    Assert (![regex]::IsMatch('JPanime 01', $jpRx) -and [regex]::IsMatch('JP01', $jpRx)) 'JP filter boundary broken'
    Assert (![regex]::IsMatch('Ukraine 01', $krRx) -and [regex]::IsMatch('KR01', $krRx)) 'KR filter boundary broken'
    Assert ([regex]::IsMatch('SG01', $sgRx) -and ![regex]::IsMatch('套餐过期 500MB SG', $sgRx)) 'SG filter boundary/junk check failed'
    $rules=@($s['filter_local'])
    foreach ($name in $wechat) { Assert ("host, $name, direct" -in $rules) "Missing WeChat protection: $name" }
    foreach ($name in $images) {
        $index=[array]::IndexOf($rules,"host, $name, reject")
        Assert ($index -ge 0 -and $index -lt [array]::IndexOf($rules,'host-suffix, weibo.com, direct')) "Shadowed image reject: $name"
    }
    foreach ($badRule in @('host-suffix, siftscience.com, reject','host-keyword, umeng, reject','host-keyword, adsdk, reject','geoip, CN, direct, no-resolve')) {
        Assert ($badRule -notin $rules) "Stale/invalid local rule: $badRule"
    }
    Assert ('geoip, CN, direct' -in $rules) 'Missing 3-arg geoip, CN, direct rule'
    foreach ($needLocal in @('host-suffix, umeng.com, reject','host-suffix, adsdk.com, reject','host-suffix, claude.com, 人工智能','host-suffix, claudeusercontent.com, 人工智能','host, sydney.bing.com, 人工智能','host-suffix, wabi.ai, 人工智能','host-suffix, discord.com, 兜底策略','host-suffix, notion.com, 兜底策略')) {
        Assert ($needLocal -in $rules) "Missing required local rule: $needLocal"
    }
    foreach ($name in $gemini) { Assert ("host, $name, Gemini" -in $rules) "Missing Gemini route: $name" }
    foreach ($rule in $ytRules) { Assert ($rule -in $rules) "Missing YouTube route: $rule" }
    foreach ($rule in $rules) {
        $parts=$rule -split ',\s*'; $policy=if ($parts[0] -eq 'final') { $parts[1] } else { $parts[2] }
        Assert ($policy -in @('direct','reject') -or $groups.ContainsKey($policy)) "Unknown local policy: $policy"
    }
    foreach ($line in $s['filter_remote']) {
        $m=[regex]::Match($line,'force-policy=([^,]+)')
        if ($m.Success) { Assert ($m.Groups[1].Value -in @('direct','reject') -or $groups.ContainsKey($m.Groups[1].Value)) 'Unresolved remote policy' }
        if ($line.Contains('/Gemini/')) { Assert ($m.Groups[1].Value -eq 'Gemini') 'Remote Gemini still uses general AI' }
        if ($line.Contains('/Advertising/')) { Assert ($m.Groups[1].Value -eq 'reject') 'Advertising policy not forced' }
    }
    $frText = $s['filter_remote'] -join "`n"
    Assert ($frText.Contains('/Discord/Discord.list') -and $frText.Contains('/Notion/Notion.list')) 'Discord/Notion remote lists missing'
    $rrText = $s['rewrite_remote'] -join "`n"
    Assert ($rrText.Contains('boxjs.rewrite.quanx.conf') -and ($s['rewrite_remote'] | Where-Object { $_ -like '*boxjs*' -and $_ -match 'enabled=false' })) 'BoxJS must be disabled'
    Assert ($rrText.Contains('/863858b49220edddd6a4a445298ea846b50e8670/modules/script-hub.qx.conf') -and ($s['rewrite_remote'] | Where-Object { $_ -like '*script-hub*' -and $_ -match 'enabled=false' })) 'Script-Hub must be disabled and pinned'
    Assert ($rrText.Contains('/b90aab7775f9c20a6ac61985a7c18d846d172745/config/QX.snippet')) 'Sub-Store QX snippet must be pinned'
    Assert ($rrText.Contains('/df6366a7024e0b3f0aa3510c5b791eea6f3cba89/module/spotify.conf')) 'Spotify conf must be pinned'
    $tlText = $s['task_local'] -join "`n"
    Assert ($tlText.Contains('/58f6cce6dbd5c5fe50c2998938f9c2ba631a7c18/QuantumultX/scripts/server_info.js')) 'server_info.js must be pinned'
    $hostsLine = @($s['mitm'] | Where-Object { $_ -like 'hostname = *' })
    Assert ($hostsLine.Count -eq 1) 'Expected single MITM hostname line'
    $mitmExcludes = @($hostsLine[0].Substring(11) -split ',\s*' | Where-Object { $_.StartsWith('-') })
    Assert ($mitmExcludes.Count -ge 185) "Expected >= 185 MITM exclusions, got $($mitmExcludes.Count)"
    foreach ($spot in @('-*.95508.com','-weixin110.qq.com','-security.wechat.com','-sso.ifanr.com','-*.ts.net','-12306.cn')) {
        Assert ($mitmExcludes -contains $spot) "Missing canonical MITM exclusion: $spot"
    }
    foreach ($value in @('server_check_url=http://cp.cloudflare.com/generate_204','server_check_timeout=5000','fallback_udp_policy=reject','udp_whitelist=53, 80-427, 444-65535')) {
        Assert ($value -in $s['general']) "Invalid general field: $value"
    }
    Assert ('skip_validating_cert = false' -in $s['mitm']) 'TLS validation weakened'
    Assert ($s['rewrite_local'].Count -eq 0) 'Unverified rewrite enabled'
    Assert ('final, 兜底策略' -eq $rules[-1]) 'Final changed'
    Assert (@($s['task_local'] | Where-Object { $_ -notmatch '^event-interaction ' -and $_ -notmatch 'enabled=false$' }).Count -eq 0) 'Scheduled task unexpectedly enabled'
}
Check $source
$mutations=[ordered]@{
    probe=@('server_check_url=http:','server_check_url=https:')
    timeout=@('server_check_timeout=5000','server_check_timeout=9000')
    udp=@('fallback_udp_policy=reject','fallback_udp_policy=direct')
    us=@($us,'(?i)US|美')
    tw=@('(?:^|[^A-Za-z])(?:TW|TWN)(?=$|[^A-Za-z])','TW')
    kr=@('(?:^|[^A-Za-z])(?:KR|KOR)(?=$|[^A-Za-z])','KR')
    stable=@('available=美国稳定','url-latency-benchmark=美国稳定')
    ytDefault=@('static=YouTube, 美国节点, YT-自动选择,','static=YouTube, 谷歌服务, YT-自动选择,')
    ytProbe=@('check-interval=120, tolerance=300','check-interval=600, tolerance=300')
    wechat=@('host, dns.weixin.qq.com, direct','host, dns.weixin.qq.com, reject')
    weibo=@('host, adimg.uve.weibo.com, reject','host, adimg.uve.weibo.com, direct')
    gemini=@('host, geller-pa.googleapis.com, Gemini','host, geller-pa.googleapis.com, 人工智能')
    geminiRemote=@('tag=Gemini, force-policy=Gemini','tag=Gemini, force-policy=人工智能')
    tls=@('skip_validating_cert = false','skip_validating_cert = true')
    geoipArg=@('geoip, CN, direct','geoip, CN, direct, no-resolve')
    sift=@('host-suffix, umeng.com, reject','host-suffix, siftscience.com, reject')
    boxjs=@('tag=BoxJs, update-interval=259200, opt-parser=false, enabled=false','tag=BoxJs, update-interval=259200, opt-parser=false, enabled=true')
    subStorePin=@('/b90aab7775f9c20a6ac61985a7c18d846d172745/config/QX.snippet','/master/config/QX.snippet')
    mitmNew=@(', -*.95508.com','')
}
foreach ($name in $mutations.Keys) {
    $bad=$source.Replace($mutations[$name][0],$mutations[$name][1]); Assert ($bad -cne $source) "Mutation did not apply: $name"
    $caught=$false; try { Check $bad } catch { $caught=$true }; Assert $caught "Mutation not caught by semantic tests: $name"
}
Write-Output "PASS: general/policy/filter/rule/remote/MITM/security checks, C7 & 48 US-name fixtures, $($mutations.Count) negative mutations."
if ($Online) {
    $s=Sections $source
    $urls=@(@('filter_remote','rewrite_remote','task_local') | ForEach-Object {
        foreach ($line in $s[$_]) {
            if ($line -match 'enabled=false') { continue }
            [regex]::Match($line,'https://[^,\s]+').Value
        }
    } | Where-Object { $_ } | Sort-Object -Unique)
    $downloads=@($urls | ForEach-Object -Parallel {
        $targetUrl=$_
        try {
            $r=Invoke-WebRequest -Uri $targetUrl -TimeoutSec 35 -MaximumRedirection 10 -UserAgent 'Quantumult X/1.7.0'
            $body=if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
            [pscustomobject]@{Url=$targetUrl; Status=[int]$r.StatusCode; Body=$body; Error=''}
        } catch { [pscustomobject]@{Url=$targetUrl; Status=0; Body=''; Error=$_.Exception.Message} }
    } -ThrottleLimit 6)
    $failed=@($downloads | Where-Object { $_.Status -ne 200 -or !$_.Body.Trim() -or $_.Body -match '(?is)^\s*(<!doctype html|<html)' })
    if ($failed.Count) { $failed | Select-Object Url,Status,Error | Format-Table -Wrap | Out-Host; throw 'Remote resource checks failed' }
    $js=@{}
    foreach ($resource in $downloads) {
        if ($resource.Url -match '\.js$') { $js[$resource.Url]=$resource.Body }
    }
    $rewrites=@($s['rewrite_remote'] | ForEach-Object { ($_ -split ',')[0] })
    $dependencies=@($downloads | Where-Object { $_.Url -in $rewrites } | ForEach-Object {
        foreach ($m in [regex]::Matches($_.Body,'(?m)^\S+\s+url\s+script-[\w-]+\s+(https://\S+)')) { $m.Groups[1].Value }
    } | Sort-Object -Unique)
    foreach ($url in $dependencies) {
        $r=Invoke-WebRequest -Uri $url -TimeoutSec 35 -UserAgent 'Quantumult X/1.7.0'
        Assert ($r.StatusCode -eq 200) "Dependency unavailable: $url"
        $js[$url]=if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
    }
    foreach ($url in $js.Keys) {
        Assert ($js[$url].Length -gt 20) "Empty JS: $url"
        $js[$url] | & node --check --input-type=commonjs -
        Assert ($LASTEXITCODE -eq 0) "JS syntax failed: $url"
    }
    $probeUrl = ($s['general'] | Where-Object { $_.StartsWith('server_check_url=') }).Substring('server_check_url='.Length)
    $probe=Invoke-WebRequest -Uri $probeUrl -Method Head -MaximumRedirection 0 -TimeoutSec 20
    Assert ($probe.StatusCode -eq 204) 'Configured HTTP HEAD probe not directly 204'
    Write-Output "PASS: $($urls.Count) enabled direct resources 200/nonempty/non-HTML; $($dependencies.Count) rewrite JS dependencies 200; $($js.Count) JS syntax checks; configured HTTP HEAD probe directly 204. No downloaded JS executed."
}
