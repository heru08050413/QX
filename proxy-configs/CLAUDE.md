# 项目:iOS 代理配置维护(四 App 差异化)

本仓库维护四份 iOS 代理 App 配置。目标优先级:**安全 > 稳定性 > 去广告 > 低功耗**。
策略不是合并成一套,而是**安全层求同、能力层存异**——每个 App 发挥自身独有架构能力。

文件:
- `shadowrocket_V26.00.lsr` — Shadowrocket
- `quantumult_B_V26.00` — Quantumult X
- `Egern_Pro_V26.00.yml` — Egern(YAML)
- `Loon_V26.00` — Loon
- `Stash_V26.00.yaml` — Stash(2026-07 纳入;Clash 系语法,fake-ip + 纯分流轻量定位,无 MITM/脚本层;规则源为 Coldvvater/Mononoke 单一个人仓库,已入巡检)
- `Stash_AdBlock_V26.00.stoverride` — Stash 去广告覆写(**Override/`.stoverride` YAML 格式** —— Stash 只有 Override/Rewrite/MitM/Script 四入口,**不吃 `.sgmodule`**;纯 `rules:` 网络层 REJECT,覆写数组插到原规则最前、不替换分流,零脚本零 MITM 零腐坏)。信息流/开屏这类需脚本的去广告,指向维护良好的 `.stoverride`(deezertidal 系:微博/微信公众号/知乎/YouTube/去广告合集,原生 Override 格式)。
  > 教训:Stash≠Surge/Loon —— `.sgmodule`(blockAds 等)在 Stash 里导入会报"格式不正确",必须用 `.stoverride`(YAML)。
- `Stash_AppAdBlock_V26.00.stoverride` — Stash **具体 App 深度去广告**覆写(**需开 MITM 并信任证书**)。从 fmz200/blockAds 精选 14 个消费类 App(京东/淘宝/闲鱼/小红书/拼多多/百度网盘/阿里云盘/高德/有道/汽车之家/钉钉/我要自学网/知乎/联通/电信)的开屏与信息流去广告,把 `[URL Rewrite]` reject + `[Map Local]` 按 Script-Hub 的 Stash 映射折叠进 `http.url-rewrite:`(`reject`/`reject-dict`/`reject-array`/`reject-200`/`reject-img`),**纯静态正则、零外部脚本 = 不会因脚本死链而腐坏**。
  > 三条硬约束(实事求是):① **不含任何银行/支付/政务/证件类 App**(京东金融/12306/个人所得税/航旅纵横一律不 MITM);② Stash 的 `rules:` **不吃 `URL-REGEX`/`PROTOCOL`**(Script-Hub 自身会把 `URL-REGEX` reject 迁到 url-rewrite),已在转换时剔除以保证导入;③ B站/YouTube 的信息流去广告依赖**特制 payload / 外部脚本**(非简单 reject),不硬转,指向 BiliUniverse/ADBlock 与 Maasea/YouTube.Enhance 维护版,本文件仅收其安全网络规则。
- `Stash_Script_V26.00.stoverride` + `scripts/*.js`(13 个)— **信息流脚本级去广告合集**。开屏/独立广告接口靠 url-rewrite 整条 reject 即可(见上一份);**信息流里混排的广告**要解析 JSON、逐条删广告保正文,必须用脚本。覆盖 14 App:知乎·小红书·微博·淘宝·京东·爱奇艺·优酷·芒果TV·什么值得买·滴滴出行·大众点评·夸克·有道词典·阿里云盘(83 hooks / 46 MITM 域 / 13 providers)。
  > 架构关键(避免重蹈"Scripts Not Downloaded"):脚本 JS **全部镜像进本仓库 `scripts/`**、`.stoverride` 的 `script-providers.url` 只引**自己仓库的 raw 链接**——第三方死链风险归零,只剩"App 改接口→标记字段变"的逻辑腐坏(用得多的 App 社区盯得紧,同步上游即可)。上游源 @fmz200(wool_scripts)/@yichahucha(微博 wb_ad)/@zirawell(R-Store),13 个上游 URL 已入巡检 EXTRA_URLS,上游死/大改即回本仓库 diff 同步。
  > 移植时踩到的两个 Stash 兼容点:① **atomic group `(?>...)` Stash 正则不吃**(JS/RE2 均不支持)→ 转 `(?:...)`(此处简单择一, 语义等价);② 爱奇艺有一条 **IP 主机 hook**(`[\d.]+`)无法 MITM, 在 Stash 上失效(域名 hook 已覆盖首页/feed)。全部 JS 过 `node --check`、全部 match 过 `new RegExp` 编译。
  > **不收录**:B站(kokoryh/Sparkle 依赖 `engine=webview`+protobuf, Stash 无 webview)、网易云音乐/百度贴吧/Spotify/YouTube(binary-body-mode protobuf)、银行/政务/证件类(12306/航旅纵横/招商证券/建行生活/买单吧…一律不 MITM)。
