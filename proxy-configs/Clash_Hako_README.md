# Clash by Hako · iPhone 配置生成器

V26.00 / revision 4 · 2026-11-27。目标客户端：用户提供的 iOS **1.0.9**。

这是一个在手机内运行的 `main(config)` 配置生成脚本：保留已验证的加密 DNS/TUN 与节点凭据，对缺失或混入明文公共 DNS 的底包自动加固为安全加密分流 DoH，并注入 `sniffer` 嗅探、120s 快速切网保活、HTTPDNS 阻断与开屏 API QUIC 防逃逸规则；不是机场订阅，也不是可直接导入为 Profile 的 YAML。机场节点、密码和订阅链接不进入本仓库。

## 导入：先有机场，再绑定脚本

脚本地址：

<https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Clash_Hako_V26.00.js>

1. 保留当前能联网的配置作为回退。在 Hako 中导入机场的 **Clash/mihomo 完整配置订阅**，先确认原始节点能用。
2. 打开 **Scripts / 脚本**，添加脚本，来源选 **URL**，粘贴上面的地址，导入并保存。可以先用 **Test Run** 检查接口。
3. 在该机场配置的 **Override / 覆写**中，模式选择 **Script**，在 **Override Script** 选择刚保存的脚本，然后保存并重新激活配置。不要把 `.js` 链接填到机场订阅入口。
4. 只启用这一套分流生成器；不要同时叠加 Runestone V1/V2/V3、旧全局分流脚本或自定义策略组。官方源码的 Profile Script 在全局覆写之前执行，全局覆写仍可能改变输出。若界面提供合并后脚本，可在该位置使用本脚本，但同样只绑定一次；不要同时绑定两个位置。
5. 首次加载等待 11 个规则集合完成下载，检查规则数、策略组及节点。下载失败时先用原配置联网后重试，不要把失败当成广告拦截已经生效。

菜单名称以手机界面为准，上述名称来自官方源码。App 的 Test Run 使用内置示例配置，不是你真实机场的连通测试。

**适用范围：**源配置必须有非空 `proxies`。仅有 `proxy-providers`、或混有运行时 Provider 的配置，这一版会明确拒绝，避免伪造节点列表。应向机场选择完整 Clash/mihomo 输出；不要手动删 Provider 来绕过检查。复杂链式配置、DNS/TUN 依赖被替换旧组/旧规则集时，也会停止并提示。普通单机场完整订阅可反复更换。

## 机场与脚本如何分别更新

- **同一机场刷新节点：**更新机场 Profile，保留脚本绑定，重新激活后生成新策略组。
- **更换机场：**导入新机场的完整 Profile，测试节点，再给新 Profile 绑定同一脚本。机场链接只放手机；旧机场停止使用后可以在 App 中删除其 Profile。
- **更新本仓库脚本：**在脚本编辑器重新从上述 URL 导入并保存，再激活机场配置。官方 `ConfigScript` 保存的是脚本文本，没有远程订阅刷新字段；不要认为刷新机场会自动下载新脚本。
- **规则更新：**Rule Provider 配置为每天刷新；Hako 的 MRS 更新可能需再次激活配置才应用，以 App 中更新时间为准。
- 关闭/更换生成脚本后，重新激活原机场配置即可回退，不需要删除节点或重装 App。

## 分流与稳定性

| 入口 | 默认行为 |
| --- | --- |
| `QXH-代理` | 全可用节点（自动过滤信息条）按 Google 204 探针自动测速，300 秒、100 ms 切换容差；可手动固定 |
| `QXH-YouTube` | JP → SG → TW → HK → US → OTHER 的单层地区故障转移（与地区池共用 Google 探针，消除双倍重复测速） |
| `QXH-AI` | 美国 → 日本 → 新加坡 → 台湾节点的顺序故障转移，避免按最快延迟频繁轮换出口 |
| `QXH-Google` | 默认通用代理，与 YouTube / AI 组完全隔离（纯港节点机场不阻断 Google 登录）；Google 账户认证与 FCM 归此组 |
| `QXH-Telegram` | 通用代理；域名和 Telegram IP 均有分流 |
| `QXH-广告` | 默认 REJECT；临时选 PASS 后继续匹配后面的规则，不会把全部广告域名改为直连 |
| 国内 / 内网 / Tailscale | 私有网段、Tailscale（`ts.net` / `tailscale.com` / `tailscale.io` / `fd7a:115c:a1e0::/48`）、必要国内服务与运营商一键登录直连；CN 域名 + CN IP 兜底 |
| 未分类流量 | 代理，不在全部节点坏掉时偷偷直连 |

各地区池采用 300 秒、外层 `QXH-YT故障转移` 采用 120 秒 Google HTTPS 204 单一套探针（全组启用 `lazy: true`）；不是“120 秒内一定修好”，实际检查受懒检查、系统调度和节点状态影响。100 ms 容差用于果断切走劣化节点并抑制小幅抖动，同时注入 `tcp-concurrent: true` 与 `keep-alive-idle: 120` 加速蜂窝切网恢复。

仅对 YouTube 相关域与国内高频开屏/信息流 API（微博、知乎、小红书、手淘、闲鱼、京东、高德、拼多多、B 站、有道、微信公众号）的 **应用侧 UDP 443** 拒绝，促使应用使用 TCP 并防止 `Alt-Svc` 升级 HTTP/3 绕过外挂去广告模块。不封所有 UDP，不禁微信语音，不改 Hysteria2/TUIC 节点的底层 QUIC 传输。

