# Requires PowerShell 5.1+ (PowerShell 7 for -Online); static contract tests, not the Loon native parser or an iPhone runtime test.
param([string]$ConfigPath = (Join-Path $PSScriptRoot '../Loon_V26.00'), [switch]$Online)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
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
$httpdns = 'https://raw.githubusercontent.com/VirgilClyne/GetSomeFries/main/plugin/HTTPDNS.Block.plugin'
$maasea = 'https://raw.githubusercontent.com/Maasea/sgmodule/65075cdb388fc5e3094afd7e7314c67b243f3525/YouTube.Enhance.sgmodule'
$removed = @('DOMAIN-SUFFIX,biz.weibo.com,REJECT', 'DOMAIN,bootpreload.uve.weibo.com,REJECT',
    'DOMAIN-SUFFIX,fastimage.uve.weibo.com,REJECT', 'DOMAIN-SUFFIX,adimg.vue.weibo.com,REJECT',
    'DOMAIN-SUFFIX,sdkapp.uve.weibo.com,REJECT', 'URL-REGEX,"\.log\.",REJECT',
    'DOMAIN-SUFFIX,siftscience.com,REJECT-DROP', 'DOMAIN-KEYWORD,umeng,REJECT-DROP',
    'DOMAIN-KEYWORD,adsdk,REJECT-DROP', 'DOMAIN-SUFFIX,branch.io,REJECT',
    'DOMAIN-SUFFIX,segment.com,REJECT', 'DOMAIN-SUFFIX,segment.io,REJECT',
    'DOMAIN-SUFFIX,googletagmanager.com,REJECT', 'DOMAIN-KEYWORD,haijiao,美国节点')
$oldMitm = @('*.weibo.cn','*.weibo.com','*.weibo.com.cn','*.weibocdn.com','*.sina.cn','*.sina.com.cn','*.sinajs.cn','restapi.amap.com')
$apiMitm = @('api.weibo.cn','mapi.weibo.cn','api.weibo.com','mapi.weibo.com','sdkapp.uve.weibo.com','wbapp.uve.weibo.com')
$safeMitm = @('-12306.cn','-*.12306.cn','-alipay.com','-alipay.com.cn','-*.alipay.com.cn','-*.ts.net','-*.95508.com','-weixin110.qq.com','-security.wechat.com','-sso.ifanr.com')