- `Stash_All_V26.00.stoverride` — **三合一总覆写**(上面三份合并, 一个链接全都有)。`rules:` 81 条(网络层 REJECT + App 网络规则)、`http.mitm:` 80 域(两份去重)、`http.url-rewrite:` 94 条、`http.script:` 83 hooks、`script-providers:` 13。①网络层免 MITM 即生效;②③需开 MITM。**三份分文件保留**(便于按需单开某层);总文件供"一键全量"。由 `/tmp/merge.py` 从三份源文件抽段合并生成,177 条 url-rewrite+script 正则全过 `new RegExp` 编译。

> 版本号:五套已统一对齐到 **V26.00**(文件名与各文件头一致);各文件内的历史修订日志(2.6.x / 5.1.x / 6.x / 2.x / 4.0)保留作为沿革记录。
> Stash 与安全基线的适用性:无 MITM 段 → 基线 1/6 不适用;基线 2(保护区)以本地 `qq.com.cn`/`teg` 规则实现;基线 5 例外——Stash 采用 `MATCH→漏网之鱼(默认代理)+ CN 白名单` 的 fail-closed 哲学,与四套 Final=DIRECT 是两种自洽取舍,不强行对齐。

---

## 一、安全基线(四套必须逐字一致,改任何一个都要对齐另外三个)

1. **MITM 排除清单**:银行/支付/登录/账户子域必须全部排除(`*.alipay.com`、`*.unionpay.com`、`*.cmbchina.com`、`*.icbc.com.cn`、`passport.*`、`account.*`、`pay.*`、`*.icloud.com` 等)。少一个 = 一个高敏感解密缺口。
2. **保护区顺序**:微博/新浪、微信(`*.qq.com.cn`、`teg.tencent-cloud.net`)、字节系的 `DIRECT` 规则必须排在广告 `REJECT` 段**之前**。
3. **熔断**:高频重试源用 `REJECT-DROP`(静默丢包),不是 `REJECT`。
4. **配置文件绝不内嵌订阅 token**(见禁止项)。
5. **Final 默认 `DIRECT`**。
6. **统一 QUIC 策略(V26.00 起)**:凡 MITM 去广告依赖的域名,必须强制走 TCP(MITM 无法解密 QUIC/HTTP3,QUIC = 去广告盲区且失效无报错)。**各 App 用自己架构内的确定性手段实现,不依赖模糊的全局开关**:
   - **SR**:`[Rule]` 段 `AND,((DOMAIN-SUFFIX,x),(PROTOCOL,UDP)),REJECT`(§0.55);`block-quic=auto` 语义无权威文档,不作依赖。
   - **Egern**:`rules` 段 `and:[domain_suffix + protocol:quic]→REJECT`(§0.68);全局 `block_quic:false` 保留 HTTP/3。
   - **QX**:无协议级规则,用 `udp_whitelist=53, 80-427, 444-65535` 掐掉 UDP 443(官方样例写法)。
   - **Loon**:无 `AND` 复合规则,但**内建"QUIC SNI 命中 MITM 列表即自动 reject"**;~~故移除节点级 `block-quic`~~ → **稳定性审查已反转:恢复节点级 `block-quic=true`**。原移除逻辑在去广告视角成立,但 googlevideo 不在 MITM(省电),代理侧 YouTube QUIC 在 Loon 架构内**无任何其它拦截手段**——节点 UDP 半死时 YouTube 挂死且 TCP 探针查不出。按优先级"稳定>低功耗/速度",牺牲代理侧 HTTP/3 换确定性。
   - **Stash**:`AND,((DOMAIN-SUFFIX,googlevideo.com),(NETWORK,udp)),REJECT`(+youtubei;置于 YouTube 分流之前)。
