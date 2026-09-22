# Shadowrocket v2.6.19：Google/Gemini 对齐、Muse/Meta 补漏、美国默认

基线：bedea9364b324e240a36ceb6344388b022650967（v2.6.18）。用户要求先审查确认问题再修复；已完成配置与本地日志交叉核验。仅修改 Shadowrocket 配置及其测试和本说明，其他客户端不变。沿用用户此前授权的 main 发布方式。

## 已确认的问题

1. 原 Google 默认 AutoSelect，Gemini 默认美国节点，两组可独立选择。日志也分别出现 Google 登录/令牌请求走 AutoSelect、Gemini 专用接口走美国节点的记录。这证明存在路由分离条件，不证明它就是全部登录故障的唯一原因。
2. Muse/Meta 的 hatch-api.meta.ai、api.meta.ai、ar.graph.meta.com 在日志中落入 FINAL 直连；配置缺少对应根域。Facebook 与其 CDN 已有代理规则，形成了业务 API 与既有 Meta 资源路由不一致的问题。
3. AI、Netflix、TikTok、Telegram、Proxy 和谷歌服务的初始选择，以及 YT-Auto 的首选地区，不符合用户新的美国默认偏好；这是需求调整，不把原地区选择一概认定为错误。

用户提供的原始数据库、查询参数、账号和节点信息不纳入提交。此处只记录修复所需的域名和策略关系。

## 修复内容

### Google/Gemini 使用同一个控制入口

- `Gemini = select, 谷歌服务`：不再保留会独立偏离的 Gemini 地区选项。需要换地区时，在“谷歌服务”里选择，Gemini 随之跟随。
- 谷歌服务首选“美国节点”；不默认进入 YouTube 的高频检测池。原有手动备选保留。
- accounts.google.com、oauth2.googleapis.com、securetoken.googleapis.com、identitytoolkit.googleapis.com 增加精确本地规则，位于广告拦截之后、后续 YouTube 远程表之前，避免其 UA/IP 规则抢先接管这些共享登录端点。
- google.com、googleapis.com、gstatic.com、googleusercontent.com 增加本地兜底，位于 Gemini/YouTube 专用规则之后、Google 远程表之前。保留 YouTube API、视频、Worker 的专用策略和 QUIC 控制。
- 同一策略入口并不保证正在使用的所有旧连接立即变成同一 IP；选组改变后需要让应用重建连接。机场节点名称也不证明实际出口地区或账号可用性。

### Muse/Meta 补齐代理并统一相关选择器

- 新增 `Meta` 手动选择组，默认美国节点，其他地区和 AutoSelect 可手动选择。
- muse.ai、meta.ai、meta.com 采用有域名边界的 DOMAIN-SUFFIX 规则，包含 auth 和 API 子域，不使用宽泛的 `DOMAIN-KEYWORD,meta`。
- 现有 facebook.com、fbcdn.net、fb.com、whatsapp.com、whatsapp.net 统一指向 Meta，减少手动换 Meta 出口时账号/API/CDN 再次分离。这个变更也影响 Facebook/WhatsApp 的选组入口，后续在 Meta 组中切换。
- Instagram/Threads 保留原独立稳定组，不把所有 Meta 产品强行合并。
- 新规则没有提前到广告规则之前，xz/xy.fbcdn.net 跟踪拦截仍保留；未新增 Meta MITM、脚本、第三方订阅或 DNS 覆写。
- 仅补齐已确认归属的域；仍可能存在尚未采集的新业务域名，不能宣称 Muse 所有功能已在真机验证。

### 初始默认值

| 服务/入口 | 更新后的初始默认 |
|---|---|
| Proxy、AI、Meta、Netflix、TikTok、Telegram | 美国节点 |
| 谷歌服务 | 美国节点 |
| Gemini | 跟随谷歌服务，初始美国节点 |
| YouTube | YT-Auto → 优先 YT-美国节点 |
| Instagram、Twitter | 美国稳定，原值不变 |
| 苹果服务、微软服务选择器 | 美国节点；显式国内直连例外不变 |
| Spotify | 新加坡节点，原值不变 |
| 哔哩哔哩、Final | DIRECT，保留国内业务与漏网直连设计 |

YT-Auto 的顺序变为美国→香港→台湾→日本→新加坡。它仍可在美国池不可用时自动跨地区回退，用户也可在 YouTube 中手动选地区。30 秒检测、5 秒超时、地区池 300 毫秒容差均保持 v2.6.18 的值，不承诺无中断。

