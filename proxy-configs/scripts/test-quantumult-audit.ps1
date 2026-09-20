# Requires PowerShell 7 + git; -Online additionally needs node and network.
# Checks declared contracts, not the native QX parser or actual proxy nodes.
param([string]$ConfigPath = (Join-Path $PSScriptRoot '../quantumult_B_V26.00'), [switch]$Online)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$baseline = '4cbd5a0dd4dcf2bb528263495bf72757c4e82e64'
$base = (& git -C $repo show "${baseline}:proxy-configs/quantumult_B_V26.00") -join "`n"
if ($LASTEXITCODE) { throw 'Immutable baseline unavailable' }
$importBaseline = 'e8fa202efd94195ed0e095fc2ebf1564b33a2099'
$beforeImportFix = (& git -C $repo show "${importBaseline}:proxy-configs/quantumult_B_V26.00") -join "`n"
if ($LASTEXITCODE) { throw 'Import-fix baseline unavailable' }
$expectedImportFix = $beforeImportFix.Replace('server_check_url=https://cp.cloudflare.com/generate_204','server_check_url=http://cp.cloudflare.com/generate_204')
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
$expected = [Collections.Generic.List[string]]::new()
foreach ($original in (Active $base)) {
    $line = $original
    if ($line -eq 'server_check_timeout=3000') { $line='server_check_timeout=5000' }
    if ($line -eq 'fallback_udp_policy=direct') { $line='fallback_udp_policy=reject' }
    if ($line -match '^(url-latency-benchmark)=(美国节点|美国稳定),') { $line=$line.Replace('美|US|States|American|🇺🇸',$us) }
    if ($line -match '^url-latency-benchmark=(美国稳定|日本稳定|狮城稳定),') {
        $line=$line.Replace('url-latency-benchmark=','available=').Replace(', check-interval=900, tolerance=300, alive-checking=true','')
    }
    if ($line.StartsWith('static=YouTube,')) { $line=$line.Replace('static=YouTube, 谷歌服务,','static=YouTube, YT-自动选择, 谷歌服务,') }
    if ($line.Contains('/Advertising/Advertising.list,')) { $line=$line.Replace(', update-interval=',', force-policy=reject, update-interval=') }
    if ($line.Contains('/Gemini/Gemini.list,')) { $line=$line.Replace('force-policy=人工智能','force-policy=Gemini') }
    if ($line -eq 'host-suffix, weibo.cn, direct') {
        foreach ($name in $images) { $expected.Add("host, $name, reject") }
    }
    $expected.Add($line)
    if ($line.StartsWith('static=人工智能,')) { $expected.Add('static=Gemini, 美国节点, 日本节点, 台湾节点, 狮城节点') }
    if ($line.StartsWith('static=YouTube,')) { $expected.Add($ytGroup) }
    if ($line -eq 'host-suffix, local, direct') { foreach ($name in $wechat) { $expected.Add("host, $name, direct") } }
    if ($line -eq 'host-suffix, quoracdn.net, 社交阅读') {
        foreach ($name in $gemini) { $expected.Add("host, $name, Gemini") }
        $expected.AddRange([string[]]$ytRules)
    }
}
function Check([string]$Text, [bool]$Delta=$true) {
    $s=Sections $Text; $active=@(Active $Text)
    if ($Delta) {
        Assert (($active -join "`n") -ceq ($expected -join "`n")) 'Unexpected active-line change against immutable baseline'
        Assert (($active -join "`n") -ceq ((Active $expectedImportFix) -join "`n")) 'Import fix must change only the global probe URL'
    }
    $groups=@{}
    foreach ($line in $s['policy']) {
        $pair=$line -split '=',2; $parts=@($pair[1] -split ',\s*')
        Assert (!$groups.ContainsKey($parts[0])) "Duplicate group: $($parts[0])"
        $groups[$parts[0]]=@{Type=$pair[0]; Members=@($parts | Select-Object -Skip 1)}
    }
    foreach ($name in $groups.Keys) {
        $group=$groups[$name]
        Assert ($group.Type -in @('static','available','url-latency-benchmark')) "Unsupported group type: $name"
        foreach ($member in $group.Members | Where-Object { $_ -notmatch '=' }) {
            Assert ($member -eq 'direct' -or $groups.ContainsKey($member)) "Unknown candidate: $member"
            Assert ($group.Type -eq 'static') "Non-static group nests a policy: $name"
        }
    }
    Assert ($groups['YouTube'].Members[0] -eq 'YT-自动选择') 'Wrong YouTube default'
    Assert ($ytGroup -in $s['policy']) 'Invalid YouTube benchmark contract'
    Assert ($groups['Gemini'].Members[0] -eq '美国节点') 'Wrong Gemini default'
    Assert ($groups['人工智能'].Members[0] -eq '狮城节点') 'Changed general AI default'
    Assert ($groups['谷歌服务'].Members[0] -eq '狮城节点') 'Changed Google default'
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
    $rules=@($s['filter_local'])
    foreach ($name in $wechat) { Assert ("host, $name, direct" -in $rules) "Missing WeChat protection: $name" }
    foreach ($name in $images) {
        $index=[array]::IndexOf($rules,"host, $name, reject")
        Assert ($index -ge 0 -and $index -lt [array]::IndexOf($rules,'host-suffix, weibo.com, direct')) "Shadowed image reject: $name"
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
    # Regression: user reported native import error at line 87 with this HTTPS probe.
    # This is a compatibility guard for this profile, not a claim about all QX versions.
    probe=@('server_check_url=http:','server_check_url=https:')
    timeout=@('server_check_timeout=5000','server_check_timeout=9000')
    udp=@('fallback_udp_policy=reject','fallback_udp_policy=direct')
    us=@($us,'(?i)US|美')
    stable=@('available=美国稳定','url-latency-benchmark=美国稳定')
    ytDefault=@('static=YouTube, YT-自动选择,','static=YouTube, 谷歌服务,')
    ytProbe=@('check-interval=120, tolerance=300','check-interval=600, tolerance=300')
    wechat=@('host, dns.weixin.qq.com, direct','host, dns.weixin.qq.com, reject')
    weibo=@('host, adimg.uve.weibo.com, reject','host, adimg.uve.weibo.com, direct')
    gemini=@('host, geller-pa.googleapis.com, Gemini','host, geller-pa.googleapis.com, 人工智能')
    geminiRemote=@('tag=Gemini, force-policy=Gemini','tag=Gemini, force-policy=人工智能')
    tls=@('skip_validating_cert = false','skip_validating_cert = true')
}
foreach ($name in $mutations.Keys) {
    $bad=$source.Replace($mutations[$name][0],$mutations[$name][1]); Assert ($bad -cne $source) "Mutation did not apply: $name"
    $caught=$false; try { Check $bad $false } catch { $caught=$true }; Assert $caught "Mutation not caught by semantic tests: $name"
}
Write-Output 'PASS: immutable active-line delta, groups/rules/security contracts, 48 US-name fixtures, 12 independent negative mutations.'
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
