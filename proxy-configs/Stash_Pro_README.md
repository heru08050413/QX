# Stash Pro V26.00

新配置，内部修订 `1.0.3`，2026-09-25。原有 Stash、Shadowrocket、Egern、Loon、Quantumult X 文件均不改动。

初版核对的 [App Store 正式版为 3.4.1](https://apps.apple.com/us/app/stash-rule-based-proxy/id1596063349)。本方案不依赖 Wiki 标注 3.6+ 的字段。桌面静态/脚本测试不等于 iPhone 原生验收。

## 文件与安装

| 文件 | 用途 | 必需条件 |
| --- | --- | --- |
| [Stash_Pro_Policy_V26.00.stoverride](Stash_Pro_Policy_V26.00.stoverride) | 推荐：叠加在已能显示节点的机场配置上，接管分流与策略组 | 机场配置需提供节点 |
| [Stash_Pro_V26.00.yaml](Stash_Pro_V26.00.yaml) | 备用独立模板：内置 DNS、分流、策略组 | 需在主配置中填写有效机场 URL |
| [Stash_Pro_AppAds_V26.00.stoverride](Stash_Pro_AppAds_V26.00.stoverride) | 微博/知乎/小红书明确广告项、部分开屏 | 自己的 MITM CA；可独立关闭 |
| [Stash_Pro_YouTube_V26.00.stoverride](Stash_Pro_YouTube_V26.00.stoverride) | YouTube 广告/PiP/上传按钮增强 | 阅读下方第三方 Worker 风险后自行启用 |

推荐策略覆写地址（发布到 main 后使用）：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_Policy_V26.00.stoverride
```

备用独立模板地址：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_V26.00.yaml
```

两份可选去广告覆写地址：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_AppAds_V26.00.stoverride
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_YouTube_V26.00.stoverride
```

1. 在 Stash 中选中**已经单独导入成功、能够看到节点的机场配置**。保留它作为当前配置，先不要开启 VPN。
2. 在 Override 中停用并移除旧的「Stash Pro 私有机场入口」。从上方 GitHub 地址导入并启用 **Stash Pro 分流策略**覆写。不要再选 `Stash_Pro_V26.00.yaml` 作为当前配置；机场节点由已选的机场配置提供。
3. 更新机场配置，查看 `手动节点`、`稳定切换`、`美国节点`、`新加坡节点` 是否列出预期节点，并确认美国池至少两条测速成功；核对节点证书验证未被机场关闭。才开启 VPN。**空地区池可能退化为 DIRECT；如果美国池为空，保持 VPN 关闭并核对机场节点名，不能把空组当代理。**
4. 新导入时 `默认代理`、`YouTube`、`AI`、`Google`、`国际媒体` 首选美国池；`Spotify` 首选新加坡池。`AI` 和 `国际媒体` 只展示策略组选项，不再把机场节点逐条铺在组内；需要固定单节点时进入 `手动节点`。Stash 可能保留同名策略组以前的手动选择；刷新后逐项查看当前选择，必要时手动选回“美国节点”或“新加坡节点”。固定单节点不会自动切换。
5. 先验证基础连通，再逐个启用 App / YouTube 去广告覆写。启用 HTTPS 过滤需要在 Stash 内生成或选用**自己的** CA，安装并在 iOS 证书信任设置中完全信任，然后开启 MITM。公共文件不包含 CA、口令或真实订阅。
6. 不要同时开启旧 `Stash_All`、`Stash_Script` 或其他重叠的 YouTube/App 去广告模块。若切换到另一份 Stash 配置，检查这些覆写是否仍适合该配置。

首次下载 GitHub 资源若失败，可先保持现有可用客户端/旧配置完成下载，随后关闭旧 VPN 再启用 Stash；不要同时运行多个 VPN。节点已下载但规则/脚本未下载，也不能算安装完成。

## 反复更换机场

推荐方式：在 Stash 中导入新的机场 Stash/Clash 配置，确认它单独有节点后选为当前配置；上面的公开策略覆写继续使用。无需填写本仓库中的机场 URL，也没有机场专用覆写和缓存文件名。机场配置若不包含可见节点，本策略覆写无法凭空生成节点。

备用独立模板 `Stash_Pro_V26.00.yaml` 仍可用于提供**可作为远程节点集加载**的机场订阅。此时只改该主配置中的 `Airport.url` 一行：

```yaml
proxy-providers:
  Airport:
    url: 'https://你的新机场提供的订阅地址'
```

备用模板不指定 `Airport.path`，无需手动递增缓存文件名。保存后手动更新 `Airport`，核对新节点与测速结果，再重启连接并检查各策略组。旧机场的节点手动选择不会自动映射到新机场；必要时重新选回 `稳定切换`。

**备用模板远程更新限制：**如果在 Stash 中直接编辑从 GitHub 下载的独立模板，日后重新下载/更新可能恢复公开占位地址。希望私有地址长期留在手机上，应将填写好地址的主配置作为本地配置保存。推荐方式由机场配置自己保存私有 URL，并由公开策略覆写从 GitHub 更新，两者互不覆盖。不要将含 token 的文件提交到任何仓库，也不要把私人订阅交给公共转换站。

这是**一个可反复替换的机场入口**，不是同时多机场聚合。订阅格式/服务端协议仍需 Stash 支持，不能承诺任意机场链接通用。

## 分流与稳定性

- 局域网和 DNS → 国内通信/支付关键功能域 → 广告过滤 → YouTube → AI → Google/国际媒体/Telegram → Apple/Microsoft → 国内清单与国内 IP → 默认代理兜底。
- 微博、知乎关键 API 先直连保护，广告混在正文 API 内时由 HTTP 脚本删除明确广告项。其余独立广告域仍受网络广告规则拦截，不整站放行广告。
- AI、Google、YouTube、Netflix/Disney/TikTok 等国际媒体、GitHub/未分类代理流量默认共用美国节点池；Spotify 单独默认新加坡池。Google 登录与 Gemini 同池，YouTube 仍可单独手选。Gemini/Copilot 显式规则优先于 Google/Microsoft 宽规则。Apple/iCloud 与普通 Microsoft 组继续保持 DIRECT，避免国内 iCloud、系统更新绕路；Copilot 走 AI 美国池。
- 推荐策略覆写保留机场配置原有的 DNS、隧道与节点参数，避免改动已能正常加载节点的基础网络。备用独立模板使用 Stash Fake-IP、国内 DoH 双上游与局域网系统 DNS；没有全匹配排除 `*`。两种方式都不能承诺“所有 DNS 零泄漏”；应用自带 DoH/纯 IP 请求需单独观察。
- 只有目标域的应用层 UDP 443 被拒绝，以便 YouTube / 被 MITM 的 API 改用 TCP。没有全局封杀 UDP，也没有修改 HY2/TUIC 节点隧道参数。仅靠此域名规则不保证覆盖所有无域名关联的 QUIC 请求。
- `稳定切换`、美国池和新加坡池均为原生 `fallback`，120 秒周期。推荐策略覆写沿用机场配置的节点测速超时；备用独立模板设为 8 秒。按订阅顺序取健康节点，优先节点恢复时可能切回；不声称“永不回切”。如订阅首个节点吞吐差，可在手机调整节点顺序或选手动节点。手动固定节点不自动故障切换。
- Stash 同一节点跨策略组共享测速结果。推荐策略覆写沿用机场配置的节点测速地址与超时，因此需核对其测速结果是否与 YouTube 实际可用性一致；备用独立模板在 `Airport` 上使用 Google HTTPS 204 探针。两者都不能以小包连通证明视频吞吐。
- 探针仅证明该测试地址可访问，**不代表 YouTube CDN 带宽、无广告、Gemini 地区准入或账户状态合格**。两分钟不是恢复时限保证；切换不能迁移既有 TCP/QUIC 会话，YouTube 仍可能短暂缓冲，全部节点故障时无法恢复。
- 美国池识别 `US1`/`US-1`/`USA`/`United States`、美国/美國/美西/美东/美中及 🇺🇸；新加坡池识别 `SG1`/`Singapore`、新加坡/狮城及 🇸🇬。边界匹配不会把 `AUS` 或 `RUS` 误认作 `US`。节点名是筛选依据，不证明实际出口国家；须在手机核对池内节点与出口 IP。机场改名或没有相应地区时池可能为空并退化为 DIRECT，不能自动切到别国，也不能在空池状态下启用代理。
- 策略组图标使用同一套 [Qure Color](https://github.com/Koolson/Qure) PNG 地址；首次显示需要能访问 GitHub Raw。Stash 本机若设置过策略组图标的本地覆写，可能优先显示本机自选图标。

## 去广告范围与风险

### 网络层（推荐策略覆写或备用独立模板生效）

使用单一 Loyalsoldier `release/reject.txt`，每天更新；规则为 `domain` 索引格式，不叠加数套重复的大清单。国内路由、私有域名和 CN IP 亦采用 indexed 清单。它们是动态外部依赖，某次 HTTP 200 不代表以后永远正确；缓存不能替代首次下载。

策略中的 `广告过滤 → DIRECT` 可临时排查网络误杀，不影响其他分流；它不会关闭 HTTP 脚本。不要通过取消 TLS 校验解决下载问题。

### App 信息流（可选覆写）

小型内嵌脚本只处理声明的微博时间线、知乎推荐/next 接口、小红书首页/搜索/开屏。仅删除识别到的明确广告标记，保留普通推荐、正文、评论、付费条目及分页字段。空响应、非 JSON、错误状态、未知结构返回 `$done({})` 保留原响应；不打印用户内容、不请求外部服务、不读持久存储。

不使用旧脚本中清空整段推荐或删除正常内容的逻辑。接口更新、广告字段改变或其他未覆盖 App 的同域信息流，仍可能有广告。2 MiB 请求体上限与 3 秒脚本超时用于控制移动端资源，不以无限内存换拦截率。MITM 按主机发生，不是只解密匹配的 URL；这些 API 可能含个人内容，需自行信任本地证书。

### YouTube（独立、需真机验证）

固定 Maasea 提交 `65075cdb388fc5e3094afd7e7314c67b243f3525` 的完整三钩子：API 响应、initplayback 请求、log_event 请求。采用 Stash 原生 `binary-mode: true` / `require-body: true`，上传按钮隐藏为 true、Shorts 隐藏为 false、翻译关闭；没有用空响应自制替代上游完整处理。

**重要隐私与稳定性边界：**上游 initplayback 命中缓存条件时会把目标播放 URL、相关 key/参数交给 `init-stream.maasea.workers.dev` 第三方 Worker 处理。固定脚本提交不能固定这个 Worker 的服务端代码、可用性或未来行为。只有接受此额外依赖才启用覆写；不接受则不要启用，不会自动发送。不能将其描述为“全程纯本地去广告”。推荐策略覆写和备用模板均将 Worker 与视频流放在同一 YouTube 策略，避免分流到直连。

上游 README 明确仅基于 Surge 测试，不保证其他客户端。本次只完成 Stash API 形式适配和隔离样本检查，**未在 iPhone 证明播放广告、PiP 或隐藏按钮效果**。服务端插播、地区/账号实验、YouTube 更新都可能改变结果。5 MiB/10 秒限制保护内存，超过大小的响应不执行脚本，因此也可能漏广告。

不能承诺“所有 App / YouTube 100% 无广告且永不中断”。若广告保留，请提供 App/Stash 版本、广告出现位置和脱敏的匹配记录；不要提供 Cookie、完整鉴权 URL、账号密钥。若视频卡住，先关闭 YouTube 覆写保持主分流，对比同节点，以区分脚本/Worker与节点问题。

## 验收与回退

按顺序，每通过一项再继续：

1. `美国节点`、`新加坡节点` 非空，美国池至少两条节点可用，出口地区符合预期；所有四个规则集和两个 YouTube 脚本（启用该覆写时）下载成功。
2. 关闭两份广告覆写，验证微信文字/语音、微博图片与视频、知乎正文、YouTube 普通视频、Gemini 对话、ChatGPT 对话。
3. App 覆写单独启用，对比时间线广告、正文/评论/搜索是否正常；检查 HTTP 记录中确实命中脚本。
4. 同意第三方风险后单独启用 YouTube 覆写，彻底退出再打开 YouTube。测试首页、搜索、片头/中插、Shorts、PiP、上传按钮，至少播放两段不同视频各 15 分钟。看到 MITM 不等于看到脚本执行成功。
5. 在非关键会话中测试 Wi-Fi ↔ 蜂窝切换；有可控失效节点时验证 fallback 切至备用节点。记录恢复时间，不以测速颜色代替真实播放。
6. 推荐方式切换到新的机场配置并更新，确认新节点出现在“手动节点”和“稳定切换”中；备用独立模板换机场时修改 `Airport.url`，重新下载 GitHub 模板后需再次填写私有 URL。

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