本次“其余默认美国”按代理业务理解，不把国内应用、局域网、Apple 国内 CDN、证书检查、广告拒绝或 FINAL 一概改为美国。苹果服务选择器的默认变化不代表所有 Apple 流量都改走代理：已有显式 DIRECT、skip-proxy 和 DNS 条目未变。

本轮用户明确要求的美国默认与 Google/Gemini 对齐，取代旧 CLAUDE.md/历史注释中的 Google 默认 AutoSelect 偏好；其他安全约束保持。机场订阅、地区筛选和节点凭据未修改。

## 验证与证据边界

- 以不可变提交逐层重建 v2.6.16—v2.6.18 基线，再仅允许本批 15 条有效行替换、12 条新增（1 个组、3 条 Meta 规则、8 条 Google 规则）。其他有效行不允许修改、删除或重排。
- 静态检查 72 个美国节点正则样本、全部组引用和循环、16 个默认入口、29 个本地域名路由样本，以及 Google 手动选择每个备选后 Gemini 的跟随关系。
- 29 个内存负向变异测试，覆盖 Gemini 再次分离、组循环、Muse 子域漏网、Meta 匹配过宽、CDN 再次分离、Google 前置登录规则丢失、Spotify 改区、国内兜底改变、跟踪域放行和旧的去广告/探针/DNS/MITM 回归。
- 审查时现用 Advertising.list、Advertising_Domain.list、Privacy.list、Hijacking.list 均 HTTP 200；15 个 Google/Meta 核心测试主机未命中这些表的域名/关键词规则。此检查不模拟 URL、UA、IP 和手机加载状态，未来上游变化需复核。
- `[General]`、`[Host]`、`[URL Rewrite]`、`[Script]`、`[MITM]` 有效内容保持不变。没有重新生成证书、关闭证书校验或取消去广告。
- 测试不是 Shadowrocket 原生解析器，也不是 iPhone 端登录、播放、广告或 Muse 执行能力测试。

运行：

```powershell
pwsh -NoProfile -File proxy-configs/scripts/test-shadowrocket-known-fixes.ps1
pwsh -NoProfile -File proxy-configs/scripts/test-shadowrocket-audit-mutations.ps1
git diff --check
```

## 手机更新与验收

1. 刷新并启用原 shadowrocket_V26.00.lsr 远程配置，确认文件头 2026-09-23 / v2.6.19。日常全局路由保持“配置”。不需要换链接、重新添加机场或重装证书。
2. 客户端可能保留原手动选择，刷新不保证自动重置所有组。核对：谷歌服务→美国节点；Gemini→谷歌服务；Meta→美国节点；YouTube→YT-Auto；Spotify→新加坡节点；其他代理业务选择美国节点或原有美国稳定组。
3. 后续更改 Google/Gemini 地区只操作“谷歌服务”，不要额外模块重新定义 Gemini。Meta 的相关账号/API/CDN 在“Meta”组统一修改；Instagram 仍是独立组。
4. 在同一网络下分别测试 Google 登录与搜索、Gemini 登录和连续回复、Muse 登录/发送/附件，以及 Facebook/WhatsApp。对 Muse 涉及发送消息、购买等外部动作，仅进行用户主动选择的功能测试，不自动代操作。
5. 回归 YouTube 广告、PiP、上传按钮和至少 30 分钟连续播放，Spotify 播放及国内微信/微博/图片。比较延迟和耗电；美国出口不保证比亚洲出口更快。
6. 如果仍有直连或登录失败，请提供失败时间、相关域名、命中规则和有效组选择，隐藏 URL 查询参数、token 和账号。不要只依赖地区名称判定服务限制。

## 影响及回退

收益：消除已确认的 Meta API 漏分流；Google/Gemini 改为同一控制入口；统一用户要求的代理业务初始地区。

代价：相比香港/日本/新加坡，美国节点可能延迟更高、吞吐更低，流媒体地区内容也可能变化；服务仍可能受出口 IP 信誉、地区、账号或节点故障限制。本批未增加检测频率、解密范围或脚本负担，但美国出口带来的网络时延需实测。

回退只 revert 本批提交，再刷新手机配置并检查原手动选项；不要 hard reset 整个仓库。本批不执行上一份日志审查中抖音、微信或微博的其他候选修复。

## 来源

- [Meta 官方：Muse 产品与 muse.ai 入口](https://ai.meta.com/learn/agentic-ai/what-is-agentic-ai/)。
- [Meta 官方：Meta AI 的 meta.ai、App 和关联产品](https://ai.meta.com/meta-ai/assistant/)。
- [当前 Google 上游规则](https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/Google/Google.list)。
- [当前 YouTube 上游规则](https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/YouTube/YouTube.list)，包含 UA/IP 条目，故共享登录规则需考虑先后顺序。