7. **探针同源原则(稳定性审查新增;fix2 修正落地方式)**:健康探针必须与它守护的业务**同源**。全用 `cp.cloudflare.com/generate_204` 的盲区:节点"能到 Cloudflare 但到不了 Google"(出口 IP 被 Google 封禁/限流是机场常态故障)时探针全绿、url-test 永不切换,YouTube 挂死只能手动换节点/重开 App。落地:SR/Loon/Stash 均建 `YT-Auto` fallback 组,探针 `http://www.gstatic.com/generate_204`(Google 自家 204),interval=600 仅此一组控耗电。
   - ⚠️ **fix2 血的教训——`YT-Auto` 成员必须是【地区池】,不能是【裸节点】**:初版 SR 把它写成 `fallback + 仅 policy-regex-filter`,成员=订阅全部节点、按订阅原始顺序,fallback 永远钉在"列表第一个能回 204 的节点"。恶果:① 选点从"全池选最快(url-test)"退化成"随缘第一个"(订阅排序与质量无关);② 204 小包只测【可达】不测【吞吐】,拥挤到卡视频的烂节点照样回 204、永不切走 → **YouTube 反而变差**。正确写法(Loon/Stash 一直是对的):成员=各地区 url-test 池 → 池【内】保最快、池【间】保 Google 可达自愈,两个目标都不牺牲。
   - ⚠️ **`YT-Auto` 只给 `YouTube`(大流量视频)当默认;`谷歌服务` 默认必须留 `AutoSelect`**:谷歌服务承载 `accounts.google.com`/`googleapis` 等轻流量登录接口(AI 应用的会话续期也走这里),让它默认走 YT-Auto 会把 AI 一起拖进自愈组、拖慢——这是 fix2 里"AI 也变差"的传导路径。YT-Auto 只作谷歌服务的备选。
   - **QX**:`server_check_url` 是否支持按组覆盖无权威文档,真机验证前不动;**Egern**:探针 URL 是全局单值(`proxy_latency_test_url`),架构上做不了按组分探针,记录为已知限制。
8. **UDP fail-fast(稳定性审查新增)**:"节点不支持 UDP 时的回落"必须 REJECT 而非 DIRECT(SR `udp-policy-not-supported-behaviour` / Loon `udp-fallback-mode`)。DIRECT 把境外 UDP 直连发出=被墙黑洞=应用挂死 60-90s;REJECT 立即失败=应用秒切 TCP。"保微信 VOIP"论据不成立:国内 UDP 在命中代理策略前已被 GEOIP CN 判 DIRECT,到不了该开关。

> 改动前后都跑一遍这 8 条。这一层不参与差异化。

---

## 二、各 App 定制方向(放大独特能力,不要互相抄)

### Shadowrocket —— 低功耗 + 极致稳定的日用机
- **发挥**:`[Host]` 段 per-domain DNS 解析器路由(`域名 = server:DoH`);最省电、最成熟。
- **做**:坚持降耗(MITM 最小化、测速 interval 900s、`googlevideo` 移出 MITM);去广告保持"网络层 REJECT + 少量脚本"的中等强度。
- **别勉强**:不支持 Fake-IP(架构限制),DNS 是全局单池;不要往重脚本/最大化去广告方向推。

### Quantumult X —— 自动化 / 脚本 / 任务中枢
- **发挥**:`[task_local]` 的 **cron 定时任务**(四个里唯一强项);rewrite 引擎 + BoxJS。
- **做**:把签到/周期检查/Cookie 捕获/复杂 rewrite 集中到这里。**当前 `[task_local]` 全是手动触发的 `event-interaction`,没用上 cron——这是该补的地方。**
- **别勉强**:策略组 failover 模型弱(`static` 是手动选择不是自动故障转移),关键 failover 别压这里;无 Fake-IP,未显式钉境外 DoH 的长尾境外站会泄露给国内 DNS。

