# Stash Pro V26.00

新配置，内部修订 `1.0.0`，2026-09-20。原有 Stash、Shadowrocket、Egern、Loon、Quantumult X 文件均不改动。

本次核对的 [App Store 正式版为 3.4.1](https://apps.apple.com/us/app/stash-rule-based-proxy/id1596063349)。Wiki 已出现标注 3.6+ 的能力，本配置不使用这些尚未在本次商店页面确认发布的字段。桌面静态/脚本测试不等于 iPhone 原生验收。

## 文件与安装

| 文件 | 用途 | 必需条件 |
| --- | --- | --- |
| [Stash_Pro_V26.00.yaml](Stash_Pro_V26.00.yaml) | 主分流、DNS、自动切换、网络层广告过滤 | 必须先绑定有效机场 |
| [Stash_Pro_Airport.example.stoverride](Stash_Pro_Airport.example.stoverride) | 私有机场入口模板 | 导入为本地副本，手机内修改 |
| [Stash_Pro_AppAds_V26.00.stoverride](Stash_Pro_AppAds_V26.00.stoverride) | 微博/知乎/小红书明确广告项、部分开屏 | 自己的 MITM CA；可独立关闭 |
| [Stash_Pro_YouTube_V26.00.stoverride](Stash_Pro_YouTube_V26.00.stoverride) | YouTube 广告/PiP/上传按钮增强 | 阅读下方第三方 Worker 风险后自行启用 |

主配置远程地址（发布到 main 后使用）：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_V26.00.yaml
```

本地机场模板地址：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_Airport.example.stoverride
```

两份可选去广告覆写地址：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_AppAds_V26.00.stoverride
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_YouTube_V26.00.stoverride
```

1. 在 Stash 导入并选中**新主配置**，不要覆盖你正在使用的旧配置。先不要开启新配置的 VPN。
2. 把机场模板保存/导入为**本地覆写**，不是继续从 GitHub 自动刷新的远程私有文件。在本地编辑 `proxy-providers.Airport.url` 为机场提供的 **Stash/Clash YAML 节点订阅**。保持 `Airport` 名称不变，保存并启用此本地覆写。
3. 更新 `Airport`，确认不是占位链接、返回非空节点列表且至少两条节点测速成功；核对节点证书验证未被机场关闭。才开启 VPN。**Stash 官方说明空策略组/空远程集可能退化为 DIRECT，本配置不是空订阅下的防泄漏开关。**没有有效节点就不要启动。
4. 首次导入的 `默认代理` 与 `YouTube` 默认是 **REJECT**，防止未绑定机场就误以为境外代理已生效。完成节点检查后，手动改为 `默认代理 → 稳定切换`、`YouTube → 稳定切换`。在 `AI` 中测试目标服务；默认跟随默认代理，需要固定地区时直接选你已验证支持服务的节点。此初始保护不能阻止你后来选中的组在订阅变空时退化，仍需检查更新结果。
5. 先验证基础连通，再逐个启用 App / YouTube 覆写。启用 HTTPS 过滤需要在 Stash 内生成或选用**自己的** CA，安装并在 iOS 证书信任设置中完全信任，然后开启 MITM。公共文件不包含 CA、口令或真实订阅。
6. 不要同时开启旧 `Stash_All`、`Stash_Script` 或其他重叠的 YouTube/App 去广告模块。覆写是用户在客户端启用的，主文件不会自动导入它们。

首次下载 GitHub 资源若失败，可先保持现有可用客户端/旧配置完成下载，随后关闭旧 VPN 再启用 Stash；不要同时运行多个 VPN。节点已下载但规则/脚本未下载，也不能算安装完成。

## 反复更换机场，不重做配置

以后只改**同一个本地机场覆写**的两项：

```yaml
proxy-providers:
  Airport:
    url: 'https://你的新机场提供的订阅地址'
    path: ./providers/stash-pro-airport-private-v2.yaml
```

每次换机场递增缓存后缀 `v1 → v2 → v3`，保存、手动更新、核对新节点与测速结果，再重启连接并检查各策略组。旧机场的节点手动选择不会自动映射到新机场；必要时重新选回 `稳定切换`。同一机场正常更新节点无需修改后缀。

主配置从 GitHub 刷新时，本地覆写仍以同名 `Airport` 键覆盖其 URL；不要把私有副本切回远程更新，否则可能被模板占位符覆盖。不要将含 token 的文件提交到任何仓库，也不要把私人订阅交给公共转换站。机场仅提供通用 Base64/不兼容节点协议时，先向机场索取 Stash 原生支持格式。

这是**一个可反复替换的机场入口**，不是同时多机场聚合。订阅格式/服务端协议仍需 Stash 支持，不能承诺任意机场链接通用。

## 分流与稳定性

- 局域网和 DNS → 国内通信/支付关键功能域 → 广告过滤 → YouTube → AI → Google/国际媒体/Telegram → Apple/Microsoft → 国内清单与国内 IP → 默认代理兜底。
- 微博、知乎关键 API 先直连保护，广告混在正文 API 内时由 HTTP 脚本删除明确广告项。其余独立广告域仍受网络广告规则拦截，不整站放行广告。
- Google 默认跟随 AI，YouTube 独立选择，避免仅为视频换节点时顺带改变 Google 登录出口。Gemini/Copilot 显式规则优先于 Google/Microsoft 宽规则。
- Fake-IP 使用 Stash 原生机制；没有全匹配排除 `*`。国内 DoH 双上游直连，局域网管理域单独走系统 DNS。未启用 DNS 跟随代理，避免机场域名解析与代理启动相互等待。没有承诺“所有 DNS 零泄漏”；应用自带 DoH/纯 IP 请求需单独观察。
- 只有目标域的应用层 UDP 443 被拒绝，以便 YouTube / 被 MITM 的 API 改用 TCP。没有全局封杀 UDP，也没有修改 HY2/TUIC 节点隧道参数。仅靠此域名规则不保证覆盖所有无域名关联的 QUIC 请求。
- `稳定切换` 是原生 `fallback`，120 秒周期、8 秒节点测试超时。按订阅顺序取健康节点，优先节点恢复时可能切回；不声称“永不回切”。如订阅首个节点吞吐差，可在手机调整节点顺序或选手动节点。手动固定节点不自动故障切换。
- Stash 同一节点跨策略组共享测速结果，因此在**机场 provider 上设置 Google 的 HTTPS 204 探针**，不把其他客户端的组内 `url:` 当作独立探针。HTTPS 可以检查基本 TLS 连通，但比官方偏向 HTTP 的测速建议稍重。
- 探针仅证明该测试地址可访问，**不代表 YouTube CDN 带宽、无广告、Gemini 地区准入或账户状态合格**。两分钟不是恢复时限保证；切换不能迁移既有 TCP/QUIC 会话，YouTube 仍可能短暂缓冲，全部节点故障时无法恢复。
- 未使用按地区名称过滤的空组；AI 默认自动组可能含服务不支持的地区，需用户验收并选点。需要“限定地区且自动切换”时，必须先看到实际节点命名/非空池再制作专用私有覆写，不能靠随意的 `US` 正则猜测。

## 去广告范围与风险

### 网络层（主配置默认生效）

使用单一 Loyalsoldier `release/reject.txt`，每天更新；规则为 `domain` 索引格式，不叠加数套重复的大清单。国内路由、私有域名和 CN IP 亦采用 indexed 清单。它们是动态外部依赖，某次 HTTP 200 不代表以后永远正确；缓存不能替代首次下载。

主配置的 `广告过滤 → DIRECT` 可临时排查网络误杀，不影响其他分流；它不会关闭 HTTP 脚本。不要通过取消 TLS 校验解决下载问题。

### App 信息流（可选覆写）

小型内嵌脚本只处理声明的微博时间线、知乎推荐/next 接口、小红书首页/搜索/开屏。仅删除识别到的明确广告标记，保留普通推荐、正文、评论、付费条目及分页字段。空响应、非 JSON、错误状态、未知结构返回 `$done({})` 保留原响应；不打印用户内容、不请求外部服务、不读持久存储。

不使用旧脚本中清空整段推荐或删除正常内容的逻辑。接口更新、广告字段改变或其他未覆盖 App 的同域信息流，仍可能有广告。2 MiB 请求体上限与 3 秒脚本超时用于控制移动端资源，不以无限内存换拦截率。MITM 按主机发生，不是只解密匹配的 URL；这些 API 可能含个人内容，需自行信任本地证书。

### YouTube（独立、需真机验证）

固定 Maasea 提交 `65075cdb388fc5e3094afd7e7314c67b243f3525` 的完整三钩子：API 响应、initplayback 请求、log_event 请求。采用 Stash 原生 `binary-mode: true` / `require-body: true`，上传按钮隐藏为 true、Shorts 隐藏为 false、翻译关闭；没有用空响应自制替代上游完整处理。

**重要隐私与稳定性边界：**上游 initplayback 命中缓存条件时会把目标播放 URL、相关 key/参数交给 `init-stream.maasea.workers.dev` 第三方 Worker 处理。固定脚本提交不能固定这个 Worker 的服务端代码、可用性或未来行为。只有接受此额外依赖才启用覆写；不接受则不要启用，不会自动发送。不能将其描述为“全程纯本地去广告”。主配置将 Worker 与视频流放在同一 YouTube 策略，避免分流到直连。

上游 README 明确仅基于 Surge 测试，不保证其他客户端。本次只完成 Stash API 形式适配和隔离样本检查，**未在 iPhone 证明播放广告、PiP 或隐藏按钮效果**。服务端插播、地区/账号实验、YouTube 更新都可能改变结果。5 MiB/10 秒限制保护内存，超过大小的响应不执行脚本，因此也可能漏广告。

不能承诺“所有 App / YouTube 100% 无广告且永不中断”。若广告保留，请提供 App/Stash 版本、广告出现位置和脱敏的匹配记录；不要提供 Cookie、完整鉴权 URL、账号密钥。若视频卡住，先关闭 YouTube 覆写保持主分流，对比同节点，以区分脚本/Worker与节点问题。

## 验收与回退

按顺序，每通过一项再继续：

1. 节点非空、至少两条节点可用；所有四个规则集和两个 YouTube 脚本（启用该覆写时）下载成功。
2. 关闭两份广告覆写，验证微信文字/语音、微博图片与视频、知乎正文、YouTube 普通视频、Gemini 对话、ChatGPT 对话。
3. App 覆写单独启用，对比时间线广告、正文/评论/搜索是否正常；检查 HTTP 记录中确实命中脚本。
4. 同意第三方风险后单独启用 YouTube 覆写，彻底退出再打开 YouTube。测试首页、搜索、片头/中插、Shorts、PiP、上传按钮，至少播放两段不同视频各 15 分钟。看到 MITM 不等于看到脚本执行成功。
5. 在非关键会话中测试 Wi-Fi ↔ 蜂窝切换；有可控失效节点时验证 fallback 切至备用节点。记录恢复时间，不以测速颜色代替真实播放。
6. 换机场本地覆写测试一次，再刷新主配置，确认私有 URL 仍保留、使用的是新节点。

回退不删旧配置：广告误伤关闭对应覆写；只关网络广告选 `广告过滤 → DIRECT`；网络异常先固定已验证可用节点对比；整体回退切回之前的配置。不要为本次故障联动修改其他客户端。

## 维护检查与依据

检查脚本不上传本地文件、不访问机场订阅：

```text
python proxy-configs/scripts/test-stash-pro.py --online
```

需安装 PyYAML，或传入 `--dependency-dir` 指向已安装的隔离目录。Node.js 用于隔离 JavaScript 样本测试。`--online` 会校验 4 个公开 YAML 规则集的 payload 和 2 个固定版本 JS，保持 TLS 校验开启。全仓旧巡检并未因本次新配置而替代运行；本次检查仅覆盖新增配置依赖。

官方依据：

- [节点订阅：格式、缓存、空集行为](https://stash.wiki/en/proxy-protocols/proxy-providers)
- [策略组：fallback、手动选择、空组行为](https://stash.wiki/en/proxy-protocols/proxy-groups)
- [测速结果跨组共享](https://stash.wiki/en/proxy-protocols/proxy-benchmark)
- [覆写：字典递归合并、数组前插](https://stash.wiki/en/configuration/override)
- [Fake-IP、DNS 与高效规则](https://stash.wiki/en/faq/effective-stash)
- [DNS 功能及版本门槛](https://stash.wiki/en/features/dns-server)
- [脚本二进制接口](https://stash.wiki/en/script/rewrite-requests)
- [内嵌脚本支持](https://stash.wiki/en/script/manage-script)
- [MITM 证书与安全要求](https://stash.wiki/en/http-engine/mitm)
- [YouTube 上游固定模块](https://github.com/Maasea/sgmodule/blob/65075cdb388fc5e3094afd7e7314c67b243f3525/YouTube.Enhance.sgmodule)

不要把旧项目说明里的“Stash 不支持 protobuf”或“只要 Google 探针通过就证明视频通畅”当作本配置结论；它们与当前文档或测试边界不符。