function Check-Config([string]$Source) {
    $s = Sections $Source
    $active = @(Active $Source)
    Assert ('proxy-test-url = https://www.gstatic.com/generate_204' -in $s['General']) 'proxy-test-url must probe Google HTTPS 204'
    Assert ('test-timeout = 5' -in $s['General']) 'test-timeout must be 5'
    Assert ('hijack-dns = *:53' -in $s['General']) 'hijack-dns must be *:53'
    Assert ('resource-parser = https://github.com/sub-store-org/Sub-Store/releases/download/2.44.23/sub-store-parser.loon.min.js' -in $s['General']) 'Sub-Store parser must be pinned to 2.44.23'
    Assert (@($s['Host'] | Where-Object { $_ -like 'iosapps.itunes.apple.com*' }).Count -eq 0) 'Stale iosapps ks-cdn Host mapping returned'
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
    # 2026-11-07 simplification: 21 groups, only 8 probe groups (no lazy in Loon).
    $removed = @('YT-Auto','稳定选择','StableFallback','香港稳定','日本稳定','美国稳定','狮城稳定','大陆网址','微信消息','微博服务','小红书','大陆抖音','Instagram','Twitter','脸书服务','Line通讯','迪士尼','Netflix','Spotify','Github','国内服务','哔哩哔哩')
    foreach ($name in $removed) { Assert (!$groups.ContainsKey($name)) "Removed group reintroduced: $name" }
    $probing = @($groups.Keys | Where-Object { $groups[$_][0] -in @('url-test','fallback') })
    Assert ($probing.Count -eq 8) "Expected 8 probe groups, got $($probing.Count)"
    foreach ($name in $probing) {
        Assert (('interval = 600' -in $groups[$name]) -and ('tolerance = 100' -in $groups[$name])) "Probe group must use 600s/100ms: $name"
    }
    Assert ('doh-server = https://223.5.5.5/dns-query, https://1.12.12.12/dns-query, https://223.6.6.6/dns-query, https://120.53.53.53/dns-query' -in $s['General']) 'doh-server must use pure IP encrypted DoH'
    Assert ($groups['油管视频'][1] -eq '美国节点') 'Wrong YouTube default'
    Assert ($groups['谷歌服务'][1] -eq '自动选择') 'Google default coupled to YouTube'
    Assert (-not ($groups['油管视频'] -contains '谷歌服务')) 'YouTube group must not offer the Google group'
    Assert ($groups['Gemini'][1] -eq '美国节点') 'Wrong Gemini default'
    Assert (($s['Remote Rule'] | Where-Object { $_ -match 'BiliBili.list' }) -match 'policy=DIRECT') 'Domestic apps must go DIRECT'
    Assert ('其他节点' -in $groups['自动选择'] -and '其他节点' -in $groups['代理节点']) 'Local/unlabelled nodes must stay reachable'
    foreach ($pool in @('自动选择','香港节点','台湾节点','日本节点','狮城节点','美国节点','韩国节点','其他节点')) {
        Assert ('url = https://www.gstatic.com/generate_204' -in $groups[$pool]) "Probe group must use Google HTTPS: $pool"
    }
    $filterMap = @{}
    foreach ($fl in $s['Remote Filter']) {
        $kv = $fl -split ' = ', 2
        if ($kv.Count -eq 2 -and $kv[1] -match 'FilterKey\s*=\s*"(.*)"$') { $filterMap[$kv[0].Trim()] = $Matches[1] }
    }
    $pattern = $filterMap['US_Filter']
    $positive = @('US','USA','us-01','US01','USA01','机场-US-01','美国01','🇺🇸 01','United States 01','America 01','洛杉矶01','SiliconValley')
    $negative = @('Russia','RUS-01','Australia','AUS-01','RUS01','AUS01','Austria','🇦🇺 Sydney','JP 日本','HK 香港','Business 01','Plus 01')
    foreach ($fixture in $positive) { Assert ([regex]::IsMatch($fixture,$pattern)) "US filter excludes $fixture" }
    foreach ($fixture in $negative) { Assert (![regex]::IsMatch($fixture,$pattern)) "US filter admits $fixture" }
    Assert ([regex]::IsMatch('Network 01', $filterMap['OT_Filter'])) 'Network 01 should land in OT_Filter'
    Assert ([regex]::IsMatch('Twitter 解锁', $filterMap['OT_Filter'])) 'Twitter 解锁 should land in OT_Filter'
    Assert ([regex]::IsMatch('Ukraine 01', $filterMap['OT_Filter'])) 'Ukraine 01 should land in OT_Filter'
    Assert ([regex]::IsMatch('🇬🇧 UK 01', $filterMap['OT_Filter'])) 'UK node should land in OT_Filter'
    Assert ([regex]::IsMatch('🇦🇺 澳洲 01', $filterMap['OT_Filter'])) 'AU node should land in OT_Filter'
    Assert (![regex]::IsMatch('Network 01', $filterMap['TW_Filter'])) 'TW filter false-matched Network'
    Assert (![regex]::IsMatch('Twitter 解锁', $filterMap['TW_Filter'])) 'TW filter false-matched Twitter'
    Assert (![regex]::IsMatch('Ukraine 01', $filterMap['KR_Filter'])) 'KR filter false-matched Ukraine'
    Assert (![regex]::IsMatch('JPanime 01', $filterMap['JP_Filter'])) 'JP filter false-matched JPanime'
    Assert ([regex]::IsMatch('HK01', $filterMap['HK_Filter']) -and [regex]::IsMatch('TW01', $filterMap['TW_Filter']) -and [regex]::IsMatch('JP01', $filterMap['JP_Filter']) -and [regex]::IsMatch('KR01', $filterMap['KR_Filter']) -and [regex]::IsMatch('SG01', $filterMap['SG_Filter'])) 'Region filters must match short code+digits'
    $rules = @($s['Rule'])
    Assert ($rules[-1] -eq 'FINAL,兜底策略') 'Changed FINAL'
    foreach ($rule in $rules) {
        $parts = $rule -split ','
        $policy = if ($parts[-1] -eq 'no-resolve') { $parts[-2] } else { $parts[-1] }
        Assert ($policy -in @('DIRECT','REJECT','REJECT-DROP') -or $groups.ContainsKey($policy)) "Unresolved rule policy: $policy"
    }
    foreach ($hostName in $wechat) { Assert ("DOMAIN,$hostName,DIRECT" -in $rules) "Missing WeChat protection: $hostName" }
    foreach ($weiboGuard in @('DOMAIN-SUFFIX,weibo.com.cn,DIRECT','DOMAIN-SUFFIX,miaopai.com,DIRECT')) { Assert ($weiboGuard -in $rules) "Missing Weibo guard: $weiboGuard" }
    foreach ($hostName in $images) {
        $index = [array]::IndexOf($rules,"DOMAIN,$hostName,REJECT")
        Assert ($index -ge 0 -and $index -lt [array]::IndexOf($rules,'DOMAIN-SUFFIX,weibo.com,DIRECT')) "Shadowed Weibo image block: $hostName"
    }
    foreach ($rule in $removed) { Assert ($rule -notin $rules) "Stale harmful/shadowed rule: $rule" }
    foreach ($needRule in @('DOMAIN-SUFFIX,umeng.com,REJECT-DROP','DOMAIN-SUFFIX,adsdk.com,REJECT-DROP','DOMAIN,dig.bdurl.net,REJECT','DOMAIN,cloudflare-dns.com,代理节点','IP-CIDR,1.1.1.1/32,代理节点,no-resolve','DOMAIN-SUFFIX,ts.net,DIRECT','DOMAIN-SUFFIX,cmpassport.com,DIRECT','AND,((DOMAIN,edith.xiaohongshu.com),(PROTOCOL,QUIC)),REJECT','AND,((DOMAIN,guide-acs.m.taobao.com),(PROTOCOL,QUIC)),REJECT','AND,((DOMAIN,api.m.jd.com),(PROTOCOL,QUIC)),REJECT','DOMAIN-SUFFIX,claude.com,人工智能','DOMAIN-SUFFIX,claudeusercontent.com,人工智能','DOMAIN,sydney.bing.com,人工智能','DOMAIN-SUFFIX,grok.com,人工智能','DOMAIN-SUFFIX,wabi.ai,人工智能','DOMAIN-SUFFIX,discord.com,代理节点','DOMAIN-SUFFIX,notion.com,代理节点')) {
        Assert ($needRule -in $rules) "Missing required local rule: $needRule"
    }
    foreach ($rule in $ytRules) { Assert ($rule -in $rules) "Missing YouTube route: $rule" }
    foreach ($hostName in $gemini) { Assert ("DOMAIN,$hostName,Gemini" -in $rules) "Missing Gemini route: $hostName" }
    $remoteRules = @($s['Remote Rule'])
    Assert (@($remoteRules | Where-Object { $_ -match 'blackmatrix7/.*/master/' -and $_ -notmatch '/Gemini/Gemini\.list' }).Count -eq 0) 'Non-Gemini bm7 rule still points to master'
    Assert (@($remoteRules | Where-Object { $_ -match 'Gemini/Gemini\.list' }).Count -eq 1) 'Missing Gemini remote rule'
    foreach ($reqRemote in @('/BlockHttpDNS/BlockHttpDNS\.list, policy=REJECT,.*enabled=true','/Discord/Discord\.list, policy=代理节点,.*enabled=true','/Notion/Notion\.list, policy=代理节点,.*enabled=true','/ChinaMax/ChinaMax_Domain\.list, policy=DIRECT,.*enabled=true','/ChinaMax/ChinaMax\.list, policy=DIRECT,.*enabled=true')) {
        Assert (@($remoteRules | Where-Object { $_ -match $reqRemote }).Count -eq 1) "Missing/bad remote rule: $reqRemote"
    }
    foreach ($rs in $s['Remote Script']) {
        Assert ($rs.Contains('enabled=false')) "Remote script should default disabled: $rs"
    }
    Assert ("$httpdns, enabled=false" -in $s['Plugin']) 'HTTPDNS plugin still enabled'
    Assert ("$httpdns, enabled=true" -notin $s['Plugin']) 'Duplicate enabled HTTPDNS plugin'
    Assert ('https://raw.githubusercontent.com/fmz200/wool_scripts/f6bcc087e4da7ebef3c596be4a3c0fa406661564/Loon/plugin/blockAds.plugin, enabled=true' -in $s['Plugin']) 'blockAds.plugin not pinned to latest audited commit'
    Assert ('https://raw.githubusercontent.com/fmz200/wool_scripts/f6bcc087e4da7ebef3c596be4a3c0fa406661564/Loon/plugin/WeChatMiniAds.plugin, enabled=true' -in $s['Plugin']) 'WeChatMiniAds.plugin not pinned to latest audited commit'
    foreach ($pl in $s['Plugin']) {
        if ($pl -match '(boxjs|script-hub)') { Assert ($pl.Contains('enabled=false')) "BoxJS/Script-Hub must be disabled by default: $pl" }
        if ($pl -notmatch 'enabled=false') {
            Assert ($pl -match '/[0-9a-f]{40}/') "Active plugin must be pinned to 40-char commit SHA: $pl"
        }
    }
    $ytPlugins = @($s['Plugin'] | Where-Object { $_ -match '(?i)youtube' })
    Assert ($ytPlugins.Count -eq 1 -and $ytPlugins[0] -eq "$maasea, policy=油管视频, enabled=true") 'YouTube plugin missing, duplicated or changed'
    $hosts = (($s['Mitm'] | Where-Object { $_ -like 'hostname = *' }) -replace '^hostname = ','') -split ',\s*'
    $excludes = @($hosts | Where-Object { $_.StartsWith('-') })
    Assert ($excludes.Count -ge 185) "Expected >= 185 MITM exclusions, got $($excludes.Count)"
    foreach ($hostName in $safeMitm + $apiMitm + @('youtubei.googleapis.com')) { Assert ($hostName -in $hosts) "Missing MITM entry: $hostName" }
    foreach ($hostName in $oldMitm) { Assert ($hostName -notin $hosts) "Broad/stale MITM entry: $hostName" }
    Assert ('skip-server-cert-verify = false' -in $s['Mitm']) 'MITM TLS verification weakened'
    foreach ($line in $s['Remote Proxy']) { Assert ($line.Contains('skip-cert-verify=false') -and $line.Contains('block-quic=true') -and $line.Contains('__REDACTED__')) 'Subscription security changed' }
    Assert ('disconnect-on-policy-change = false' -in $s['General']) 'Global disconnect enabled'
    Assert ('udp-fallback-mode = REJECT' -in $s['General']) 'UDP direct leakage enabled'
}