### Egern —— 精密路由 / 规则引擎的权威源
- **发挥**:逻辑 `and/or/not` 规则、`url_regex`、用 `proxy_rule_set` 当 DNS 分流条件、YAML 可 diff。
- **做**:在这里**编写和验证最精细的路由逻辑**,验证通过再把简化版移植到其他三个;去广告模块**去重**(保 `blockAds` + B站 `BiliUniverse` + 微博 `zmqcherish`,关掉重叠的 `Daily`/`NobyDa` 冗余)。
- **别勉强**:v6.5 的 **TUN + 境外 NextDNS 不是默认选项**——它把 DNS 稳定性绑定到节点稳定性、且更耗电(配置自己标注了)。"放大 Egern" 指放大它的规则/DNS 引擎,**不等于必须开 TUN**。若稳定性优先,可在非 TUN 模式跑它更强的规则引擎。

### Loon —— Fake-IP 防泄漏的干净 DNS 日用机
- **发挥**:**Fake-IP**(SR 做不到)、`hijack-dns`、原生 `fallback`。
- **做**:国内域名走国内 DoH(就近 CDN),境外走 Fake-IP→代理节点出口解析(天然防污染、零泄露、不等 1.1.1.1);维护好 `real-ip` 排除表(部分游戏/直连 IP 服务需要)。
- **注意**:正因为有 Fake-IP,Loon 的"国内 DoH 优先"是合理的,不属于泄露问题。
- **别勉强**:`[Host]` 只能做 IP 映射,**不能**复刻 SR 的 per-domain DNS 路由写法。

---

## 三、禁止项(硬约束,任何改动不得违反)

- ❌ **不得在任何配置文件写入真实订阅 token**。已有的(Loon `[Remote Proxy]`、QX `[server_remote]`)用占位符替代,如 `https://YOUR_AIRPORT/subscribe?token=__REDACTED__`。
- ❌ **不得把含 token 的文件提交到 git 或推到任何远程**。`git init` 之前先 scrub;token 会进 git 历史,删了也留痕。
- ❌ **不得降低证书校验**:`skip-cert-verify` / `skip_validating_cert` 保持 `false`(Loon 节点上的 `skip-cert-verify=true` 已于 v2.2.1 修复)。
- ❌ **不要尝试改 MITM CA 口令或重新生成证书**——只能在各 App 内手动操作,配置文件无法自动化。Egern 的 `ca_passphrase: egern` 是默认弱口令,在说明里提示用户去 App 改,但不要在文件里硬写新口令。
- ✅ 改远程规则源时,bm7 系把 URL 里 `/master/` 改 `/release/`(人工发布,降静默失效)。**但不可一刀切**:必须逐路径联网核验 release 是否提供该路径(见 §六-1),否则会把 404 静默引进来。
- ✅ 每次改动走 git commit,保证可回滚、可 diff review。

---

## 四、Claude Code 在本任务里**做不到**的事(交还给用户)

- 真机测试、观察 iPhone 上的实际去广告/连通效果。
- 重新生成或安装 MITM 根证书。
- 验证机场节点本身是否可用(token 已脱敏,且需真实订阅)。
- 离线环境下验证远程规则集 URL 是否仍返回 200。

这些请在结论里明确标注为"需用户手动验证",不要假装已完成。

---

## 五、工作方式

- 先**只读审查 + 出改动清单**,等确认后再逐文件修改。一次改一个 App,不要四个一起动。
- Egern 是 YAML,可做语法校验(`yq`/`python -c 'import yaml'`)后再保存。
- 每个改动在说明里写清:动了什么、为什么、影响哪三维(安全/稳定/功耗)、是否需要用户手动跟进。

---

## 六、经验沉淀(2026-06 审查轮)

