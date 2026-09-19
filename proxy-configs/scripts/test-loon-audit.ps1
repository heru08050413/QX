# Requires PowerShell 7 and git; -Online also requires node and network.
# Static contract tests, not the Loon native parser or an iPhone runtime test.
param([string]$ConfigPath = (Join-Path $PSScriptRoot '../Loon_V26.00'), [switch]$Online)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$baseline = 'f2ac77e1e5c6084a67ebf50b7a201cc1f1d86b2e'
$baseText = (& git -C $repo show "${baseline}:proxy-configs/Loon_V26.00") -join "`n"
if ($LASTEXITCODE) { throw 'Cannot read immutable baseline' }
$text = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8

function Assert([bool]$Ok, [string]$Message) { if (!$Ok) { throw $Message } }
function Active([string]$Text) {
    @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[#;]' })
}
function Sections([string]$Text) {
    $result = [ordered]@{}
    $section = ''
    foreach ($line in (Active $Text)) {
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1]
            Assert (!$result.Contains($section)) "Duplicate section: $section"
            $result[$section] = [Collections.Generic.List[string]]::new()
        } else {
            Assert ($section -ne '') 'Data before section'
            $result[$section].Add($line)
        }
    }
    $result
}

$usPattern = '(?i)🇺🇸|(?:^|[^A-Za-z])(?:US|USA)(?=$|[^A-Za-z])|America|United States|美国|凤凰城|洛杉矶|西雅图|芝加哥|纽约|沪美|LosAngeles|SiliconValley'
$wechat = @('dns.weixin.qq.com', 'dns.weixin.qq.com.cn', 'apd-pcdnwxlogin.teg.tencent-cloud.net')
$images = @('fastimage.uve.weibo.com', 'adimg.uve.weibo.com', 'adimg.vue.weibo.com')
$gemini = @('geller-pa.googleapis.com', 'robinfrontend-pa.googleapis.com', 'gemini.gstatic.com',
    'alkalicore-pa.clients6.google.com', 'webchannel-alkalimakersuite-pa.clients6.google.com')
$ytRules = @('DOMAIN,youtubei.googleapis.com,油管视频', 'DOMAIN,youtubei-att.googleapis.com,油管视频',
    'DOMAIN,init-stream.maasea.workers.dev,油管视频', 'DOMAIN-SUFFIX,googlevideo.com,油管视频')
$ytGroups = [ordered]@{'YT-香港'='HK_Filter'; 'YT-狮城'='SG_Filter'; 'YT-日本'='JP_Filter'; 'YT-美国'='US_Filter'}
$stableGroups = [ordered]@{'香港稳定'='HK_Filter'; '日本稳定'='JP_Filter'; '美国稳定'='US_Filter'; '狮城稳定'='SG_Filter'}
$httpdns = 'https://raw.githubusercontent.com/VirgilClyne/GetSomeFries/main/plugin/HTTPDNS.Block.plugin'
$maasea = 'https://raw.githubusercontent.com/Maasea/sgmodule/master/YouTube.Enhance.sgmodule'
$removed = @('DOMAIN-SUFFIX,biz.weibo.com,REJECT', 'DOMAIN,bootpreload.uve.weibo.com,REJECT',
    'DOMAIN-SUFFIX,fastimage.uve.weibo.com,REJECT', 'DOMAIN-SUFFIX,adimg.vue.weibo.com,REJECT',
    'DOMAIN-SUFFIX,sdkapp.uve.weibo.com,REJECT', 'URL-REGEX,"\.log\.",REJECT')
$oldMitm = @('*.weibo.cn','*.weibo.com','*.weibo.com.cn','*.weibocdn.com','*.sina.cn','*.sina.com.cn','*.sinajs.cn')
$apiMitm = @('api.weibo.cn','mapi.weibo.cn','api.weibo.com','mapi.weibo.com','sdkapp.uve.weibo.com','wbapp.uve.weibo.com')
$safeMitm = @('-12306.cn','-*.12306.cn','-alipay.com','-alipay.com.cn','-*.alipay.com.cn')