Check-Config $text
$mutations = [ordered]@{
    httpdns = @("$httpdns, enabled=false", "$httpdns, enabled=true")
    probe = @('香港节点 = url-test,HK_Filter,url = https://www.gstatic.com', '香港节点 = url-test,HK_Filter,url = http://cp.cloudflare.com')
    interval = @('HK_Filter,url = https://www.gstatic.com/generate_204,interval = 600', 'HK_Filter,url = https://www.gstatic.com/generate_204,interval = 30')
    dohDomain = @('doh-server = https://223.5.5.5/dns-query, https://1.12.12.12/dns-query, https://223.6.6.6/dns-query, https://120.53.53.53/dns-query', 'doh-server = https://dns.alidns.com/dns-query')
    httpdnsRule = @('/BlockHttpDNS/BlockHttpDNS.list, policy=REJECT, tag=BlockHttpDNS@bm7, enabled=true', '/BlockHttpDNS/BlockHttpDNS.list, policy=REJECT, tag=BlockHttpDNS@bm7, enabled=false')
    dohTunnel = @('IP-CIDR,1.1.1.1/32,代理节点,no-resolve', 'IP-CIDR,1.1.1.1/32,DIRECT,no-resolve')
    ytDefault = @('油管视频 = select,美国节点,', '油管视频 = select,谷歌服务,美国节点,')
    usFilter = @($usPattern, '(?i)(US|美)')
    twFilter = @('(?:^|[^A-Za-z])(?:TW|TWN)(?=$|[^A-Za-z])', 'TW')
    krFilter = @('(?:^|[^A-Za-z])(?:KR|KOR)(?=$|[^A-Za-z])', 'KR')
    worker = @('DOMAIN,init-stream.maasea.workers.dev,油管视频', 'DOMAIN,init-stream.maasea.workers.dev,DIRECT')
    gemini = @('DOMAIN,geller-pa.googleapis.com,Gemini', 'DOMAIN,geller-pa.googleapis.com,谷歌服务')
    weibo = @('DOMAIN,adimg.uve.weibo.com,REJECT', 'DOMAIN,adimg.uve.weibo.com,DIRECT')
    mitm = @('-*.12306.cn', '*.12306.cn')
    mitmNew = @(', -*.95508.com', '')
    bili = @('BiliBili.list, policy=DIRECT', 'BiliBili.list, policy=代理节点')
    tls = @('skip-server-cert-verify = false','skip-server-cert-verify = true')
    wechat = @('DOMAIN,dns.weixin.qq.com,DIRECT','DOMAIN,dns.weixin.qq.com,REJECT')
    sift = @('DOMAIN-SUFFIX,umeng.com,REJECT-DROP', 'DOMAIN-SUFFIX,siftscience.com,REJECT-DROP')
    boxjs = @('boxjs.rewrite.loon.plugin, policy=代理节点, enabled=false', 'boxjs.rewrite.loon.plugin, policy=代理节点, enabled=true')
    tasks = @('tasks.scripts, tag=定时任务合集@fmz200, enabled=false', 'tasks.scripts, tag=定时任务合集@fmz200, enabled=true')
    pluginPin = @('/1d9f51bc9a0077d81998bb503ee6158ca83faa73/weibo.sgmodule', '/main/weibo.sgmodule')
    chinaMax = @('/ChinaMax/ChinaMax.list, policy=DIRECT, tag=ChinaMax规则@bm7, enabled=true', '/ChinaMax/ChinaMax.list, policy=DIRECT, tag=ChinaMax规则@bm7, enabled=false')
}
foreach ($name in $mutations.Keys) {
    $bad = $text.Replace($mutations[$name][0], $mutations[$name][1])
    Assert ($bad -cne $text) "Mutation did not apply: $name"
    $caught = $false
    try { Check-Config $bad } catch { $caught = $true }
    Assert $caught "Mutation not detected by semantic checks: $name"
}
Write-Output "PASS: section/general/group/filter/rule/remote/plugin/MITM/security checks, C7 boundary fixtures, 24 US fixtures, $($mutations.Count) negative mutations."

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
