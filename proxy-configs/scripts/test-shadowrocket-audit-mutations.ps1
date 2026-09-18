# In-memory negative tests; no configuration or temporary file is written.
$ErrorActionPreference = 'Stop'
$testPath = Join-Path $PSScriptRoot 'test-shadowrocket-known-fixes.ps1'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../shadowrocket_V26.00.lsr') -Raw -Encoding utf8
$cases = @(
    @{ Name='HTTP YouTube probe'; From='url=https://www.gstatic.com/generate_204'; To='url=http://www.gstatic.com/generate_204' },
    @{ Name='Upload button restored'; From='"blockUpload":true'; To='"blockUpload":false' },
    @{ Name='WeChat DNS protection removed'; From='DOMAIN,dns.weixin.qq.com,DIRECT'; To='# removed by mutation' },
    @{ Name='Weibo ad incorrectly allowed'; From='DOMAIN,adimg.uve.weibo.com,REJECT'; To='DOMAIN,adimg.uve.weibo.com,DIRECT' },
    @{ Name='Stable group ranks latency'; From='美国稳定 = fallback,'; To='美国稳定 = url-test,' },
    @{ Name='AI default changed'; From='AI = select, 新加坡节点, 美国节点, 日本节点, AutoSelect'; To='AI = select, DIRECT' },
    @{ Name='DNS changed'; From='dns-direct-fallback-proxy = false'; To='dns-direct-fallback-proxy = true' },
    @{ Name='MITM expanded'; From='hostname = -*.alipay.com'; To='hostname = *, -*.alipay.com' },
    @{ Name='YouTube pin lost'; From='/65075cdb388fc5e3094afd7e7314c67b243f3525/'; To='/master/' },
    @{ Name='Weibo SDK blocked'; From='DOMAIN-SUFFIX,weibomingzi.com,REJECT'; To="DOMAIN-SUFFIX,sdkapp.uve.weibo.com,REJECT`nDOMAIN-SUFFIX,weibomingzi.com,REJECT" }
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