# Rebuild every approved active-line change from a fixed pre-repair commit.
# This guards all unrelated DNS, subscriptions, defaults, scripts, CA and TLS fields.
$expected = [Collections.Generic.List[string]]::new()
foreach ($line in (Active $baseText)) {
    if ($line -in $removed) { continue }
    if ($line -eq 'DOMAIN-SUFFIX,weibo.cn,DIRECT') {
        foreach ($hostName in $wechat) { $expected.Add("DOMAIN,$hostName,DIRECT") }
        foreach ($hostName in $images) { $expected.Add("DOMAIN,$hostName,REJECT") }
    }
    if ($line -like 'YT-Auto = *') {
        $expected.Add('YT-Auto = fallback,YT-香港,YT-狮城,YT-日本,YT-美国,url = https://www.gstatic.com/generate_204,interval = 60,max-timeout = 5000')
        foreach ($name in $ytGroups.Keys) { $expected.Add("$name = url-test,$($ytGroups[$name]),url = https://www.gstatic.com/generate_204,interval = 120,tolerance = 300") }
        continue
    }
    if ($line -like 'StableFallback = *') {
        $expected.Add('StableFallback = fallback,狮城稳定,日本稳定,美国稳定,香港稳定,url = https://cp.cloudflare.com/generate_204,interval = 300,max-timeout = 5000')
        continue
    }
    $groupName = ($line -split ' = ',2)[0]
    if ($stableGroups.Contains($groupName)) {
        $expected.Add("$groupName = fallback,$($stableGroups[$groupName]),url = https://cp.cloudflare.com/generate_204,interval = 300,max-timeout = 5000")
        continue
    }
    if ($line -like 'US_Filter = *') { $expected.Add("US_Filter = NameRegex, FilterKey = `"$usPattern`""); continue }
    if ($line -eq "$httpdns, enabled=true") { $expected.Add("$httpdns, enabled=false"); continue }
    if ($line.StartsWith('hostname = ')) {
        $hosts = @($line.Substring(11) -split ',\s*')
        $newHosts = [Collections.Generic.List[string]]::new()
        foreach ($hostName in $hosts) {
            if ($hostName -eq $oldMitm[0]) {
                $newHosts.AddRange([string[]]$safeMitm)
                $newHosts.AddRange([string[]]$apiMitm)
            }
            if ($hostName -notin $oldMitm) { $newHosts.Add($hostName) }
        }
        $expected.Add('hostname = ' + ($newHosts -join ', ')); continue
    }
    $expected.Add($line)
    if ($line -eq 'DOMAIN-KEYWORD,haijiao,美国节点') {
        $expected.AddRange([string[]]$ytRules)
        foreach ($hostName in $gemini) { $expected.Add("DOMAIN,$hostName,Gemini") }
    }
}

function Check-Config([string]$Source, [bool]$CheckDelta = $true) {
    $s = Sections $Source
    $active = @(Active $Source)
    if ($CheckDelta) { Assert (($active -join "`n") -ceq ($expected -join "`n")) 'Unexpected active-line delta against immutable baseline' }
    $groups = @{}
    foreach ($line in $s['Proxy Group']) {
        $pair = $line -split '\s*=\s*',2
        Assert (!$groups.ContainsKey($pair[0])) "Duplicate group: $($pair[0])"
        $groups[$pair[0]] = @($pair[1] -split ',' | ForEach-Object { $_.Trim() })
    }
    $filters = @($s['Remote Filter'] | ForEach-Object { ($_ -split '\s*=\s*',2)[0] })
    foreach ($name in $groups.Keys) {
        Assert ($groups[$name][0] -in @('select','url-test','fallback')) "Unexpected type: $name"
        foreach ($member in $groups[$name] | Select-Object -Skip 1 | Where-Object { $_ -notmatch '=' }) {
            Assert ($member -eq 'DIRECT' -or $groups.ContainsKey($member) -or $member -in $filters) "Unresolved $name member: $member"
        }
    }
    Assert ($groups['油管视频'][1] -eq 'YT-Auto') 'Wrong YouTube default'
    Assert ($groups['谷歌服务'][1] -eq '自动选择') 'Google default coupled to YouTube'
    Assert ($groups['Gemini'][1] -eq '美国节点') 'Wrong Gemini default'
    Assert (($groups['YT-Auto'][0..4] -join ',') -eq 'fallback,YT-香港,YT-狮城,YT-日本,YT-美国') 'YouTube must use dedicated regional pools'
    foreach ($item in @('url = https://www.gstatic.com/generate_204','interval = 60','max-timeout = 5000')) {
        Assert ($item -in $groups['YT-Auto']) "Missing YT-Auto field: $item"
    }
    foreach ($name in $ytGroups.Keys) {
        Assert (($groups[$name] -join ',') -eq "url-test,$($ytGroups[$name]),url = https://www.gstatic.com/generate_204,interval = 120,tolerance = 300") "Invalid YouTube regional pool: $name"
    }
    foreach ($name in $stableGroups.Keys) {
        Assert (($groups[$name] -join ',') -eq "fallback,$($stableGroups[$name]),url = https://cp.cloudflare.com/generate_204,interval = 300,max-timeout = 5000") "Invalid stable group: $name"
    }
    $filterLine = @($s['Remote Filter'] | Where-Object { $_ -like 'US_Filter = *' })
    Assert ($filterLine.Count -eq 1) 'Missing/duplicate US filter'
    $pattern = [regex]::Match($filterLine[0], 'FilterKey\s*=\s*"(.*)"$').Groups[1].Value
    $positive = @('US','USA','us-01','US01','USA01','机场-US-01','美国01','🇺🇸 01','United States 01','America 01','洛杉矶01','SiliconValley')
    $negative = @('Russia','RUS-01','Australia','AUS-01','RUS01','AUS01','Austria','🇦🇺 Sydney','JP 日本','HK 香港','Business 01','Plus 01')
    foreach ($fixture in $positive) { Assert ([regex]::IsMatch($fixture,$pattern)) "US filter excludes $fixture" }
    foreach ($fixture in $negative) { Assert (![regex]::IsMatch($fixture,$pattern)) "US filter admits $fixture" }
    $rules = @($s['Rule'])
    Assert ($rules[-1] -eq 'FINAL,兜底策略') 'Changed FINAL'
    foreach ($rule in $rules) {
        $parts = $rule -split ','
        $policy = if ($parts[-1] -eq 'no-resolve') { $parts[-2] } else { $parts[-1] }
        Assert ($policy -in @('DIRECT','REJECT','REJECT-DROP') -or $groups.ContainsKey($policy)) "Unresolved rule policy: $policy"
    }
    foreach ($hostName in $wechat) { Assert ("DOMAIN,$hostName,DIRECT" -in $rules) "Missing WeChat protection: $hostName" }
    foreach ($hostName in $images) {
        $index = [array]::IndexOf($rules,"DOMAIN,$hostName,REJECT")
        Assert ($index -ge 0 -and $index -lt [array]::IndexOf($rules,'DOMAIN-SUFFIX,weibo.com,DIRECT')) "Shadowed Weibo image block: $hostName"
    }
    foreach ($rule in $removed) { Assert ($rule -notin $rules) "Stale harmful/shadowed rule: $rule" }
    foreach ($rule in $ytRules) { Assert ($rule -in $rules) "Missing YouTube route: $rule" }
    foreach ($hostName in $gemini) { Assert ("DOMAIN,$hostName,Gemini" -in $rules) "Missing Gemini route: $hostName" }
    Assert ("$httpdns, enabled=false" -in $s['Plugin']) 'HTTPDNS plugin still enabled'
    Assert ("$httpdns, enabled=true" -notin $s['Plugin']) 'Duplicate enabled HTTPDNS plugin'
    $ytPlugins = @($s['Plugin'] | Where-Object { $_ -match '(?i)youtube' })
    Assert ($ytPlugins.Count -eq 1 -and $ytPlugins[0] -eq "$maasea, policy=油管视频, enabled=true") 'YouTube plugin missing, duplicated or changed'
    $hosts = (($s['Mitm'] | Where-Object { $_ -like 'hostname = *' }) -replace '^hostname = ','') -split ',\s*'
    foreach ($hostName in $safeMitm + $apiMitm + @('youtubei.googleapis.com')) { Assert ($hostName -in $hosts) "Missing MITM entry: $hostName" }
    foreach ($hostName in $oldMitm) { Assert ($hostName -notin $hosts) "Broad main MITM entry: $hostName" }
    Assert ('skip-server-cert-verify = false' -in $s['Mitm']) 'MITM TLS verification weakened'
    foreach ($line in $s['Remote Proxy']) { Assert ($line.Contains('skip-cert-verify=false') -and $line.Contains('block-quic=true') -and $line.Contains('__REDACTED__')) 'Subscription security changed' }
    Assert ('disconnect-on-policy-change = false' -in $s['General']) 'Global disconnect enabled'
    Assert ('udp-fallback-mode = REJECT' -in $s['General']) 'UDP direct leakage enabled'
}

Check-Config $text
$mutations = [ordered]@{
    httpdns = @("$httpdns, enabled=false", "$httpdns, enabled=true")
    probe = @('YT-香港 = url-test,HK_Filter,url = https://www.gstatic.com', 'YT-香港 = url-test,HK_Filter,url = http://www.gstatic.com')
    interval = @('interval = 60,max-timeout', 'interval = 600,max-timeout')
    genericPool = @('fallback,YT-香港,YT-狮城,YT-日本,YT-美国,', 'fallback,香港节点,狮城节点,日本节点,美国节点,')
    usFilter = @($usPattern, '(?i)(US|美)')
    worker = @('DOMAIN,init-stream.maasea.workers.dev,油管视频', 'DOMAIN,init-stream.maasea.workers.dev,DIRECT')
    gemini = @('DOMAIN,geller-pa.googleapis.com,Gemini', 'DOMAIN,geller-pa.googleapis.com,谷歌服务')
    weibo = @('DOMAIN,adimg.uve.weibo.com,REJECT', 'DOMAIN,adimg.uve.weibo.com,DIRECT')
    mitm = @('-*.12306.cn', '*.12306.cn')
    stable = @('香港稳定 = fallback,', '香港稳定 = url-test,')
    tls = @('skip-server-cert-verify = false','skip-server-cert-verify = true')
    wechat = @('DOMAIN,dns.weixin.qq.com,DIRECT','DOMAIN,dns.weixin.qq.com,REJECT')
}
foreach ($name in $mutations.Keys) {
    $bad = $text.Replace($mutations[$name][0], $mutations[$name][1])
    Assert ($bad -cne $text) "Mutation did not apply: $name"
    $caught = $false
    try { Check-Config $bad $false } catch { $caught = $true }
    Assert $caught "Mutation not detected by semantic checks: $name"
}
Write-Output 'PASS: immutable active-line delta, section/group/rule/MITM/security checks, 24 US fixtures, 12 negative mutations.'

if ($Online) {
    $s = Sections $text
    $urls = @('Remote Rule','Remote Script','Plugin') | ForEach-Object {
        $s[$_] | Where-Object { $_ -notmatch 'enabled=false' } | ForEach-Object { ($_ -split ',')[0].Trim() }
    }
    $urls = @($urls | Sort-Object -Unique)
    $downloads = @($urls | ForEach-Object -Parallel {
        $url = $_
        try {
            $r = Invoke-WebRequest -Uri $url -TimeoutSec 60 -MaximumRedirection 10 -UserAgent 'Loon/3.5.0' -ErrorAction Stop
            $body = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
            [pscustomobject]@{Url=$url; Status=[int]$r.StatusCode; Body=$body; Error=$null}
        } catch { [pscustomobject]@{Url=$url; Status=0; Body=''; Error=$_.Exception.Message} }
    } -ThrottleLimit 6)
    $failures = @($downloads | Where-Object { $_.Status -ne 200 -or !$_.Body.Trim() -or $_.Body -match '(?is)^\s*(<!doctype html|<html)' })
    if ($failures.Count) { $failures | Select-Object Url,Status,Error | Format-Table -Wrap | Out-Host; throw 'Enabled remote resource check failed' }
    $module = ($downloads | Where-Object Url -eq $maasea).Body
    foreach ($hook in @('youtube.response','youtube.request.init','youtube.request.log_event')) {
        Assert ([regex]::Matches($module, '(?m)^' + [regex]::Escape($hook) + '\s*=').Count -eq 1) "Missing/duplicate upstream hook: $hook"
    }
    Assert ($module.Contains('屏蔽上传按钮:true')) 'Upstream upload-hide default changed'
    Assert ($module.Contains('*.googlevideo.com') -and $module.Contains('youtubei.googleapis.com')) 'Upstream MITM changed'
    Assert ([regex]::Matches($module,'binary-body-mode=1').Count -eq 3) 'Upstream binary mode changed'
    $scripts = @([regex]::Matches($module,'script-path=(https://[^,\s]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Assert ($scripts.Count -eq 2) 'Expected two unique Maasea scripts'
    foreach ($url in $scripts) {
        $r = Invoke-WebRequest -Uri $url -TimeoutSec 60 -UserAgent 'Loon/3.5.0'
        $body = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        Assert ($r.StatusCode -eq 200 -and $body.Length -gt 100) "Invalid JS response: $url"
        $body | & node --check --input-type=commonjs -
        Assert ($LASTEXITCODE -eq 0) "JavaScript syntax failed: $url"
    }
    foreach ($url in @('https://www.gstatic.com/generate_204','https://cp.cloudflare.com/generate_204')) {
        $r = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 30 -UserAgent 'Loon/3.5.0'
        Assert ($r.StatusCode -eq 204) "Probe not 204: $url"
    }
    Write-Output "PASS: $($urls.Count) enabled direct resources HTTP 200/nonempty/non-HTML; 3 Maasea hooks; 2 JS syntax checks; 2 HTTPS HEAD probes 204. No downloaded JS executed."
}