地区来自节点名称，不能证明真实出口国家；“剩余流量/到期/官网”等信息条自动从测速池排除（仅保留在 `QXH-手动`）。无 US/JP/SG/TW 候选时，AI 默认 REJECT，需在 `QXH-手动` 选已验证可用的节点，再把 `QXH-AI` 切到该手动组（不会影响 Google 账户登录）。`QXH-手动` 是共享手动入口，多个服务选择它时会跟随同一个节点。

**自动切换不会迁移已经建立的连接。**坏节点、Wi-Fi/蜂窝切换、服务端限制仍可能造成一次重连或缓冲。全机场不可用时，脚本无法恢复网络。聊天长连接和视频的真实表现必须在手机上验收。

## 去广告：覆盖与边界

使用 [217heidai 的合并去重 MRS 广告规则](https://github.com/217heidai/adblockfilters)，其余服务与国内分流来自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)。只使用 Raw 地址，不依赖第三方 CDN/转换站；采用 MRS，避免叠加几份巨型文本名单；高频遥测域名（如 `umc.danuoyi.alicdn.com`、`Aisou.ialicdn.com`、`xz/xy.fbcdn.net`）采用 `REJECT-DROP` 静默丢包防死循环重连。

这是**独立广告域名拦截**，不是 HTTP 响应体改写。不会自动安装证书、开启 MITM、添加第三方视频 Worker，也不把 `googlevideo.com` 整站拒绝。**不能保证 YouTube 内嵌广告、信息流原生广告全部消失，不提供 PiP 或上传按钮隐藏。**也不声称 Hako 所有其他功能均不支持这些能力；本交付只覆盖已核对的配置生成与路由接口。

为避免重现微信/微博/知乎/运营商一键登录转圈，微信（含 TEG、`wx.qq.com`、`qq.com.cn`）、微博主域与图床/SDK 启动域、知乎及图片域、支付宝/个推探测、Apple 推送、三大运营商一键登录域先直连；ChatGPT 监控域 `browser-intake-datadoghq.com` 走 `QXH-AI`。这意味着这些保护范围内的广告域名也会被放行，是明确的连通性优先取舍，不是“去广告 100%”的承诺。

误拦截排查：临时将 `QXH-广告` 改为 PASS，再彻底退出并重开故障 App；若恢复，请提供**被拦域名 + 命中规则 + 时间**，不要提供订阅 token。不要直接把整个配置切成全局 DIRECT。确认后恢复 REJECT。

## 安全与保留字段

- 已配置纯加密 DoH 的 `dns`、以及 `tun`、`ipv6`、`hosts` 保留原值；若机场底包缺失 `dns` 或在 `nameserver`/`fallback` 混入明文公共 UDP DNS（如 `8.8.8.8`/`114.114.114.114`），脚本会自动收敛为 `Fake-IP + respect-rules` 加密分流 DoH（海外走代理隧道 Cloudflare/Google DoH，国内走加密 IP-DoH）；若底包未定义 `sniffer` 则自动注入纯 IP 域名嗅探（`override-destination: false`）。请关闭 App 的局域网共享/外部控制服务。
- 改动范围：`mode=rule`、`allow-lan=false`、记住手选节点、节点已有的 `skip-cert-verify` 强制 `false`、替换策略组/规则集/路由规则。自签名或错误证书节点可能因此失败，应修正证书，不建议关校验。
- 不记录或传出配置内容；脚本无网络 API 调用。远程规则下载和探针仍是外部依赖，规则源也可能发生误拦截或不可用。
- 节点重名、保留名冲突、空机场、节点链循环会直接报错，不生成静默 DIRECT 配置。

## 已验证 / 待手机验收

已完成 JavaScript 语法检查与离线回归（详见 [test-clash-hako.cjs](scripts/test-clash-hako.cjs)；历史 revision 1 曾进行 10 份 MRS 完整解码、10 个路由夹具与 mihomo 1.19.31 `-t` 检查，revision 3 单一套探针池尚未重跑 `mihomo -t`）。

**不是 Hako 1.0.9 真机认证。**官方客户端源码没有可明确对应你 iOS 1.0.9 二进制的公开标签；本机不能运行 Apple JavaScriptCore/Network Extension，也未在本环境运行新版 `mihomo -t`。不能把离线检查说成手机导入实测。

请依次验收：

1. 激活无报错、10 个集合加载成功、没有空策略组；先使用少量已验证节点。
2. Wi-Fi 与蜂窝各测微信消息/语音、微博、知乎；记录异常域名和命中规则。
3. YouTube 连续播放至少 15 分钟，拖动进度/切清晰度，观察缓冲；再测一次网络切换，允许正常重连。
4. 分别测 ChatGPT、Gemini 登录及新对话；探针绿不代表 AI 服务必定可用。
5. 通过节点故障或手动切换观察后续连接是否恢复；不要在支付/上传/通话中测试。

测试命令（仓库根目录，Node 24+）：

```powershell
node --check proxy-configs/Clash_Hako_V26.00.js
node proxy-configs/scripts/test-clash-hako.cjs
node proxy-configs/scripts/test-clash-hako.cjs --online
# 可选：已从官方发布页下载并校验的 mihomo，仅执行 -t，不启动代理。
node proxy-configs/scripts/test-clash-hako.cjs --online --core C:\path\mihomo.exe
```

参考：[Hako 代理组](https://clash.md/zh/guide/config/proxy-groups)、[MRS 与 iOS 内存](https://clash.md/zh/guide/config/best-practice)、[日常使用与连接切换](https://clash.md/zh/guide/everyday-use)。你提供的新版 Runestone 仓库用于接口/设计比对，本脚本独立实现，不远程执行其代码，也不同时套用 V1/V2/V3。