1. **`/master → /release/` 不能一刀切,必须逐路径验证。**
   release 分支是 bm7 人工发布的子集,**并非每个 master 路径都有对应 release 版本**。本轮实测到的缺口:
   - QX `rule/QuantumultX/Gemini/Gemini.list` —— release 上 404(启用中!),保留 master。
   - SR `rule/Shadowrocket/ChinaMax/ChinaMax_IP.list` —— master/release 皆 404(见下)。
   改之前对每个 URL 跑一次 `curl -o /dev/null -w "%{http_code}"`,只切返回 200 的;其余保留 master 并注明原因。

2. **远程 URL 死链巡检 —— 已脚本化为 `scripts/url-health-sweep.sh`,每次大改必跑。**
   累计四轮审查查实 **17+ 处静默死链**(iOS 代理 App 对 404 是静默失败,去广告悄悄失效无报错),其中绝大多数集中在"个人维护脚本/整库重构"(ddgksf2013 Filter 目录整删、zmqcherish/Maasea/NobyDa 各自删文件)。教训:**"写了就生效""历史悠久=稳定"都被证伪**。运行 `bash scripts/url-health-sweep.sh`,退出码非 0 即有死链;`⚠ WARN` 项(自托管域/releases-latest/DoH 端点/gist,在受限出口会假阳)需真机人工核实。
   历史查实死链存档:
   审查发现两个**自始就失效、却因 enabled=false 或无报错而长期隐藏**的远程源:
   - QX `BlockAppleOTA/BlockAppleOTA.list` —— bm7 QuantumultX 目录无此清单(master/release 皆 404),`enabled=false` 掩盖。
   - SR `ChinaMax/ChinaMax_IP.list` —— 路径写错(正确为 `ChinaIPs/ChinaIPs.list`),且该 RULE-SET **启用且无开关**,故"国内 ISP CIDR 兜底"自 v2.6.1 起从未真正加载。已更正。
   **建议**:每次大改顺手对所有远程 URL(规则集/脚本/模块)做一次 200 巡检,别假设"写了就生效"。

3. **基线"逐字一致"是目标而非现状。** 本轮才把 SR 的银行/支付/icloud MITM 排除补齐(原仅其余三套有)。新增/修改安全基线项时,务必四套同步,并跑一次跨文件 diff 确认。

4. **远程源优先 `raw.githubusercontent.com`,避开 jsDelivr / 第三方镜像站。** 用户实测 `fastly.jsdelivr.net`、`cdn.jsdelivr.net`、`clashios.app` 在国内均 000(被墙/污染)——这是 Stash "Scripts Not Downloaded" 的真正根因,也曾潜伏在我们自己的 Loon(GeoIP/ASN 库)、QX(resource-parser)里,V26.00 已全部切回 raw。规律:这些配置走代理,`raw.githubusercontent.com` 经代理稳定可达,而 jsDelivr 的公共 CDN 反而不稳。新增远程源时选 raw 原始地址,不要图"加速"用 jsDelivr。

---

## 七、需用户手动跟进清单(配置无法自动完成)

> 以下为审查轮结论中标注"需用户手动"的项,集中归档。Claude Code 不能代办。

- **Loon**:`skip-cert-verify` 已改 false;逐节点真机验证连通(若某节点连不上,是该节点证书问题,找机场修,勿改回 true)。
- **Egern**:
  - App 内重新生成 `egern.p12` 并把 `ca_passphrase` 从默认 `egern` 改成强口令。
  - 把 DNS `forward` 层 0.08 的"机场节点域名 → bootstrap"模板填上你机场的真实节点根域(若节点用 IP 字面量则免);填后真机验证 TUN 模式连通。
  - 模块去重(关 Daily/NobyDa)后,留意是否有个别 App 广告回潮,需要时单独重开定位。
- **QX**:
  - `[task_local]` 三条 cron 目前是 `enabled=false` 模板,把占位脚本/账号换成真实值并在 App/BoxJS 授权后再启用;链路巡检那条确认 cron 下"仅异常时通知"。
  - `BlockAppleOTA` 另寻有效上游源或删除该行(当前死链,已禁用)。
- **四套通用**:重置机场订阅并作废旧 token、在各 App 内重填真实订阅、生成并信任 MITM 根证书、真机观察去广告与连通效果、离线无法验证的远程 URL 在真机更新时再确认。
