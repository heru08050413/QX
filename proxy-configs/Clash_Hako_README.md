# Clash by Hako · iPhone 配置生成器

V26.00 / revision 1 · 2026-09-20。目标客户端：用户提供的 iOS **1.0.9**。

这是一个在手机内运行的 `main(config)` 配置生成脚本，采用 V3 式“保留机场 DNS/TUN、重建分流”的方案；不是机场订阅，也不是可直接导入为 Profile 的 YAML。机场节点、密码和订阅链接不进入本仓库。其他客户端文件不变。

## 导入：先有机场，再绑定脚本

脚本地址：

<https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Clash_Hako_V26.00.js>

1. 保留当前能联网的配置作为回退。在 Hako 中导入机场的 **Clash/mihomo 完整配置订阅**，先确认原始节点能用。
2. 打开 **Scripts / 脚本**，添加脚本，来源选 **URL**，粘贴上面的地址，导入并保存。可以先用 **Test Run** 检查接口。
3. 在该机场配置的 **Override / 覆写**中，模式选择 **Script**，在 **Override Script** 选择刚保存的脚本，然后保存并重新激活配置。不要把 `.js` 链接填到机场订阅入口。
4. 只启用这一套分流生成器；不要同时叠加 Runestone V1/V2/V3、旧全局分流脚本或自定义策略组。官方源码的 Profile Script 在全局覆写之前执行，全局覆写仍可能改变输出。若界面提供合并后脚本，可在该位置使用本脚本，但同样只绑定一次；不要同时绑定两个位置。
5. 首次加载等待 10 个规则集合完成下载，检查规则数、策略组及节点。下载失败时先用原配置联网后重试，不要把失败当成广告拦截已经生效。

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
| `QXH-代理` | 全节点自动测速，300 秒、150 ms 切换容差；可手动固定 |
| `QXH-YouTube` | JP → SG → TW → HK → US → OTHER 的地区故障转移；每个存在的地区先按 Google 探针选点 |
| `QXH-AI` | 美国 → 日本 → 新加坡 → 台湾节点的顺序故障转移，避免按最快延迟频繁轮换出口 |
| `QXH-Google` | 默认通用代理，不被视频策略组牵动；Google 账户登录单独跟随 AI 出口 |
| `QXH-Telegram` | 通用代理；域名和 Telegram IP 均有分流 |
| `QXH-广告` | 默认 REJECT；临时选 PASS 后继续匹配后面的规则，不会把全部广告域名改为直连 |
| 国内 / 内网 | 私有网段、必要国内服务直连；CN 域名 + CN IP 兜底 |
| 未分类流量 | 代理，不在全部节点坏掉时偷偷直连 |

YouTube 地区池 120 秒、外层故障转移 60 秒，Google HTTPS 204 探针；不是“60 秒内一定修好”，实际检查受懒检查、系统调度和节点状态影响。150 ms 容差用于减少小幅延迟波动引起的切换。探针仅代表基础可达，不验证吞吐、视频 CDN、AI 地区资格或账户授权。

仅对 YouTube/Googlevideo/YouTube API 的 **应用侧 UDP 443** 拒绝，促使应用使用 TCP。不封所有 UDP，不禁微信语音，不改 Hysteria2/TUIC 节点的底层 QUIC 传输。

地区来自节点名称，不能证明真实出口国家。无 US/JP/SG/TW 候选时，AI 默认 REJECT，需在 `QXH-手动` 选已验证可用的节点，再把 `QXH-AI` 切到该手动组；Google 账户登录也受此选择影响。`QXH-手动` 是共享手动入口，多个服务选择它时会跟随同一个节点。

**自动切换不会迁移已经建立的连接。**坏节点、Wi-Fi/蜂窝切换、服务端限制仍可能造成一次重连或缓冲。全机场不可用时，脚本无法恢复网络。聊天长连接和视频的真实表现必须在手机上验收。

## 去广告：覆盖与边界

使用 [217heidai 的合并去重 MRS 广告规则](https://github.com/217heidai/adblockfilters)，其余服务与国内分流来自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)。只使用 Raw 地址，不依赖第三方 CDN/转换站；采用 MRS，避免叠加几份巨型文本名单。

这是**独立广告域名拦截**，不是 HTTP 响应体改写。不会自动安装证书、开启 MITM、添加第三方视频 Worker，也不把 `googlevideo.com` 整站拒绝。**不能保证 YouTube 内嵌广告、信息流原生广告全部消失，不提供 PiP 或上传按钮隐藏。**也不声称 Hako 所有其他功能均不支持这些能力；本交付只覆盖已核对的配置生成与路由接口。

为避免重现微信/微博/知乎转圈，微信关键域名、微博主站/API、知乎及图片域、Apple 推送先直连。这意味着这些保护范围内的广告域名也会被放行，是明确的连通性优先取舍，不是“去广告 100%”的承诺。

误拦截排查：临时将 `QXH-广告` 改为 PASS，再彻底退出并重开故障 App；若恢复，请提供**被拦域名 + 命中规则 + 时间**，不要提供订阅 token。不要直接把整个配置切成全局 DIRECT。确认后恢复 REJECT。

## 安全与保留字段

- DNS、TUN、IPv6、hosts 以及未接管的字段保留原值；不照抄桌面端口、TUN 设备名或外部控制器。这也意味着**不能自动修好原机场已有的 DNS 问题或不安全监听设置**。请关闭 App 的局域网共享/外部控制服务，保留自己已验证可用的网络参数。
- 改动范围：`mode=rule`、`allow-lan=false`、记住手选节点、节点已有的 `skip-cert-verify` 强制 `false`、替换策略组/规则集/路由规则。自签名或错误证书节点可能因此失败，应修正证书，不建议关校验。
- 不记录或传出配置内容；脚本无网络 API 调用。远程规则下载和探针仍是外部依赖，规则源也可能发生误拦截或不可用。
- 节点重名、保留名冲突、空机场、节点链循环会直接报错，不生成静默 DIRECT 配置。

## 已验证 / 待手机验收

已完成 JavaScript 语法、28 项离线回归、10 份远程 MRS 的标识校验和原生完整解码、10 个实际规则数据路由夹具、2 个 HTTPS 204 探针，以及 mihomo 1.19.31 的 4 类模拟配置 `-t` 语法检查。详见 [审查记录](reviews/clash-hako-2026-09-20.md)。

**不是 Hako 1.0.9 真机认证。**官方客户端源码没有可明确对应你 iOS 1.0.9 二进制的公开标签；本机不能运行 Apple JavaScriptCore/Network Extension。不能把 Windows mihomo 检查说成手机导入实测。

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
