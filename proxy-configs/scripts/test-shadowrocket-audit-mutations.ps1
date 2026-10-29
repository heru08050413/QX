# In-memory negative tests; no configuration or temporary file is written.
$ErrorActionPreference = 'Stop'
$testPath = Join-Path $PSScriptRoot 'test-shadowrocket-known-fixes.ps1'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../shadowrocket_V26.00.lsr') -Raw -Encoding utf8
$cases = @(
    @{ Name='HTTP YouTube probe'; From='url=https://www.gstatic.com/generate_204'; To='url=http://www.gstatic.com/generate_204' },
    @{ Name='Upload button restored'; From='"blockUpload":true'; To='"blockUpload":false' },
    @{ Name='WeChat DNS protection removed'; From='DOMAIN,dns.weixin.qq.com,DIRECT'; To='# removed by mutation' },
    @{ Name='Weibo ad incorrectly allowed'; From='DOMAIN,adimg.uve.weibo.com,REJECT'; To='DOMAIN,adimg.uve.weibo.com,DIRECT' },
    @{ Name='Stable pool reintroduced'; From='Instagram = select, 美国节点,'; To='Instagram = select, 美国稳定,' },
    @{ Name='AI default changed'; From='AI = select, 美国节点, 新加坡节点, 日本节点, AutoSelect'; To='AI = select, DIRECT' },
    @{ Name='DNS changed'; From='dns-direct-fallback-proxy = false'; To='dns-direct-fallback-proxy = true' },
    @{ Name='MITM expanded'; From='hostname = -*.alipay.com'; To='hostname = *, -*.alipay.com' },
    @{ Name='YouTube pin lost'; From='/65075cdb388fc5e3094afd7e7314c67b243f3525/'; To='/master/' },
    @{ Name='Weibo SDK blocked'; From='DOMAIN-SUFFIX,weibomingzi.com,REJECT'; To="DOMAIN-SUFFIX,sdkapp.uve.weibo.com,REJECT`nDOMAIN-SUFFIX,weibomingzi.com,REJECT" },
    @{ Name='Region pools back on Cloudflare probe'; From='美国节点 = url-test, url=https://www.gstatic.com/generate_204'; To='美国节点 = url-test, url=http://cp.cloudflare.com/generate_204' },
    @{ Name='Region probes too often (battery)'; From='美国节点 = url-test, url=https://www.gstatic.com/generate_204, interval=900,'; To='美国节点 = url-test, url=https://www.gstatic.com/generate_204, interval=30,' },
    @{ Name='Region probe timeout too aggressive'; From='interval=900, tolerance=200, timeout=5'; To='interval=900, tolerance=200, timeout=1' },
    @{ Name='YT-Auto reintroduced'; From='YouTube = select, 美国节点,'; To='YouTube = select, YT-Auto, 美国节点,' },
    @{ Name='General probes accidentally sped up'; From='AutoSelect = url-test, url=http://cp.cloudflare.com/generate_204, interval=900'; To='AutoSelect = url-test, url=http://cp.cloudflare.com/generate_204, interval=30' },
    @{ Name='Region group type changed'; From='香港节点 = url-test,'; To='香港节点 = fallback,' },
    @{ Name='Gemini selector split again'; From='Gemini = select, 谷歌服务'; To='Gemini = select, 美国节点' },
    @{ Name='Google selector cycle'; From='谷歌服务 = select, 美国节点, AutoSelect'; To='谷歌服务 = select, Gemini, AutoSelect' },
    @{ Name='Meta API missing'; From='DOMAIN-SUFFIX,meta.ai,Meta'; To='# removed by mutation' },
    @{ Name='Muse auth subdomains missing'; From='DOMAIN-SUFFIX,muse.ai,Meta'; To='DOMAIN,muse.ai,Meta' },
    @{ Name='Meta suffix too broad'; From='DOMAIN-SUFFIX,meta.ai,Meta'; To='DOMAIN-KEYWORD,meta,Meta' },
    @{ Name='Meta CDN split again'; From='DOMAIN-SUFFIX,fbcdn.net,Meta'; To='DOMAIN-SUFFIX,fbcdn.net,Proxy' },
    @{ Name='Google local fallback missing'; From='DOMAIN-SUFFIX,googleapis.com,谷歌服务'; To='# removed by mutation' },
    @{ Name='Spotify region changed'; From='Spotify = select, 新加坡节点, 香港节点, 日本节点, 美国节点'; To='Spotify = select, 美国节点, 新加坡节点, 香港节点, 日本节点' },
    @{ Name='Default Proxy not US'; From='Proxy = select, 美国节点, AutoSelect'; To='Proxy = select, AutoSelect, 美国节点' },
    @{ Name='Domestic fallback changed'; From='Final = select, DIRECT, Proxy'; To='Final = select, Proxy, DIRECT' },
    @{ Name='Meta tracking unblocked'; From='DOMAIN-SUFFIX,xz.fbcdn.net,REJECT-DROP'; To='DOMAIN-SUFFIX,xz.fbcdn.net,Meta' },
    @{ Name='Google auth early guard missing'; From='DOMAIN,accounts.google.com,谷歌服务'; To='# removed by mutation' },
    @{ Name='Tailscale range excluded from TUN'; From='bypass-tun = 10.0.0.0/8, 127.0.0.0/8'; To='bypass-tun = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8' },
    @{ Name='Tailscale IPv4 policy missing'; From='IP-CIDR,100.64.0.0/10,TAILSCALE,no-resolve'; To='# removed by mutation' },
    @{ Name='Tailscale MagicDNS policy missing'; From='DOMAIN-SUFFIX,ts.net,TAILSCALE'; To='# removed by mutation' }
)
& $testPath -ConfigText $source
foreach ($case in $cases) {
    if (!$source.Contains($case.From)) { throw "Mutation fixture missing: $($case.Name)" }
    $rejected = $false
    try { & $testPath -ConfigText ($source.Replace($case.From, $case.To)) | Out-Null }
    catch { $rejected = $true }
    if (!$rejected) { throw "Mutation escaped regression checks: $($case.Name)" }
    Write-Output "PASS (rejected): $($case.Name)"
}
Write-Output "PASS: $($cases.Count) in-memory negative cases; configuration unchanged."
